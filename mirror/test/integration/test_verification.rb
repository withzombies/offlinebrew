#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "json"
require "open3"

# TestVerification: Integration tests for brew-mirror-verify
#
# Tests the mirror verification system to ensure:
# - Validates config.json structure
# - Checks for missing files
# - Detects orphaned files
# - Verifies Git repository cache
# - Reports errors and warnings correctly
class TestVerification < Minitest::Test
  def setup
    skip "Integration tests require Homebrew" unless homebrew_available?
  end

  # Test: Verify valid mirror
  def test_verify_valid_mirror
    puts "\n" + "=" * 70
    puts "Integration Test: Verify Valid Mirror"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Creating and verifying a valid mirror..."

      # Create mirror
      puts "  [1] Creating mirror..."
      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", tmpdir, "-s", "0.1", "--taps", "core"]
      )

      assert result[:success], "Mirror creation should succeed: #{result[:stderr]}"

      # Verify mirror
      puts "  [2] Verifying mirror..."
      verify_result = run_brew_mirror_verify(brew_mirror_verify_path, [tmpdir])

      assert verify_result[:success], "Verification should succeed: #{verify_result[:stderr]}"
      assert_match(/Mirror is valid and complete/, verify_result[:stdout],
                   "Should report mirror as valid")
      assert_match(/✅/, verify_result[:stdout], "Should show success indicator")

      puts "  ✓ Valid mirror verified successfully"
    end

    puts "\n" + "=" * 70
    puts "Valid Mirror Verification Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Verify mirror with --verify flag
  def test_verify_flag_in_mirror_command
    puts "\n" + "=" * 70
    puts "Integration Test: Mirror with --verify Flag"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Creating mirror with automatic verification..."

      # Create mirror with --verify flag
      # Use --taps core to skip cask mirroring for faster CI tests
      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", tmpdir, "-s", "0.1", "--taps", "core", "--verify"]
      )

      assert result[:success], "Mirror with --verify should succeed: #{result[:stderr]}"
      assert_match(/Verifying mirror/, result[:stdout],
                   "Should show verification step")
      assert_match(/Mirror is valid/, result[:stdout],
                   "Should show verification result")

      puts "  ✓ --verify flag works correctly"
    end

    puts "\n" + "=" * 70
    puts "Mirror --verify Flag Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Detect missing files
  def test_verify_detects_missing_files
    puts "\n" + "=" * 70
    puts "Integration Test: Detect Missing Files"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Creating mirror and removing files..."

      # Create mirror
      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", tmpdir, "-s", "0.1", "--taps", "core"]
      )

      assert result[:success], "Mirror creation should succeed"

      # Remove a mirrored file
      urlmap = JSON.parse(File.read(File.join(tmpdir, "urlmap.json")))
      first_file = urlmap.values.first
      File.delete(File.join(tmpdir, first_file)) if first_file

      puts "  [1] Removed file: #{first_file}"

      # Verify mirror (should fail)
      puts "  [2] Verifying corrupted mirror..."
      verify_result = run_brew_mirror_verify(brew_mirror_verify_path, [tmpdir])

      refute verify_result[:success], "Verification should fail for missing files"
      assert_match(/missing/, verify_result[:stdout].downcase,
                   "Should report missing files")
      assert_match(/❌/, verify_result[:stdout], "Should show error indicator")

      puts "  ✓ Missing files detected correctly"
    end

    puts "\n" + "=" * 70
    puts "Missing Files Detection Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Detect missing config
  def test_verify_detects_missing_config
    puts "\n" + "=" * 70
    puts "Integration Test: Detect Missing Config"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Creating mirror and removing config..."

      # Create mirror
      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", tmpdir, "-s", "0.1", "--taps", "core"]
      )

      assert result[:success], "Mirror creation should succeed"

      # Remove config.json
      File.delete(File.join(tmpdir, "config.json"))
      puts "  [1] Removed config.json"

      # Verify mirror (should fail)
      puts "  [2] Verifying mirror without config..."
      verify_result = run_brew_mirror_verify(brew_mirror_verify_path, [tmpdir])

      refute verify_result[:success], "Verification should fail without config"
      assert_match(/config\.json not found/, verify_result[:stdout],
                   "Should report missing config")

      puts "  ✓ Missing config detected correctly"
    end

    puts "\n" + "=" * 70
    puts "Missing Config Detection Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Verify verbose output
  def test_verify_verbose_output
    puts "\n" + "=" * 70
    puts "Integration Test: Verbose Verification Output"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Testing verbose verification mode..."

      # Create mirror
      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", tmpdir, "-s", "0.1", "--taps", "core"]
      )

      assert result[:success], "Mirror creation should succeed"

      # Verify with verbose flag
      puts "  [1] Running verification with --verbose..."
      verify_result = run_brew_mirror_verify(
        brew_mirror_verify_path,
        [tmpdir, "--verbose"]
      )

      assert verify_result[:success], "Verbose verification should succeed"
      assert_match(/Statistics/, verify_result[:stdout],
                   "Should show statistics section")

      puts "  ✓ Verbose mode provides detailed output"
    end

    puts "\n" + "=" * 70
    puts "Verbose Verification Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Verify Git cache (Task 3.2)
  def test_verify_git_cache
    puts "\n" + "=" * 70
    puts "Integration Test: Git Repository Cache Verification"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Verifying Git repository cache handling..."

      # Create mirror (jq doesn't use git, so cache should be empty)
      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", tmpdir, "-s", "0.1", "--taps", "core"]
      )

      assert result[:success], "Mirror creation should succeed"

      # Verify mirror
      puts "  [1] Verifying mirror with Git cache check..."
      verify_result = run_brew_mirror_verify(brew_mirror_verify_path, [tmpdir])

      assert verify_result[:success], "Verification should succeed"
      assert_match(/Git repositories/, verify_result[:stdout],
                   "Should report Git repository count")

      # Check that identifier_cache.json exists
      cache_file = File.join(tmpdir, "identifier_cache.json")
      assert File.exist?(cache_file), "identifier_cache.json should exist"

      puts "  ✓ Git cache verification works"
    end

    puts "\n" + "=" * 70
    puts "Git Cache Verification Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Help flag
  def test_verify_help_flag
    puts "\n" + "=" * 70
    puts "Integration Test: Verification Help Flag"
    puts "=" * 70

    puts "\n[Test] Testing --help flag..."

    result = run_brew_mirror_verify(brew_mirror_verify_path, ["--help"])

    assert result[:success], "Help should succeed"
    assert_match(/Usage:/, result[:stdout], "Should show usage")
    assert_match(/Options:/, result[:stdout], "Should show options")
    assert_match(/Exit codes:/, result[:stdout], "Should show exit codes")

    puts "  ✓ Help documentation is available"

    puts "\n" + "=" * 70
    puts "Verification Help Test: PASSED ✓"
    puts "=" * 70
  end

  private

  def homebrew_available?
    system("brew --version > /dev/null 2>&1")
  end

  def brew_mirror_path
    File.expand_path("../../bin/brew-mirror", __dir__)
  end

  def brew_mirror_verify_path
    File.expand_path("../../bin/brew-mirror-verify", __dir__)
  end

  def run_brew_mirror_verify(script_path, args)
    # Use '--' to separate brew ruby options from script options
    cmd = ["brew", "ruby", script_path, "--"] + args
    stdout, stderr, status = Open3.capture3(*cmd)
    {
      success: status.success?,
      stdout: stdout,
      stderr: stderr,
      exit_code: status.exitstatus,
    }
  end
end
