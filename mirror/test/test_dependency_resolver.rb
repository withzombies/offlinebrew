#!/usr/bin/env brew ruby
# frozen_string_literal: true

# TestDependencyResolver: Unit tests for DependencyResolver module
#
# These tests verify dependency resolution for formulas and casks.
# Must run with `brew ruby` to access Formula and Cask APIs.
#
# Usage:
#   brew ruby mirror/test/test_dependency_resolver.rb

require "minitest/autorun"
require "set"
require_relative "../lib/dependency_resolver"

# We need Homebrew's libraries
abort "Make sure to run me via `brew ruby`!" unless Object.const_defined? :Homebrew

# Load Cask API if available
begin
  require "cask/cask_loader"
  require "cask/cask"
  CASK_AVAILABLE = true
rescue LoadError
  CASK_AVAILABLE = false
end

class TestDependencyResolver < Minitest::Test
  # Test: Empty input returns empty result
  def test_resolve_formulas_empty_input
    result = DependencyResolver.resolve_formulas([])
    assert_equal [], result
  end

  def test_resolve_formulas_nil_input
    result = DependencyResolver.resolve_formulas(nil)
    assert_equal [], result
  end

  # Test: Single formula with no dependencies
  def test_resolve_formula_no_dependencies
    # jq typically has only one or two dependencies
    result = DependencyResolver.resolve_formulas(["jq"])

    assert_includes result, "jq"
    assert result.is_a?(Array)
    assert result.all? { |name| name.is_a?(String) }

    # Should be sorted
    assert_equal result, result.sort
  end

  # Test: Formula with dependencies
  def test_resolve_formula_with_dependencies
    # wget has several dependencies: gettext, libidn2, libunistring, openssl@3
    result = DependencyResolver.resolve_formulas(["wget"])

    assert_includes result, "wget"
    # wget has known dependencies
    assert result.size > 1, "wget should have dependencies"

    # Common dependencies (may vary by Homebrew version)
    # At minimum, wget typically depends on openssl
    has_known_deps = result.any? { |name| name.include?("openssl") } ||
                     result.any? { |name| name.include?("gettext") }
    assert has_known_deps, "wget should have common dependencies like openssl or gettext"
  end

  # Test: Multiple formulas with shared dependencies
  def test_resolve_multiple_formulas_deduplication
    # Both wget and curl depend on openssl
    result = DependencyResolver.resolve_formulas(["wget", "curl"])

    assert_includes result, "wget"
    assert_includes result, "curl"

    # Should not have duplicates
    assert_equal result, result.uniq

    # Should be sorted
    assert_equal result, result.sort
  end

  # Test: Recursive dependency resolution
  def test_recursive_dependency_resolution
    # Pick a formula with multi-level dependencies
    # git typically has several layers of dependencies
    result = DependencyResolver.resolve_formulas(["git"])

    assert_includes result, "git"
    # git has many dependencies
    assert result.size > 3, "git should have multiple dependencies"
  end

  # Test: Build dependencies (opt-in)
  def test_resolve_formula_with_build_dependencies
    # Test with a formula that has build dependencies
    result_without_build = DependencyResolver.resolve_formulas(["wget"], include_build: false)
    result_with_build = DependencyResolver.resolve_formulas(["wget"], include_build: true)

    assert result_with_build.size >= result_without_build.size,
      "With build deps should have same or more formulas"
  end

  # Test: Optional dependencies (opt-in)
  def test_resolve_formula_with_optional_dependencies
    # Test optional dependencies
    result_without_optional = DependencyResolver.resolve_formulas(["wget"], include_optional: false)
    result_with_optional = DependencyResolver.resolve_formulas(["wget"], include_optional: true)

    assert result_with_optional.size >= result_without_optional.size,
      "With optional deps should have same or more formulas"
  end

  # Test: Non-existent formula handling
  def test_resolve_nonexistent_formula
    # Should handle gracefully without crashing
    result = DependencyResolver.resolve_formulas(["nonexistent-formula-12345"])

    # Should return empty or not include the nonexistent formula
    refute_includes result, "nonexistent-formula-12345"
  end

  # Test: Mixed existent and non-existent formulas
  def test_resolve_mixed_formulas
    result = DependencyResolver.resolve_formulas(["jq", "nonexistent-formula-12345"])

    # Should include valid formula
    assert_includes result, "jq"

    # Should not include invalid formula
    refute_includes result, "nonexistent-formula-12345"
  end

  # Test: Circular dependency handling
  # Note: Homebrew shouldn't have circular dependencies, but we should handle it gracefully
  def test_circular_dependency_protection
    # Our visited tracking should prevent infinite loops
    # This is more of a structural test - the algorithm should complete
    result = DependencyResolver.resolve_formulas(["python@3.11"])

    # Should complete without hanging
    assert result.is_a?(Array)
    assert result.size > 0
  end

  # Test: Large dependency tree
  def test_large_dependency_tree
    skip "Slow test - only run on demand" unless ENV["RUN_SLOW_TESTS"]

    # python has many dependencies
    result = DependencyResolver.resolve_formulas(["python@3.11"])

    assert_includes result, "python@3.11"
    # python has many dependencies (typically 15+)
    assert result.size > 10, "python should have many dependencies"
  end

  # Cask tests (only if Cask API is available)
  def test_resolve_cask_empty_input
    skip "Cask API not available" unless CASK_AVAILABLE

    result = DependencyResolver.resolve_casks([])
    assert_equal({ casks: [], formulas: [] }, result)
  end

  def test_resolve_cask_nil_input
    skip "Cask API not available" unless CASK_AVAILABLE

    result = DependencyResolver.resolve_casks(nil)
    assert_equal({ casks: [], formulas: [] }, result)
  end

  def test_resolve_cask_no_dependencies
    skip "Cask API not available" unless CASK_AVAILABLE
    skip "Requires internet to fetch cask data" unless ENV["RUN_ONLINE_TESTS"]

    # Most casks don't have dependencies
    # Use a simple cask like "1password-cli"
    result = DependencyResolver.resolve_casks(["1password-cli"])

    assert_includes result[:casks], "1password-cli"
    assert result[:formulas].is_a?(Array)
  end

  def test_resolve_cask_with_formula_dependencies
    skip "Cask API not available" unless CASK_AVAILABLE
    skip "Requires internet to fetch cask data" unless ENV["RUN_ONLINE_TESTS"]

    # Some casks depend on formulas
    # docker cask typically depends on docker formula
    # This may vary, so we test the structure
    result = DependencyResolver.resolve_casks(["docker"])

    assert result.is_a?(Hash)
    assert result.key?(:casks)
    assert result.key?(:formulas)
    assert result[:casks].is_a?(Array)
    assert result[:formulas].is_a?(Array)
  end

  def test_resolve_nonexistent_cask
    skip "Cask API not available" unless CASK_AVAILABLE

    result = DependencyResolver.resolve_casks(["nonexistent-cask-12345"])

    # Should handle gracefully
    refute_includes result[:casks], "nonexistent-cask-12345"
  end

  # Performance test
  def test_dependency_resolution_performance
    skip "Performance test - only run on demand" unless ENV["RUN_PERFORMANCE_TESTS"]

    require "benchmark"

    time = Benchmark.realtime do
      DependencyResolver.resolve_formulas(["wget", "jq", "curl", "git"])
    end

    # Should complete in reasonable time (< 5 seconds)
    assert time < 5.0, "Dependency resolution took too long: #{time}s"

    puts "\n  Performance: Resolved 4 formulas in #{time.round(3)}s"
  end

  # Debug mode test
  def test_debug_mode_output
    # Test that debug mode doesn't crash
    ENV["BREW_OFFLINE_DEBUG"] = "1"

    result = DependencyResolver.resolve_formulas(["jq"])

    assert_includes result, "jq"
  ensure
    ENV.delete("BREW_OFFLINE_DEBUG")
  end

  # Edge case: Formula name with special characters or versions
  def test_resolve_versioned_formula
    # Test with a versioned formula like openssl@3
    result = DependencyResolver.resolve_formulas(["openssl@3"])

    assert_includes result, "openssl@3"
  end

  # Test: Formulas are returned sorted
  def test_formulas_returned_sorted
    result = DependencyResolver.resolve_formulas(["wget", "jq", "curl"])

    assert_equal result, result.sort,
      "Results should be returned in sorted order"
  end

  # Test: Casks are returned sorted
  def test_casks_returned_sorted
    skip "Cask API not available" unless CASK_AVAILABLE
    skip "Requires internet to fetch cask data" unless ENV["RUN_ONLINE_TESTS"]

    result = DependencyResolver.resolve_casks(["zoom", "slack", "firefox"])

    assert_equal result[:casks], result[:casks].sort,
      "Casks should be returned in sorted order"
    assert_equal result[:formulas], result[:formulas].sort,
      "Formulas should be returned in sorted order"
  end

  # Helper: Check if Homebrew is available
  def homebrew_available?
    system("which brew > /dev/null 2>&1")
  end

  # Helper: Check if formula exists
  def formula_exists?(name)
    Formula[name]
    true
  rescue FormulaUnavailableError
    false
  end

  # Helper: Check if cask exists
  def cask_exists?(token)
    return false unless CASK_AVAILABLE
    Cask::Cask.load(token)
    true
  rescue Cask::CaskUnavailableError
    false
  end
end

# Run tests if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  # Suppress Homebrew output during tests unless verbose
  unless ENV["VERBOSE"]
    def ohai(*)
      # Suppress
    end

    def opoo(*)
      # Suppress
    end
  end

  puts "\n" + "=" * 70
  puts "DependencyResolver Unit Tests"
  puts "=" * 70
  puts ""

  exit Minitest.run
end
