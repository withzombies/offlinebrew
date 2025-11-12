#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/url_helpers"
require "uri"
require "json"

# TestBrewOfflineCurl: Tests for brew-offline-curl URL redirection shim
#
# NOTE: These are regression tests for existing code, not true TDD.
# The brew-offline-curl script was written before tests.
# Going forward, all changes to brew-offline-curl MUST follow TDD.
#
# Testing Strategy:
# - Test URL transformation logic directly (URLHelpers module)
# - Test script structure and error handling where possible
# - Accept that exec behavior can't be easily unit tested
class TestBrewOfflineCurl < Minitest::Test
  def setup
    @script_path = File.expand_path("../../bin/brew-offline-curl", __dir__)
    assert File.exist?(@script_path), "brew-offline-curl script not found"
  end

  # Test: Script exists and is executable
  def test_script_exists_and_is_executable
    assert File.exist?(@script_path)
    assert File.executable?(@script_path), "brew-offline-curl should be executable"
  end

  # Test: Script has required components
  def test_script_has_required_components
    script_content = File.read(@script_path, encoding: "UTF-8")

    # Should require url_helpers
    assert_match(/require_relative.*url_helpers/, script_content,
      "Script should require url_helpers")

    # Should use URLHelpers.find_in_urlmap
    assert_match(/URLHelpers\.find_in_urlmap/, script_content,
      "Script should use URLHelpers.find_in_urlmap")

    # Should exec curl
    assert_match(/exec.*curl/, script_content,
      "Script should exec curl")

    # Should have verbose and debug functions
    assert_match(/def verbose/, script_content,
      "Script should have verbose function")
    assert_match(/def debug/, script_content,
      "Script should have debug function")
  end

  # Test: URL transformation logic (via URLHelpers)
  #
  # This tests the core logic that brew-offline-curl uses
  def test_url_transformation_exact_match
    urlmap = {
      "https://example.com/file.dmg" => "abc123.dmg",
    }

    # Exact match should work
    result = URLHelpers.find_in_urlmap("https://example.com/file.dmg", urlmap)
    assert_equal "abc123.dmg", result
  end

  def test_url_transformation_with_query_params
    urlmap = {
      "https://example.com/file.dmg" => "abc123.dmg",
    }

    # URL with query params should match base URL
    result = URLHelpers.find_in_urlmap("https://example.com/file.dmg?version=1.0", urlmap)
    assert_equal "abc123.dmg", result,
      "URL with query params should match base URL"
  end

  def test_url_transformation_with_fragment
    urlmap = {
      "https://example.com/file.dmg" => "abc123.dmg",
    }

    # URL with fragment should match base URL
    result = URLHelpers.find_in_urlmap("https://example.com/file.dmg#download", urlmap)
    assert_equal "abc123.dmg", result,
      "URL with fragment should match base URL"
  end

  def test_url_transformation_with_both_query_and_fragment
    urlmap = {
      "https://example.com/file.dmg" => "abc123.dmg",
    }

    # URL with both should match base URL
    result = URLHelpers.find_in_urlmap("https://example.com/file.dmg?v=1.0#download", urlmap)
    assert_equal "abc123.dmg", result,
      "URL with query and fragment should match base URL"
  end

  def test_url_transformation_missing_url_returns_nil
    urlmap = {
      "https://example.com/exists.dmg" => "abc123.dmg",
    }

    # Missing URL should return nil
    result = URLHelpers.find_in_urlmap("https://example.com/missing.dmg", urlmap)
    assert_nil result, "Missing URL should return nil"
  end

  # Test: URL extraction from ARGV
  def test_url_extraction_from_argv
    test_argv = [
      "-L",
      "-o",
      "output.dmg",
      "https://example.com/file.dmg",
      "--silent",
    ]

    # Extract URLs using same logic as script
    urls = test_argv.select { |arg| URI.regexp(%w[http https]) =~ arg }

    assert_equal 1, urls.length
    assert_equal "https://example.com/file.dmg", urls.first
  end

  def test_url_extraction_multiple_urls
    test_argv = [
      "https://example.com/file1.dmg",
      "-o",
      "output.dmg",
      "https://example.com/file2.pkg",
    ]

    urls = test_argv.select { |arg| URI.regexp(%w[http https]) =~ arg }

    assert_equal 2, urls.length
    assert_equal "https://example.com/file1.dmg", urls[0]
    assert_equal "https://example.com/file2.pkg", urls[1]
  end

  def test_url_extraction_no_urls
    test_argv = ["-L", "-I", "--silent"]

    urls = test_argv.select { |arg| URI.regexp(%w[http https]) =~ arg }

    assert_equal 0, urls.length
  end

  # Test: HEAD request detection
  def test_head_request_detection_dash_i
    test_argv = ["-I", "https://example.com/file.dmg"]

    is_head = test_argv.include?("-I") || test_argv.include?("--head")

    assert is_head, "Should detect -I as HEAD request"
  end

  def test_head_request_detection_dash_dash_head
    test_argv = ["--head", "https://example.com/file.dmg"]

    is_head = test_argv.include?("-I") || test_argv.include?("--head")

    assert is_head, "Should detect --head as HEAD request"
  end

  def test_head_request_detection_regular_request
    test_argv = ["-L", "https://example.com/file.dmg"]

    is_head = test_argv.include?("-I") || test_argv.include?("--head")

    refute is_head, "Should not detect regular request as HEAD"
  end

  # Test: Mirror URL construction
  def test_mirror_url_construction
    baseurl = "http://mirror.local:8000"
    mapped_file = "abc123.dmg"

    mirror_url = URI.join(baseurl, mapped_file)

    assert_equal "http://mirror.local:8000/abc123.dmg", mirror_url.to_s
  end

  def test_mirror_url_construction_with_trailing_slash
    baseurl = "http://mirror.local:8000/"
    mapped_file = "abc123.dmg"

    mirror_url = URI.join(baseurl, mapped_file)

    assert_equal "http://mirror.local:8000/abc123.dmg", mirror_url.to_s
  end

  # Test: Script structure and dependencies
  def test_script_requires_url_helpers
    script_content = File.read(@script_path, encoding: "UTF-8")

    assert_match(/require_relative.*url_helpers/, script_content)
  end

  def test_script_requires_offlinebrew_config
    script_content = File.read(@script_path, encoding: "UTF-8")

    assert_match(/require_relative.*offlinebrew_config/, script_content)
  end

  def test_script_uses_offlinebrew_config_paths
    script_content = File.read(@script_path, encoding: "UTF-8")

    assert_match(/OfflinebrewConfig\.config_path/, script_content)
    assert_match(/OfflinebrewConfig\.urlmap_path/, script_content)
  end

  # Test: Debug and verbose functions exist
  def test_script_has_debug_function
    script_content = File.read(@script_path, encoding: "UTF-8")

    assert_match(/def debug\(msg\)/, script_content)
    assert_match(/HOMEBREW_VERBOSE.*BREW_OFFLINE_DEBUG/, script_content)
  end

  def test_script_has_verbose_function
    script_content = File.read(@script_path, encoding: "UTF-8")

    assert_match(/def verbose\(msg\)/, script_content)
    assert_match(/HOMEBREW_VERBOSE/, script_content)
  end

  # Test: Error handling
  def test_script_handles_config_read_errors
    script_content = File.read(@script_path, encoding: "UTF-8")

    # Should have begin/rescue for config reading
    assert_match(/begin/, script_content)
    assert_match(/rescue.*RuntimeError/, script_content)
    assert_match(/raise/, script_content)
  end

  # Test: URL variant debugging
  def test_script_shows_variants_on_miss
    script_content = File.read(@script_path, encoding: "UTF-8")

    # Should show URL variants when debugging
    assert_match(/normalize_for_matching/, script_content)
    assert_match(/Tried variants/, script_content)
  end

  # Integration test: End-to-end with mock config
  #
  # This tests as much as possible without actually execing curl
  def test_integration_url_mapping_flow
    with_temp_dir do |tmpdir|
      # Setup
      baseurl = "http://mirror.local:8000"
      urlmap = {
        "https://example.com/file.dmg" => "abc123.dmg",
        "https://example.com/other.pkg" => "def456.pkg",
      }

      config = {
        baseurl: baseurl,
        taps: {
          "homebrew/homebrew-core" => { "commit" => "abc123" },
        },
      }

      config_path = File.join(tmpdir, "config.json")
      urlmap_path = File.join(tmpdir, "urlmap.json")

      File.write(config_path, JSON.pretty_generate(config))
      File.write(urlmap_path, JSON.pretty_generate(urlmap))

      # Simulate the script's URL mapping logic
      test_url = "https://example.com/file.dmg?version=1.0"

      # 1. Find URL in urlmap
      mapped_file = URLHelpers.find_in_urlmap(test_url, urlmap)
      assert_equal "abc123.dmg", mapped_file

      # 2. Construct mirror URL
      mirror_url = URI.join(baseurl, mapped_file)
      assert_equal "http://mirror.local:8000/abc123.dmg", mirror_url.to_s

      # 3. Verify config was read correctly
      loaded_config = JSON.parse(File.read(config_path), symbolize_names: true)
      assert_equal baseurl, loaded_config[:baseurl]

      # 4. Verify urlmap was read correctly
      loaded_urlmap = JSON.parse(File.read(urlmap_path))
      assert_equal "abc123.dmg", loaded_urlmap["https://example.com/file.dmg"]
    end
  end
end
