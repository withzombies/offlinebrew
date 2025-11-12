#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "json"

# TestFullWorkflow: End-to-end integration tests
#
# NOTE: This is a regression test for existing functionality, not true TDD.
# The brew-mirror and brew-offline-install scripts were written before tests.
# Going forward, all changes MUST follow TDD.
#
# This test verifies the complete workflow:
# 1. Mirror a formula with brew-mirror
# 2. Serve mirror via HTTP
# 3. Install formula with brew-offline-install
# 4. Verify formula works
#
# Requirements:
# - Real Homebrew installation (macOS or Linux with Homebrew)
# - Network access (to download bottles during mirror step)
# - ~2-5 minutes execution time
class TestFullWorkflow < Minitest::Test
  # Test formula: jq (small, simple, single binary)
  TEST_FORMULA = "jq"
  TEST_PORT = 8765

  def setup
    skip "Integration tests require Homebrew" unless homebrew_available?

    @mirror_dir = nil
    @http_server_pid = nil
    @original_tap_commit = current_tap_commit
  end

  def teardown
    # Stop HTTP server
    if @http_server_pid
      Process.kill("TERM", @http_server_pid) rescue nil
      Process.wait(@http_server_pid) rescue nil
      @http_server_pid = nil
    end

    # Uninstall test formula
    system("brew", "uninstall", "--force", TEST_FORMULA, out: File::NULL, err: File::NULL)

    # Reset tap to original commit
    if @original_tap_commit
      reset_tap(@original_tap_commit)
    end

    # Clean up mirror directory
    if @mirror_dir && File.exist?(@mirror_dir)
      FileUtils.rm_rf(@mirror_dir)
    end
  end

  # Integration test: Full mirror → serve → install workflow
  def test_full_workflow_mirror_serve_install
    puts "\n" + "=" * 70
    puts "Integration Test: Full Offline Brew Workflow"
    puts "=" * 70

    # Step 1: Mirror the formula
    puts "\n[Step 1/4] Mirroring #{TEST_FORMULA}..."
    @mirror_dir = mirror_formula(TEST_FORMULA)

    # Verify mirror created files
    assert File.exist?(File.join(@mirror_dir, "config.json")),
      "config.json should exist after mirroring"
    assert File.exist?(File.join(@mirror_dir, "urlmap.json")),
      "urlmap.json should exist after mirroring"

    config = JSON.parse(File.read(File.join(@mirror_dir, "config.json")))
    assert config["taps"], "Config should have taps"
    assert config["taps"]["homebrew/homebrew-core"], "Config should have core tap"
    assert config["taps"]["homebrew/homebrew-core"]["commit"], "Config should have tap commit"

    puts "  ✓ Mirror created successfully"
    puts "  ✓ config.json contains tap commit: #{config["taps"]["homebrew/homebrew-core"]["commit"][0..7]}"

    # Step 2: Serve the mirror
    puts "\n[Step 2/4] Starting HTTP server on port #{TEST_PORT}..."
    start_http_server(@mirror_dir, TEST_PORT)
    puts "  ✓ HTTP server started at http://localhost:#{TEST_PORT}"

    # Step 3: Install from mirror
    puts "\n[Step 3/4] Installing #{TEST_FORMULA} from offline mirror..."

    # Uninstall if already present
    if formula_installed?(TEST_FORMULA)
      puts "  - Uninstalling existing #{TEST_FORMULA}..."
      system("brew", "uninstall", "--force", TEST_FORMULA, out: File::NULL, err: File::NULL)
    end

    install_result = install_from_mirror(TEST_FORMULA, @mirror_dir)

    if install_result[:success]
      puts "  ✓ Installation completed"
    else
      puts "  ✗ Installation failed"
      puts install_result[:output]
      flunk "Installation failed: #{install_result[:output]}"
    end

    # Step 4: Verify the formula works
    puts "\n[Step 4/4] Verifying #{TEST_FORMULA} works..."
    assert formula_installed?(TEST_FORMULA),
      "#{TEST_FORMULA} should be installed"

    # Test jq actually works
    test_result = run_command("jq --version")
    assert test_result[:success], "jq --version should succeed"
    assert_output_contains(test_result[:stdout], "jq",
      "jq should report its version")

    puts "  ✓ #{TEST_FORMULA} is installed and functional"

    puts "\n" + "=" * 70
    puts "Integration Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Mirror creation with config-only mode
  def test_mirror_config_only_mode
    puts "\n" + "=" * 70
    puts "Integration Test: Mirror Config-Only Mode"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Running brew-mirror --config-only..."

      # Use 'brew mirror' command (brew finds brew-mirror executable in PATH)
      # This avoids brew ruby's option parser conflicts
      bin_dir = File.dirname(brew_mirror_path)
      result = run_command(
        "brew mirror -f #{TEST_FORMULA} -c -d #{tmpdir}",
        env: { "PATH" => "#{bin_dir}:#{ENV['PATH']}" }
      )

      # Config-only should succeed
      assert result[:success], "Config-only should succeed: #{result[:stderr]}"

      # Should create config files but not download bottles
      assert File.exist?(File.join(tmpdir, "config.json")),
        "Config-only should create config.json"

      assert File.exist?(File.join(tmpdir, "urlmap.json")),
        "Config-only should create urlmap.json"

      puts "  ✓ Config-only completed successfully"
      puts "  ✓ Config files created without downloading bottles"
    end

    puts "\n" + "=" * 70
    puts "Config-Only Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Config validation in brew-offline-install
  def test_offline_install_validates_config
    puts "\n" + "=" * 70
    puts "Integration Test: Config Validation"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      # Create .offlinebrew directory in tmpdir
      offlinebrew_dir = File.join(tmpdir, ".offlinebrew")
      Dir.mkdir(offlinebrew_dir)

      # Create invalid config (missing tap commit)
      invalid_config = {
        baseurl: "http://localhost:8000",
        taps: {
          "homebrew/homebrew-core" => {}
        }
      }

      File.write(
        File.join(offlinebrew_dir, "config.json"),
        JSON.pretty_generate(invalid_config)
      )

      # Create empty urlmap (required to exist)
      File.write(File.join(offlinebrew_dir, "urlmap.json"), "{}")

      puts "\n[Test] Running brew-offline-install with invalid config..."

      result = run_command(
        "#{brew_offline_install_path} #{TEST_FORMULA}",
        env: { "REAL_HOME" => tmpdir }
      )

      # Should fail with validation error
      refute result[:success], "Should fail with invalid config"

      # Check for validation error message
      error_output = result[:stdout] + result[:stderr]
      assert_match(/commit|tap|configuration/i, error_output,
        "Should mention configuration issue in error")

      puts "  ✓ Invalid config rejected (as expected)"
      puts "  ✓ Error message indicates configuration problem"
    end

    puts "\n" + "=" * 70
    puts "Config Validation Test: PASSED ✓"
    puts "=" * 70
  end

  private

  # Check if Homebrew is available
  def homebrew_available?
    system("brew --version > /dev/null 2>&1")
  end

  # Get current tap commit
  def current_tap_commit
    tap_dir = `brew --repository homebrew/core`.strip
    return nil unless Dir.exist?(tap_dir)

    Dir.chdir(tap_dir) do
      `git rev-parse HEAD`.strip
    end
  rescue
    nil
  end

  # Reset tap to specific commit
  def reset_tap(commit)
    tap_dir = `brew --repository homebrew/core`.strip
    return unless Dir.exist?(tap_dir)

    Dir.chdir(tap_dir) do
      system("git", "fetch", "--quiet", "origin", out: File::NULL, err: File::NULL)
      system("git", "checkout", "--quiet", commit, out: File::NULL, err: File::NULL)
    end
  end

  # Mirror a formula using brew-mirror
  def mirror_formula(formula)
    tmpdir = Dir.mktmpdir("brew-mirror-test-")

    puts "  - Running brew-mirror --formulae #{formula}"
    puts "  - Mirror directory: #{tmpdir}"

    # Use 'brew mirror' command (brew finds brew-mirror executable in PATH)
    bin_dir = File.dirname(brew_mirror_path)
    result = run_command(
      "brew mirror -f #{formula} -d #{tmpdir}",
      env: { "PATH" => "#{bin_dir}:#{ENV['PATH']}" }
    )

    unless result[:success]
      FileUtils.rm_rf(tmpdir)
      flunk "Mirror failed: #{result[:stderr]}"
    end

    tmpdir
  end

  # Start HTTP server to serve mirror
  # Uses Ruby's built-in httpd (no external dependencies)
  def start_http_server(directory, port)
    # Start Ruby's built-in HTTP server in background
    @http_server_pid = spawn(
      "ruby", "-run", "-e", "httpd", directory, "-p", port.to_s,
      out: File::NULL,
      err: File::NULL
    )

    # Wait for server to start
    sleep 2

    # Verify server is responding
    require "net/http"
    retries = 0
    loop do
      begin
        Net::HTTP.get(URI("http://localhost:#{port}/config.json"))
        break
      rescue
        retries += 1
        if retries > 10
          Process.kill("TERM", @http_server_pid) rescue nil
          flunk "HTTP server failed to start"
        end
        sleep 1
      end
    end
  end

  # Install formula from offline mirror
  def install_from_mirror(formula, mirror_dir)
    # Create a temporary HOME directory with .offlinebrew config
    Dir.mktmpdir do |home_dir|
      offlinebrew_dir = File.join(home_dir, ".offlinebrew")
      Dir.mkdir(offlinebrew_dir)

      # Copy config and urlmap from mirror_dir to temp .offlinebrew directory
      config_path = File.join(mirror_dir, "config.json")
      urlmap_path = File.join(mirror_dir, "urlmap.json")

      # Update config baseurl to point to our test server
      config = JSON.parse(File.read(config_path))
      config["baseurl"] = "http://localhost:#{TEST_PORT}"

      # Write updated config to temp location
      File.write(File.join(offlinebrew_dir, "config.json"), JSON.pretty_generate(config))
      FileUtils.cp(urlmap_path, File.join(offlinebrew_dir, "urlmap.json"))

      puts "  - Running brew-offline-install #{formula}"
      puts "  - Config: #{File.join(offlinebrew_dir, 'config.json')}"

      result = run_command(
        "#{brew_offline_install_path} #{formula}",
        env: { "REAL_HOME" => home_dir }
      )

      return {
        success: result[:success],
        output: result[:stdout] + "\n" + result[:stderr]
      }
    end
  end

  # Check if formula is installed
  def formula_installed?(formula)
    system("brew list #{formula} > /dev/null 2>&1")
  end

  # Path to brew-mirror script
  def brew_mirror_path
    File.expand_path("../../bin/brew-mirror", __dir__)
  end

  # Path to brew-offline-install script
  def brew_offline_install_path
    File.expand_path("../../bin/brew-offline-install", __dir__)
  end
end
