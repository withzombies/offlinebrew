#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "tempfile"
require "json"
require "net/http"
require "uri"

# TestURLShims: Integration tests for brew-offline-curl and brew-offline-git
#
# These tests verify that URL redirection works correctly when installing
# from an offline mirror.
class TestURLShims < Minitest::Test
  TEST_PORT = 8766

  def setup
    skip "Integration tests require Homebrew" unless homebrew_available?

    @mirror_dir = nil
    @http_server_pid = nil
  end

  def teardown
    # Stop HTTP server
    if @http_server_pid
      Process.kill("TERM", @http_server_pid) rescue nil
      Process.wait(@http_server_pid) rescue nil
      @http_server_pid = nil
    end

    # Clean up mirror directory
    if @mirror_dir && File.exist?(@mirror_dir)
      FileUtils.rm_rf(@mirror_dir)
    end
  end

  # Test: brew-offline-curl redirects URLs correctly
  def test_brew_offline_curl_url_redirection
    puts "\n" + "=" * 70
    puts "Integration Test: brew-offline-curl URL Redirection"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      # Create test config
      offlinebrew_dir = File.join(tmpdir, ".offlinebrew")
      Dir.mkdir(offlinebrew_dir)

      config = {
        baseurl: "http://localhost:#{TEST_PORT}"
      }

      urlmap = {
        "https://example.com/test.tar.gz" => "abc123.tar.gz",
        "https://example.com/test.tar.gz?version=1.0" => "abc123.tar.gz",
        "https://github.com/foo/bar.git" => "def456.git"
      }

      File.write(File.join(offlinebrew_dir, "config.json"), JSON.pretty_generate(config))
      File.write(File.join(offlinebrew_dir, "urlmap.json"), JSON.pretty_generate(urlmap))

      puts "\n[Test] Testing URL matching..."

      # Test exact match
      result = run_brew_offline_curl(
        "https://example.com/test.tar.gz",
        env: { "REAL_HOME" => tmpdir, "BREW_OFFLINE_DEBUG" => "1" }
      )

      assert_match(/abc123\.tar\.gz/, result[:stderr],
        "Should redirect exact URL match")

      # Test URL with query parameters
      result = run_brew_offline_curl(
        "https://example.com/test.tar.gz?version=1.0",
        env: { "REAL_HOME" => tmpdir, "BREW_OFFLINE_DEBUG" => "1" }
      )

      assert_match(/abc123\.tar\.gz/, result[:stderr],
        "Should redirect URL with query parameters")

      # Test URL with fragment
      result = run_brew_offline_curl(
        "https://example.com/test.tar.gz#download",
        env: { "REAL_HOME" => tmpdir, "BREW_OFFLINE_DEBUG" => "1" }
      )

      assert_match(/abc123\.tar\.gz/, result[:stderr],
        "Should redirect URL with fragment")

      puts "  ✓ URL matching works correctly"
      puts "  ✓ Query parameters handled"
      puts "  ✓ Fragments handled"
    end

    puts "\n" + "=" * 70
    puts "URL Redirection Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: URLmap includes all mirrored resources
  def test_urlmap_completeness
    puts "\n" + "=" * 70
    puts "Integration Test: URLmap Completeness"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Mirroring formula and checking URLmap..."

      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "wget", "-d", tmpdir]
      )

      assert result[:success], "Mirror should succeed"

      # Load urlmap
      urlmap_path = File.join(tmpdir, "urlmap.json")
      assert File.exist?(urlmap_path), "urlmap.json should exist"

      urlmap = JSON.parse(File.read(urlmap_path))

      # urlmap should have entries
      refute_empty urlmap, "URLmap should not be empty"

      puts "  ✓ URLmap created"
      puts "  ✓ URLmap contains #{urlmap.keys.count} URL mappings"

      # Verify each URL maps to a file that exists
      urlmap.each do |url, filename|
        file_path = File.join(tmpdir, filename)
        assert File.exist?(file_path),
          "URLmap points to non-existent file: #{filename} for URL: #{url}"
      end

      puts "  ✓ All URLmap entries point to existing files"
    end

    puts "\n" + "=" * 70
    puts "URLmap Completeness Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Mirror handles multiple formulae
  def test_mirror_multiple_formulae
    puts "\n" + "=" * 70
    puts "Integration Test: Mirror Multiple Formulae"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Mirroring multiple formulae..."

      # Mirror two small formulae
      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq,tree", "-d", tmpdir, "-s", "0.1"]
      )

      assert result[:success], "Mirror should succeed: #{result[:stderr]}"

      # Check config
      config = JSON.parse(File.read(File.join(tmpdir, "config.json")))
      assert config["taps"], "Config should have taps"
      assert config["taps"]["homebrew/homebrew-core"], "Config should have core tap"

      # Check urlmap
      urlmap = JSON.parse(File.read(File.join(tmpdir, "urlmap.json")))
      assert urlmap.keys.count >= 2, "Should have URLs for both formulae"

      puts "  ✓ Multiple formulae mirrored"
      puts "  ✓ URLmap contains #{urlmap.keys.count} entries"
    end

    puts "\n" + "=" * 70
    puts "Multiple Formulae Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Config-only mode doesn't download files
  def test_config_only_no_downloads
    puts "\n" + "=" * 70
    puts "Integration Test: Config-Only No Downloads"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Running config-only mode..."

      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "wget", "-c", "-d", tmpdir]
      )

      assert result[:success], "Config-only should succeed"

      # Should create config
      assert File.exist?(File.join(tmpdir, "config.json")),
        "Should create config.json"

      # Should create empty urlmap
      assert File.exist?(File.join(tmpdir, "urlmap.json")),
        "Should create urlmap.json"

      urlmap = JSON.parse(File.read(File.join(tmpdir, "urlmap.json")))
      assert_empty urlmap, "URLmap should be empty in config-only mode"

      # Should NOT download any files
      downloaded_files = Dir.glob(File.join(tmpdir, "*")).select { |f| File.file?(f) }
      downloaded_files.reject! { |f| f.end_with?("config.json", "urlmap.json") }

      assert_empty downloaded_files,
        "Should not download files in config-only mode, found: #{downloaded_files}"

      puts "  ✓ Config created"
      puts "  ✓ No files downloaded"
    end

    puts "\n" + "=" * 70
    puts "Config-Only Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Tap commit is recorded correctly
  def test_tap_commit_recorded
    puts "\n" + "=" * 70
    puts "Integration Test: Tap Commit Recording"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Checking tap commit recording..."

      # Get current core tap commit
      core_tap_dir = `brew --repository homebrew/core`.strip
      original_commit = nil
      Dir.chdir(core_tap_dir) do
        original_commit = `git rev-parse HEAD`.strip
      end

      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", tmpdir]
      )

      assert result[:success], "Mirror should succeed"

      # Check config has the commit
      config = JSON.parse(File.read(File.join(tmpdir, "config.json")))
      recorded_commit = config.dig("taps", "homebrew/homebrew-core", "commit")

      assert recorded_commit, "Config should record tap commit"
      assert_equal original_commit, recorded_commit,
        "Recorded commit should match original"

      puts "  ✓ Tap commit recorded: #{recorded_commit[0..7]}"
      puts "  ✓ Commit matches current tap state"
    end

    puts "\n" + "=" * 70
    puts "Tap Commit Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Invalid config is rejected
  def test_invalid_config_rejection
    puts "\n" + "=" * 70
    puts "Integration Test: Invalid Config Rejection"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      offlinebrew_dir = File.join(tmpdir, ".offlinebrew")
      Dir.mkdir(offlinebrew_dir)

      test_cases = [
        {
          name: "Missing baseurl",
          config: { taps: { "homebrew/homebrew-core" => { "commit" => "abc123" } } },
          should_fail: true
        },
        {
          name: "Empty taps",
          config: { baseurl: "http://localhost:8000", taps: {} },
          should_fail: false  # Will fail when trying to fetch remote config
        },
        {
          name: "Invalid JSON",
          config: "{ invalid json",
          should_fail: true,
          write_raw: true
        }
      ]

      test_cases.each do |test_case|
        puts "\n[Test] #{test_case[:name]}..."

        if test_case[:write_raw]
          File.write(File.join(offlinebrew_dir, "config.json"), test_case[:config])
        else
          File.write(
            File.join(offlinebrew_dir, "config.json"),
            JSON.pretty_generate(test_case[:config])
          )
        end

        File.write(File.join(offlinebrew_dir, "urlmap.json"), "{}")

        result = run_command(
          "#{brew_offline_install_path} test-formula",
          env: { "REAL_HOME" => tmpdir }
        )

        if test_case[:should_fail]
          refute result[:success], "Should fail with: #{test_case[:name]}"
          puts "  ✓ Correctly rejected invalid config"
        end
      end
    end

    puts "\n" + "=" * 70
    puts "Invalid Config Test: PASSED ✓"
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

  def brew_offline_curl_path
    File.expand_path("../../bin/brew-offline-curl", __dir__)
  end

  def run_brew_offline_curl(url, env: {})
    run_command(
      "#{brew_offline_curl_path} #{url}",
      env: env
    )
  end
end
