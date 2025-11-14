#!/usr/bin/env brew ruby
# frozen_string_literal: true

# TestApiGenerator: Unit tests for ApiGenerator module
#
# These tests verify API JSON generation for formulas following Homebrew's schema.
# Must run with `brew ruby` to access Formula API.
#
# Usage:
#   brew ruby mirror/test/lib/test_api_generator.rb

require "minitest/autorun"
require "json"
require "fileutils"
require "tmpdir"

# Load the ApiGenerator module we're testing
require_relative "../../lib/api_generator"

# We need Homebrew's libraries
abort "Make sure to run me via `brew ruby`!" unless Object.const_defined? :Homebrew

class TestApiGenerator < Minitest::Test
  def setup
    # Create a temporary directory for test output
    @test_dir = Dir.mktmpdir("api_generator_test")
    @api_dir = File.join(@test_dir, "api")
  end

  def teardown
    # Clean up temporary directory
    FileUtils.rm_rf(@test_dir) if @test_dir && File.exist?(@test_dir)
  end

  # Test: generate_formula_list produces valid JSON array
  def test_generates_formula_list_json
    # Use real formulas for testing
    formulas = [Formula["jq"], Formula["oniguruma"]]

    result = ApiGenerator.generate_formula_list(formulas)

    # Should return an array
    assert result.is_a?(Array), "Formula list should be an array"

    # Should contain formula names as strings
    assert_includes result, "jq"
    assert_includes result, "oniguruma"
    assert_equal 2, result.length

    # All entries should be strings
    assert result.all? { |name| name.is_a?(String) }
  end

  # Test: generate_formula_json produces valid formula object with required fields
  def test_generates_single_formula_json
    formula = Formula["jq"]

    result = ApiGenerator.generate_formula_json(formula)

    # Should return a hash
    assert result.is_a?(Hash), "Formula JSON should be a hash"

    # Check REQUIRED fields from HOMEBREW_API_SCHEMA.md
    assert_equal "jq", result[:name]
    assert result[:full_name].is_a?(String)
    assert result[:tap].is_a?(String)
    assert result[:desc].is_a?(String)
    assert result[:license].is_a?(String) || result[:license].nil?
    assert result[:homepage].is_a?(String)
    assert result[:versions].is_a?(Hash)
    assert result[:urls].is_a?(Hash)
    assert result[:revision].is_a?(Integer)
    assert result[:version_scheme].is_a?(Integer)
  end

  # Test: versions object structure
  def test_formula_json_versions_structure
    formula = Formula["jq"]

    result = ApiGenerator.generate_formula_json(formula)

    versions = result[:versions]
    assert versions.is_a?(Hash)
    assert versions[:stable].is_a?(String), "versions.stable should be a string"
    # head and bottle are optional
    assert [String, NilClass].include?(versions[:head].class)
    assert [TrueClass, FalseClass, NilClass].include?(versions[:bottle].class)
  end

  # Test: urls object structure
  def test_formula_json_urls_structure
    formula = Formula["jq"]

    result = ApiGenerator.generate_formula_json(formula)

    urls = result[:urls]
    assert urls.is_a?(Hash)

    # stable URL is required
    assert urls[:stable].is_a?(Hash)
    assert urls[:stable][:url].is_a?(String)
    assert urls[:stable][:checksum].is_a?(String)
  end

  # Test: bottle metadata is included when formula has bottles
  def test_includes_bottle_metadata
    # jq typically has bottles available
    formula = Formula["jq"]

    # Skip if formula doesn't have bottles
    skip "jq doesn't have bottles in this environment" unless formula.bottle

    result = ApiGenerator.generate_formula_json(formula)

    # Should have bottle section
    assert result[:bottle].is_a?(Hash), "Formula with bottles should have :bottle key"

    # Bottle should have stable section
    assert result[:bottle][:stable].is_a?(Hash)

    # Bottle should have files hash with platform-specific entries
    assert result[:bottle][:stable][:files].is_a?(Hash)

    # Each platform entry should have url and sha256
    result[:bottle][:stable][:files].each do |platform, data|
      assert data.is_a?(Hash), "Platform #{platform} data should be a hash"
      assert data[:url].is_a?(String), "Platform #{platform} should have url"
      assert data[:sha256].is_a?(String), "Platform #{platform} should have sha256"
    end
  end

  # Test: handles formula without bottles gracefully
  def test_handles_formula_without_bottles
    # Find a formula without bottles, or use mock
    formulas_without_bottles = Formula.to_a.select { |f| !f.bottle }

    if formulas_without_bottles.any?
      formula = formulas_without_bottles.first
      result = ApiGenerator.generate_formula_json(formula)

      # Should not have bottle section, or it should be nil/empty
      assert result[:bottle].nil? || result[:bottle].empty?,
        "Formula without bottles should not have populated :bottle key"
    else
      skip "No formulas without bottles found in test environment"
    end
  end

  # Test: dependencies are included correctly
  def test_includes_dependencies
    formula = Formula["jq"]

    result = ApiGenerator.generate_formula_json(formula)

    # Dependencies should be arrays (may be empty)
    assert result[:dependencies].is_a?(Array)
    assert result[:build_dependencies].is_a?(Array)

    # All dependency entries should be strings
    assert result[:dependencies].all? { |dep| dep.is_a?(String) }
    assert result[:build_dependencies].all? { |dep| dep.is_a?(String) }
  end

  # Test: validate_formula_json checks required fields
  def test_validates_formula_json_required_fields
    # Create minimal valid formula JSON
    valid_json = {
      name: "test",
      full_name: "test",
      tap: "homebrew/core",
      desc: "Test formula",
      license: "MIT",
      homepage: "https://example.com",
      versions: { stable: "1.0.0" },
      urls: { stable: { url: "https://example.com/test.tar.gz", checksum: "abc123" } },
      revision: 0,
      version_scheme: 0
    }

    # Should not raise error
    assert ApiGenerator.validate_formula_json(valid_json)
  end

  # Test: validate_formula_json detects missing required fields
  def test_validates_formula_json_missing_fields
    # Create incomplete formula JSON (missing required fields)
    invalid_json = {
      name: "test",
      # Missing other required fields
    }

    # Should return false or raise error
    refute ApiGenerator.validate_formula_json(invalid_json)
  end

  # Test: generate_all creates directory structure and files
  def test_generate_all_creates_files
    formulas = [Formula["jq"]]

    ApiGenerator.generate_all(formulas, @api_dir)

    # Should create api directory
    assert File.directory?(@api_dir), "API directory should be created"

    # Should create formula.json
    formula_list_file = File.join(@api_dir, "formula.json")
    assert File.exist?(formula_list_file), "formula.json should be created"

    # Should create formula subdirectory
    formula_subdir = File.join(@api_dir, "formula")
    assert File.directory?(formula_subdir), "formula subdirectory should be created"

    # Should create individual formula JSON files
    jq_file = File.join(formula_subdir, "jq.json")
    assert File.exist?(jq_file), "jq.json should be created"

    # Verify files contain valid JSON
    formula_list = JSON.parse(File.read(formula_list_file))
    assert formula_list.is_a?(Array)

    jq_json = JSON.parse(File.read(jq_file))
    assert jq_json.is_a?(Hash)
    assert_equal "jq", jq_json["name"]
  end

  # Test: extract_bottle_metadata formats bottles correctly
  def test_extract_bottle_metadata
    formula = Formula["jq"]

    # Skip if no bottles
    skip "jq doesn't have bottles in this environment" unless formula.bottle

    result = ApiGenerator.extract_bottle_metadata(formula)

    # Should return a hash with stable key
    assert result.is_a?(Hash)
    assert result[:stable].is_a?(Hash)

    # Should have files hash
    assert result[:stable][:files].is_a?(Hash)

    # Should have at least one platform
    assert result[:stable][:files].any?, "Should have at least one platform"
  end

  # Test: JSON output matches Homebrew schema structure
  def test_json_output_matches_homebrew_schema
    formula = Formula["jq"]

    result = ApiGenerator.generate_formula_json(formula)

    # Convert to JSON and parse back (simulates real usage)
    json_string = JSON.generate(result)
    parsed = JSON.parse(json_string)

    # Key required fields should be present
    %w[name full_name tap desc homepage versions urls revision version_scheme].each do |field|
      assert parsed.key?(field), "Should have #{field} field"
    end

    # versions should have stable
    assert parsed["versions"].key?("stable")

    # urls should have stable with url and checksum
    assert parsed["urls"]["stable"].key?("url")
    assert parsed["urls"]["stable"].key?("checksum")
  end

  # Test: handles multiple formulas correctly
  def test_generate_all_multiple_formulas
    formulas = [Formula["jq"], Formula["oniguruma"]]

    ApiGenerator.generate_all(formulas, @api_dir)

    # Check formula.json contains both
    formula_list_file = File.join(@api_dir, "formula.json")
    formula_list = JSON.parse(File.read(formula_list_file))

    assert_includes formula_list, "jq"
    assert_includes formula_list, "oniguruma"

    # Check individual files exist
    jq_file = File.join(@api_dir, "formula", "jq.json")
    oniguruma_file = File.join(@api_dir, "formula", "oniguruma.json")

    assert File.exist?(jq_file)
    assert File.exist?(oniguruma_file)
  end

  # Test: generated JSON is valid and parseable
  def test_generated_json_is_valid
    formulas = [Formula["jq"]]

    ApiGenerator.generate_all(formulas, @api_dir)

    # Parse all generated JSON files
    formula_list_file = File.join(@api_dir, "formula.json")
    jq_file = File.join(@api_dir, "formula", "jq.json")

    # Should not raise JSON parse errors
    assert JSON.parse(File.read(formula_list_file))
    assert JSON.parse(File.read(jq_file))
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
  puts "ApiGenerator Unit Tests"
  puts "=" * 70
  puts ""

  exit Minitest.run
end
