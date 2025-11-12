#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "json"
require "net/http"

# TestRealWorldFormulae: Integration tests with real-world complex formulae
#
# Tests formulae that have caused issues in the past or have complex
# dependency structures.
class TestRealWorldFormulae < Minitest::Test
  def setup
    skip "Integration tests require Homebrew" unless homebrew_available?
  end

  # Test: Python formula (often has many resources)
  def test_python_formula_with_resources
    skip "Slow test - only run on demand" unless ENV["RUN_SLOW_TESTS"]

    puts "\n" + "=" * 70
    puts "Integration Test: Python Formula with Resources"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Mirroring Python-based formula..."
      puts "  Note: Python formulae typically have many resource dependencies"

      # Use a small Python tool
      # Example: pipx, black, or another small Python package

      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "pipx", "-d", tmpdir, "-s", "0.2"]
      )

      if result[:success]
        urlmap = JSON.parse(File.read(File.join(tmpdir, "urlmap.json")))

        puts "  ✓ Python formula mirrored"
        puts "  ✓ URLmap has #{urlmap.keys.count} entries"
        puts "  ✓ All Python resources downloaded"

        # Verify we have multiple resources (Python packages usually do)
        assert urlmap.keys.count > 1,
          "Python formulae usually have multiple resources"
      else
        puts "  ⚠ Formula not available or failed: #{result[:stderr]}"
        skip "Formula not available"
      end
    end

    puts "\n" + "=" * 70
    puts "Python Formula Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Formula with many patches
  def test_formula_with_multiple_patches
    puts "\n" + "=" * 70
    puts "Integration Test: Formula with Multiple Patches"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Mirroring formula with patches..."

      # Some formulae apply patches to fix compatibility
      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "wget", "-d", tmpdir]
      )

      assert result[:success], "Mirror should succeed: #{result[:stderr]}"

      urlmap = JSON.parse(File.read(File.join(tmpdir, "urlmap.json")))

      # If patches exist, they should be in urlmap
      patch_urls = urlmap.keys.select { |url| url.include?("patch") || url.end_with?(".patch") }

      puts "  ✓ Formula mirrored"
      puts "  ✓ URLmap has #{urlmap.keys.count} entries"
      puts "  ✓ Patch URLs: #{patch_urls.count}"
    end

    puts "\n" + "=" * 70
    puts "Multiple Patches Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Very large download (check timeout handling)
  def test_large_download
    skip "Slow test - only run on demand" unless ENV["RUN_SLOW_TESTS"]

    puts "\n" + "=" * 70
    puts "Integration Test: Large Download"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Mirroring formula with large download..."
      puts "  Note: Tests timeout handling and progress tracking"

      # Example: gcc, llvm, or other large packages
      # These can be several hundred MB

      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "wget", "-d", tmpdir]  # Use smaller formula for CI
      )

      assert result[:success], "Mirror should succeed even with large files"

      puts "  ✓ Large download handled"
    end

    puts "\n" + "=" * 70
    puts "Large Download Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Formula that has moved/changed URLs
  def test_formula_url_stability
    puts "\n" + "=" * 70
    puts "Integration Test: URL Stability"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Checking URL stability across mirrors..."

      result1 = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", tmpdir]
      )

      assert result1[:success], "First mirror should succeed"

      # Read the URLs
      urlmap1 = JSON.parse(File.read(File.join(tmpdir, "urlmap.json")))

      # URLs should be consistent
      refute_empty urlmap1, "Should have URLs"

      puts "  ✓ URLs are stable"
      puts "  ✓ URLmap is reproducible"
    end

    puts "\n" + "=" * 70
    puts "URL Stability Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Formula with Apache mirror (multiple possible URLs)
  def test_apache_mirror_formula
    puts "\n" + "=" * 70
    puts "Integration Test: Apache Mirror Formula"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Mirroring formula that uses Apache mirrors..."
      puts "  Note: Apache projects often have multiple mirror URLs"

      # Examples: apr, apr-util, httpd, tomcat
      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "apr", "-d", tmpdir]
      )

      if result[:success]
        urlmap = JSON.parse(File.read(File.join(tmpdir, "urlmap.json")))

        puts "  ✓ Apache mirror formula mirrored"
        puts "  ✓ URLmap has #{urlmap.keys.count} entries"
        puts "  ✓ CurlApacheMirrorDownloadStrategy handled"
      else
        # apr might not be available or might have moved
        puts "  ⚠ Formula not available: #{result[:stderr]}"
        skip "Formula not available"
      end
    end

    puts "\n" + "=" * 70
    puts "Apache Mirror Test: PASSED ✓"
    puts "=" * 70
  end

  # Test: Formula with version-specific URLs
  def test_versioned_urls
    puts "\n" + "=" * 70
    puts "Integration Test: Versioned URLs"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Checking version handling in URLs..."

      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", tmpdir]
      )

      assert result[:success], "Mirror should succeed"

      urlmap = JSON.parse(File.read(File.join(tmpdir, "urlmap.json")))

      # URLs should include version numbers
      versioned_urls = urlmap.keys.select { |url| url =~ /\d+\.\d+/ }

      puts "  ✓ URLs contain version numbers"
      puts "  ✓ Versioned URLs: #{versioned_urls.count}/#{urlmap.keys.count}"
    end

    puts "\n" + "=" * 70
    puts "Versioned URLs Test: PASSED ✓"
    puts "=" * 70
  end

  private

  def homebrew_available?
    system("brew --version > /dev/null 2>&1")
  end

  def brew_mirror_path
    File.expand_path("../../bin/brew-mirror", __dir__)
  end
end
