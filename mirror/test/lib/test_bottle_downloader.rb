#!/usr/bin/env brew ruby
# frozen_string_literal: true

# TestBottleDownloader: Unit tests for BottleDownloader module
#
# These tests verify bottle downloading functionality for offline formula installs.
# Must run with `brew ruby` to access Formula API.
#
# Usage:
#   brew ruby mirror/test/lib/test_bottle_downloader.rb

require "minitest/autorun"
require "json"
require "fileutils"
require "tmpdir"
require "digest"

# Load the BottleDownloader module we're testing
require_relative "../../lib/bottle_downloader"

# We need Homebrew's libraries
abort "Make sure to run me via `brew ruby`!" unless Object.const_defined? :Homebrew

class TestBottleDownloader < Minitest::Test
  def setup
    # Create a temporary directory for test output
    @test_dir = Dir.mktmpdir("bottle_downloader_test")
    @bottles_dir = File.join(@test_dir, "bottles")
    @urlmap = {}
    @options = {}
  end

  def teardown
    # Clean up temporary directory
    FileUtils.rm_rf(@test_dir) if @test_dir && File.exist?(@test_dir)
  end

  # Test: Extract bottle URL and SHA256 for current platform
  def test_extracts_bottle_url_for_platform
    formula = Formula["jq"]
    downloader = BottleDownloader.new(@bottles_dir, @urlmap, @options)

    # Get the current platform (e.g., arm64_sonoma)
    platform = downloader.current_platform

    bottle_info = downloader.extract_bottle_info(formula, platform)

    # Should return hash with url and sha256
    assert bottle_info.is_a?(Hash), "Bottle info should be a hash"
    assert bottle_info.key?(:url), "Should have :url key"
    assert bottle_info.key?(:sha256), "Should have :sha256 key"

    # URL should be a string and not empty
    assert bottle_info[:url].is_a?(String)
    refute_empty bottle_info[:url]

    # SHA256 should be a 64-character hex string
    assert_match(/^[a-f0-9]{64}$/i, bottle_info[:sha256])
  end

  # Test: Download bottle to bottles/ subdirectory
  def test_downloads_bottle_to_bottles_directory
    formula = Formula["jq"]
    downloader = BottleDownloader.new(@bottles_dir, @urlmap, @options)

    platform = downloader.current_platform
    bottle_path = downloader.download_bottle(formula, platform)

    # Should create bottles/ directory
    assert Dir.exist?(@bottles_dir), "Bottles directory should exist"

    # Should return path to downloaded bottle
    assert bottle_path.is_a?(String)
    assert File.exist?(bottle_path), "Bottle file should exist at #{bottle_path}"

    # Path should be in bottles/ subdirectory
    assert bottle_path.start_with?(@bottles_dir), "Bottle should be in bottles/ directory"

    # Filename should match pattern: formula--version.platform.bottle.tar.gz
    basename = File.basename(bottle_path)
    assert_match(/jq--.*\.#{Regexp.escape(platform.to_s)}\.bottle\.tar\.gz$/, basename)
  end

  # Test: Verify bottle SHA256 checksum
  def test_verifies_bottle_sha256
    formula = Formula["jq"]
    downloader = BottleDownloader.new(@bottles_dir, @urlmap, @options)

    platform = downloader.current_platform
    bottle_path = downloader.download_bottle(formula, platform)

    # Verify the downloaded file
    bottle_info = downloader.extract_bottle_info(formula, platform)
    expected_sha = bottle_info[:sha256]

    actual_sha = Digest::SHA256.file(bottle_path).hexdigest

    assert_equal expected_sha, actual_sha, "SHA256 checksum should match"
  end

  # Test: Skip formula without bottles (no error)
  def test_skips_formula_without_bottles
    # head-only formula or formula without bottles
    # We'll use a formula that might not have bottles for current platform
    formula = Formula["jq"]
    downloader = BottleDownloader.new(@bottles_dir, @urlmap, @options)

    # Try a fake platform that doesn't exist
    fake_platform = :nonexistent_platform_12345
    bottle_info = downloader.extract_bottle_info(formula, fake_platform)

    # Should return nil or empty hash, not raise error
    assert [nil, {}].include?(bottle_info) || bottle_info.empty?,
           "Should return nil/empty for non-existent platform"
  end

  # Test: Update urlmap with bottle URL mappings
  def test_updates_urlmap_with_bottle_urls
    formula = Formula["jq"]
    downloader = BottleDownloader.new(@bottles_dir, @urlmap, @options)

    platform = downloader.current_platform
    bottle_path = downloader.download_bottle(formula, platform)

    # urlmap should be updated
    refute_empty @urlmap, "urlmap should not be empty"

    # Should contain mapping from bottle URL to local filename
    bottle_info = downloader.extract_bottle_info(formula, platform)
    bottle_url = bottle_info[:url]

    assert @urlmap.key?(bottle_url), "urlmap should contain bottle URL"
    assert_equal File.basename(bottle_path), @urlmap[bottle_url]
  end

  # Test: Download_all processes multiple formulas
  def test_download_all_processes_multiple_formulas
    formulas = [Formula["jq"], Formula["oniguruma"]]
    downloader = BottleDownloader.new(@bottles_dir, @urlmap, @options)

    count = downloader.download_all(formulas)

    # Should return count of bottles downloaded
    assert count.is_a?(Integer)
    assert count >= 2, "Should download at least 2 bottles (jq + oniguruma)"

    # Bottles directory should have files
    bottles = Dir.glob(File.join(@bottles_dir, "*.bottle.tar.gz"))
    assert bottles.length >= 2, "Should have at least 2 bottle files"
  end

  # Test: Current platform detection
  def test_detects_current_platform
    downloader = BottleDownloader.new(@bottles_dir, @urlmap, @options)
    platform = downloader.current_platform

    # Should return a symbol
    assert platform.is_a?(Symbol), "Platform should be a symbol"

    # Should match known macOS platform patterns
    # e.g., arm64_sonoma, arm64_sequoia, arm64_ventura, x86_64_sonoma, etc.
    platform_str = platform.to_s
    assert platform_str.match?(/^(arm64|x86_64)_\w+$/),
           "Platform should match pattern: arch_os (got #{platform_str})"
  end
end
