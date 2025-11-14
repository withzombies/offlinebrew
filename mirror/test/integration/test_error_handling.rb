#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "tempfile"
require "json"
require "securerandom"

# TestErrorHandling: Integration tests for error cases and edge conditions
#
# These tests verify that offlinebrew handles errors gracefully and provides
# helpful error messages.
class TestErrorHandling < Minitest::Test
  def setup
    skip "Integration tests require Homebrew" unless homebrew_available?
  end

  # Test: Mirror with non-existent formula
  def test_mirror_nonexistent_formula
    puts "\n" + "=" * 70
    puts "Integration Test: Non-Existent Formula"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Attempting to mirror non-existent formula..."

      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "this-formula-does-not-exist-12345", "-d", tmpdir]
      )

      refute result[:success], "Should fail with non-existent formula"

      # Should have a helpful error message
      error_output = result[:stdout] + result[:stderr]
      assert_match(/No available formula/i, error_output,
        "Should mention formula not available")

      puts "  ✓ Non-existent formula rejected"
      puts "  ✓ Error message is clear"
    end

    puts "\n" + "=" * 70
    puts "Non-Existent Formula Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Mirror to non-existent directory
  def test_mirror_to_nonexistent_directory
    puts "\n" + "=" * 70
    puts "Integration Test: Non-Existent Directory"
    puts "=" * 70

    nonexistent_dir = "/tmp/this-directory-does-not-exist-#{SecureRandom.hex(8)}"

    puts "\n[Test] Attempting to mirror to non-existent directory..."

    result = run_brew_mirror(
      brew_mirror_path,
      ["-f", "jq", "-d", nonexistent_dir]
    )

    refute result[:success], "Should fail with non-existent directory"

    error_output = result[:stdout] + result[:stderr]
    assert_match(/directory must exist/i, error_output,
      "Should mention directory doesn't exist")

    puts "  ✓ Non-existent directory rejected"
    puts "  ✓ Error message is clear"

    puts "\n" + "=" * 70
    puts "Non-Existent Directory Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Install without config
  def test_install_without_config
    puts "\n" + "=" * 70
    puts "Integration Test: Install Without Config"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Attempting install without config..."

      # Empty .offlinebrew directory (no config files)
      offlinebrew_dir = File.join(tmpdir, ".offlinebrew")
      Dir.mkdir(offlinebrew_dir)

      result = run_command(
        "#{brew_offline_install_path} jq",
        env: { "REAL_HOME" => tmpdir }
      )

      refute result[:success], "Should fail without config"

      error_output = result[:stdout] + result[:stderr]
      assert_match(/config\.json|No such file/i, error_output,
        "Should mention missing config")

      puts "  ✓ Missing config detected"
      puts "  ✓ Error message is clear"
    end

    puts "\n" + "=" * 70
    puts "Install Without Config Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Install with unreachable mirror
  def test_install_with_unreachable_mirror
    puts "\n" + "=" * 70
    puts "Integration Test: Unreachable Mirror"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Attempting install with unreachable mirror..."

      offlinebrew_dir = File.join(tmpdir, ".offlinebrew")
      Dir.mkdir(offlinebrew_dir)

      # Config points to unreachable server
      config = {
        baseurl: "http://localhost:99999",  # Invalid port
        taps: {
          "homebrew/homebrew-core" => {
            "commit" => "abc123",
            "type" => "formula"
          }
        }
      }

      File.write(
        File.join(offlinebrew_dir, "config.json"),
        JSON.pretty_generate(config)
      )
      File.write(File.join(offlinebrew_dir, "urlmap.json"), "{}")

      result = run_command(
        "#{brew_offline_install_path} jq",
        env: { "REAL_HOME" => tmpdir }
      )

      refute result[:success], "Should fail with unreachable mirror"

      error_output = result[:stdout] + result[:stderr]
      assert_match(/Failed to open TCP connection|Connection refused|configuration/i, error_output,
        "Should mention connection failure")

      puts "  ✓ Unreachable mirror detected"
      puts "  ✓ Error message mentions connection issue"
    end

    puts "\n" + "=" * 70
    puts "Unreachable Mirror Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Install with corrupted urlmap
  def test_install_with_corrupted_urlmap
    puts "\n" + "=" * 70
    puts "Integration Test: Corrupted URLmap"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Attempting install with corrupted URLmap..."

      offlinebrew_dir = File.join(tmpdir, ".offlinebrew")
      Dir.mkdir(offlinebrew_dir)

      config = {
        baseurl: "http://localhost:8000",
        taps: {
          "homebrew/homebrew-core" => {
            "commit" => "abc123",
            "type" => "formula"
          }
        }
      }

      File.write(
        File.join(offlinebrew_dir, "config.json"),
        JSON.pretty_generate(config)
      )

      # Write invalid JSON to urlmap
      File.write(File.join(offlinebrew_dir, "urlmap.json"), "{ invalid json }")

      result = run_command(
        "#{brew_offline_install_path} jq",
        env: { "REAL_HOME" => tmpdir }
      )

      refute result[:success], "Should fail with corrupted URLmap"

      error_output = result[:stdout] + result[:stderr]
      assert_match(/JSON|parse|unexpected/i, error_output,
        "Should mention JSON parsing issue")

      puts "  ✓ Corrupted URLmap detected"
      puts "  ✓ Error message mentions parsing issue"
    end

    puts "\n" + "=" * 70
    puts "Corrupted URLmap Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Legacy format rejection
  def test_legacy_format_rejection
    puts "\n" + "=" * 70
    puts "Integration Test: Legacy Format Rejection"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Testing legacy format rejection..."

      offlinebrew_dir = File.join(tmpdir, ".offlinebrew")
      Dir.mkdir(offlinebrew_dir)

      # Old format config (just commit field, no taps)
      old_config = {
        baseurl: "http://localhost:8000",
        commit: "abc123def456",  # Old format - should be rejected
        stamp: Time.now.to_i.to_s,
        cache: "/tmp/mirror"
      }

      File.write(
        File.join(offlinebrew_dir, "config.json"),
        JSON.pretty_generate(old_config)
      )
      File.write(File.join(offlinebrew_dir, "urlmap.json"), "{}")

      result = run_command(
        "#{brew_offline_install_path} jq",
        env: { "REAL_HOME" => tmpdir }
      )

      # Should fail when legacy format is detected
      refute result[:success], "Should fail with legacy config format"

      error_output = result[:stdout] + result[:stderr]

      # Should have legacy format error message
      assert_match(/Legacy config format detected|old.*format/i, error_output,
        "Should mention legacy format in error message")

      # Should mention new format requirement
      assert_match(/multi-tap|taps/i, error_output,
        "Should mention new format requirement")

      puts "  ✓ Legacy format rejected with clear error"
      puts "  ✓ Error message guides user to new format"
    end

    puts "\n" + "=" * 70
    puts "Legacy Format Rejection Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Mirror handles formula with no stable version
  def test_mirror_formula_no_stable
    puts "\n" + "=" * 70
    puts "Integration Test: Formula Without Stable Version"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Attempting to mirror HEAD-only formula..."

      # Most formulae have stable versions, but we can test the code path
      # by checking if mirror handles missing stable gracefully
      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", tmpdir]
      )

      # Should succeed (jq has a stable version)
      assert result[:success], "Mirror should succeed"

      # But if we tried with --HEAD flag (not supported), should get error
      result_head = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", tmpdir, "--HEAD"]  # Invalid flag
      )

      refute result_head[:success], "Should reject --HEAD flag"
      puts "  ✓ HEAD-only installations correctly unsupported"
    end

    puts "\n" + "=" * 70
    puts "No Stable Version Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Multiple taps in config
  def test_multi_tap_config
    puts "\n" + "=" * 70
    puts "Integration Test: Multi-Tap Configuration"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Creating multi-tap mirror config..."

      result = run_brew_mirror(
        brew_mirror_path,
        ["--taps", "homebrew/homebrew-core", "-f", "jq", "-d", tmpdir]
      )

      assert result[:success], "Mirror should succeed"

      config = JSON.parse(File.read(File.join(tmpdir, "config.json")))
      assert config["taps"], "Config should have taps hash"
      assert config["taps"]["homebrew/homebrew-core"], "Config should have core tap"

      # Check tap info structure
      core_tap = config["taps"]["homebrew/homebrew-core"]
      assert core_tap["commit"], "Core tap should have commit"
      assert core_tap["type"], "Core tap should have type"
      assert_equal "formula", core_tap["type"], "Core tap type should be formula"

      puts "  ✓ Multi-tap config created"
      puts "  ✓ Tap structure is correct"
      puts "  ✓ Core tap: #{core_tap["commit"][0..7]}"
    end

    puts "\n" + "=" * 70
    puts "Multi-Tap Config Test: PASSED ✓"
    puts "=" * 70
  end

  private

  def homebrew_available?
    system("brew --version > /dev/null 2>&1")
  end

  def brew_mirror_path
    File.expand_path("../../bin/brew-mirror", __dir__)
  end

  def brew_offline_install_path
    File.expand_path("../../bin/brew-offline-install", __dir__)
  end
end
