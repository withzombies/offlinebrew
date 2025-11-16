#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/tap_manager"
require_relative "../lib/homebrew_paths"

# TestTapManager: Unit tests for TapManager module
#
# These tests verify tap name parsing, path resolution, and tap type detection.
class TestTapManager < Minitest::Test
  def test_parse_tap_name_valid
    result = TapManager.parse_tap_name("homebrew/homebrew-core")
    assert_equal "homebrew", result[:user]
    assert_equal "homebrew-core", result[:repo]
  end

  def test_parse_tap_name_invalid
    # Since expand_tap_name now handles single-word names as shorthands,
    # we need to test with a truly invalid format (multiple slashes)
    assert_raises(SystemExit) do
      TapManager.parse_tap_name("invalid/tap/name")
    end
  end

  def test_tap_directory
    expected = HomebrewPaths.tap_path("homebrew", "homebrew-core")
    actual = TapManager.tap_directory("homebrew/homebrew-core")
    assert_equal expected, actual
  end

  def test_tap_type_core
    assert_equal "formula", TapManager.tap_type("homebrew/homebrew-core")
  end

  def test_tap_type_cask
    assert_equal "cask", TapManager.tap_type("homebrew/homebrew-cask")
  end

  def test_tap_type_cask_fonts
    assert_equal "cask", TapManager.tap_type("homebrew/homebrew-cask-fonts")
  end

  def test_tap_type_cask_versions
    assert_equal "cask", TapManager.tap_type("homebrew/homebrew-cask-versions")
  end

  def test_tap_type_unknown
    # Non-standard tap should be detected based on directory structure
    # or default to "mixed"
    type = TapManager.tap_type("custom/custom-tap")
    assert_includes ["formula", "cask", "mixed"], type
  end

  # Only run installation tests if Homebrew is available
  def test_tap_installed_core
    skip "Homebrew not available" unless HomebrewPaths.homebrew_installed?

    # Core tap should always be installed
    assert TapManager.tap_installed?("homebrew/homebrew-core"),
      "homebrew-core should be installed"
  end

  def test_tap_commit_core
    skip "Homebrew not available" unless HomebrewPaths.homebrew_installed?
    skip "Core tap not installed" unless TapManager.tap_installed?("homebrew/homebrew-core")

    commit = TapManager.tap_commit("homebrew/homebrew-core")
    refute_nil commit, "Should return commit hash for core tap"
    # In Homebrew 5.0+, bundled taps return synthetic commit like "bundled-5.0.1"
    assert_match(/^bundled-\d+\.\d+/, commit, "Commit should be bundled version format")
  end

  def test_tap_commit_nonexistent
    commit = TapManager.tap_commit("nonexistent/nonexistent-tap")
    assert_nil commit, "Should return nil for non-existent tap"
  end

  def test_all_installed_taps
    skip "Homebrew not available" unless HomebrewPaths.homebrew_installed?

    taps = TapManager.all_installed_taps
    assert_instance_of Array, taps
    assert taps.all? { |t| t.include?("/") }, "All taps should be in user/repo format"
    assert taps.include?("homebrew/homebrew-core"), "Core tap should be in list"
  end

  def test_tap_available_in_homebrew_bundled_taps
    # Bundled taps are always available in Homebrew 5.0+
    assert TapManager.tap_available_in_homebrew?("homebrew/homebrew-core"),
      "Core tap should always be available in 5.0+"
    assert TapManager.tap_available_in_homebrew?("homebrew/homebrew-cask"),
      "Cask tap should always be available in 5.0+"
  end

  def test_tap_available_in_homebrew_non_bundled_taps
    # Non-bundled taps are not bundled
    refute TapManager.tap_available_in_homebrew?("custom/custom-tap"),
      "Custom tap should not be bundled"
  end

  def test_tap_commit_bundled_format
    skip "Homebrew not available" unless HomebrewPaths.homebrew_installed?

    # Test both bundled taps return synthetic commit format
    ["homebrew/homebrew-core", "homebrew/homebrew-cask"].each do |tap|
      commit = TapManager.tap_commit(tap)
      assert_match(/^bundled-\d+\.\d+/, commit,
        "#{tap} should return bundled version format")
    end
  end

  def test_all_installed_taps_includes_bundled
    skip "Homebrew not available" unless HomebrewPaths.homebrew_installed?

    taps = TapManager.all_installed_taps
    # In Homebrew 5.0+, bundled taps should always be in the list
    assert taps.include?("homebrew/homebrew-core"),
      "Core tap should always be in list for 5.0+"
    assert taps.include?("homebrew/homebrew-cask"),
      "Cask tap should always be in list for 5.0+"
  end
end
