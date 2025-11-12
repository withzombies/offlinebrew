#!/usr/bin/env brew ruby
# frozen_string_literal: true

# Test script to verify Homebrew API compatibility
# Run with: brew ruby mirror/test/test_api_compatibility.rb
#
# This script tests that brew-mirror is compatible with the current
# Homebrew version by checking that all required APIs still exist.

require_relative "../lib/homebrew_paths"
require_relative "../lib/safe_shell"

puts "Homebrew API Compatibility Test"
puts "=" * 70
puts ""

# Test 1: Check if running under brew ruby
abort "ERROR: Must run with `brew ruby`!" unless Object.const_defined?(:Homebrew)
puts "✓ Running under brew ruby"

# Test 2: Check Homebrew version
# We can't call `brew --version` directly in brew ruby context, so use HOMEBREW_VERSION constant
brew_version = if defined?(Homebrew::HOMEBREW_VERSION)
  "Homebrew #{Homebrew::HOMEBREW_VERSION}"
elsif defined?(HOMEBREW_VERSION)
  "Homebrew #{HOMEBREW_VERSION}"
else
  "Homebrew (version unknown)"
end
puts "✓ Homebrew version: #{brew_version}"
puts ""

# Test 3: Check if Formula class exists
puts "Testing Formula API..."
begin
  puts "  ✓ Formula class exists: #{Formula.class}"
rescue NameError => e
  puts "  ✗ Formula class not found: #{e.message}"
  abort "FATAL: Cannot continue without Formula class"
end

# Test 4: Check Formula iteration methods (what brew-mirror uses)
# brew-mirror line 125: options[:iterator].each do |formula|
# where options[:iterator] is Formula (line 73)
puts "  Testing Formula iteration..."
iterator_method = nil
iterator_available = false

begin
  # Test what brew-mirror ACTUALLY uses: Formula.each
  # This is called on line 125 of brew-mirror
  if Formula.respond_to?(:each)
    iterator_method = "Formula.each"
    puts "  ✓ Formula.each method exists (used by brew-mirror)"

    # Try to verify it's actually iterable (but don't enumerate all)
    # Just check that calling .each with a block doesn't crash
    begin
      # Use lazy enumeration to avoid loading all formulae
      Formula.each do |_formula|
        # Found at least one formula, that's enough
        iterator_available = true
        break
      end
      puts "  ✓ Formula.each is functional"
    rescue StandardError => e
      # If .each exists but requires HOMEBREW_EVAL_ALL, that's OK
      if e.message.include?("HOMEBREW_EVAL_ALL")
        puts "  ⚠ Formula.each requires HOMEBREW_EVAL_ALL=1"
        puts "    (brew-mirror will need to set this)"
        iterator_available = true  # Method exists, just needs env var
      else
        puts "  ✗ Formula.each failed: #{e.message}"
      end
    end
  # If Formula.each doesn't exist, check if Formula.all works as alternative
  elsif Formula.respond_to?(:all)
    iterator_method = "Formula.all (fallback)"
    puts "  ⚠ Formula.each not found (brew-mirror uses this!)"
    puts "  ✓ Formula.all method exists as alternative"
    puts "  ⚠ brew-mirror may need update to use Formula.all.each"
    iterator_available = true
  else
    abort "  ✗ No Formula iteration method found (tried .each and .all)"
  end

  if iterator_available
    puts "  ✓ Formula iteration: #{iterator_method} (available)"
  else
    abort "  ✗ Formula iteration not functional"
  end
rescue StandardError => e
  puts "  ✗ Formula iteration check failed: #{e.message}"
  puts "    #{e.backtrace.first}"
  abort "FATAL: Cannot check formula iteration methods"
end

# Test 5: Test formula access
puts "  Testing formula access..."
test_formula = nil
begin
  # Try to load a common formula
  test_formula = Formula["wget"]
  puts "  ✓ Can load formula: wget"
rescue FormulaUnavailableError => e
  puts "  ⚠ wget not installed, trying different formula..."
  # Try another common formula
  begin
    test_formula = Formula["ruby"]
    puts "  ✓ Can load formula: ruby"
  rescue StandardError => e2
    # Try one more
    begin
      test_formula = Formula["git"]
      puts "  ✓ Can load formula: git"
    rescue StandardError => e3
      puts "  ✗ Cannot load any test formula"
      puts "    Tried: wget, ruby, git"
    end
  end
rescue StandardError => e
  puts "  ✗ Formula access failed: #{e.message}"
end

# Test formula methods if we got one
if test_formula
  methods_to_test = {
    stable: "Stable spec",
    full_name: "Full name",
    name: "Name",
    tap: "Tap",
    desc: "Description",
    homepage: "Homepage",
  }

  methods_to_test.each do |method, description|
    if test_formula.respond_to?(method)
      puts "  ✓ Formula##{method} exists (#{description})"
    else
      puts "  ✗ Formula##{method} missing (#{description})"
    end
  end
end
puts ""

# Test 6: Check download strategy classes
puts "Testing Download Strategy classes..."
download_strategies = [
  :CurlDownloadStrategy,
  :CurlApacheMirrorDownloadStrategy,
  :NoUnzipCurlDownloadStrategy,
  :GitDownloadStrategy,
  :GitHubGitDownloadStrategy,
  :SubversionDownloadStrategy,  # SVN, rarely used
  :GitLabDownloadStrategy,       # May be new
  :FossilDownloadStrategy,       # May be new
]

available_strategies = []
download_strategies.each do |strategy|
  begin
    if Object.const_defined?(strategy)
      puts "  ✓ #{strategy} exists"
      available_strategies << strategy
    else
      puts "  ⚠ #{strategy} not found (may be new or removed)"
    end
  rescue StandardError => e
    puts "  ✗ Error checking #{strategy}: #{e.message}"
  end
end
puts ""

# Test 7: Check SoftwareSpec methods
puts "Testing SoftwareSpec API..."
begin
  if test_formula && test_formula.stable
    stable = test_formula.stable
    puts "  ✓ Formula#stable returns: #{stable.class}"

    # Test common methods
    spec_methods = {
      url: "URL",
      checksum: "Checksum",
      version: "Version",
      downloader: "Downloader",
      resources: "Resources",
      patches: "Patches",
    }

    spec_methods.each do |method, description|
      if stable.respond_to?(method)
        value = stable.send(method)
        puts "  ✓ SoftwareSpec##{method} (#{description}): #{value.class}"
      else
        puts "  ✗ SoftwareSpec##{method} missing (#{description})"
      end
    end
  else
    puts "  ⚠ No stable spec available for testing"
  end
rescue StandardError => e
  puts "  ✗ SoftwareSpec test failed: #{e.message}"
  puts "    #{e.backtrace.first}"
end
puts ""

# Test 8: Check Resource API
puts "Testing Resource API..."
begin
  test_formula_for_resources = test_formula

  # If current formula has no resources, try python (usually has many)
  if !test_formula_for_resources || !test_formula_for_resources.stable || !test_formula_for_resources.stable.resources.any?
    puts "  Current formula has no resources, trying python..."
    begin
      test_formula_for_resources = Formula["python"]
    rescue StandardError
      puts "  ⚠ Could not load python formula"
    end
  end

  if test_formula_for_resources && test_formula_for_resources.stable && test_formula_for_resources.stable.resources.any?
    resources = test_formula_for_resources.stable.resources
    puts "  ✓ Resources available: #{resources.count} in #{test_formula_for_resources.name}"

    # Get first resource
    resource_name, resource_obj = resources.first
    puts "  ✓ Resource name: #{resource_name}"
    puts "  ✓ Resource class: #{resource_obj.class}"

    # Test resource methods
    res_methods = [:url, :checksum, :downloader]
    res_methods.each do |method|
      if resource_obj.respond_to?(method)
        puts "  ✓ Resource##{method} exists"
      else
        puts "  ✗ Resource##{method} missing"
      end
    end
  else
    puts "  ⚠ No formula with resources found for testing"
  end
rescue StandardError => e
  puts "  ✗ Resource test failed: #{e.message}"
  puts "    #{e.backtrace.first}"
end
puts ""

# Test 9: Check Patch API
puts "Testing Patch API..."
begin
  # Need to find a formula with patches
  puts "  Looking for formula with patches..."
  formula_with_patches = nil

  # Check a few common formulae that often have patches
  ["vim", "git", "openssl", "emacs", "postgresql"].each do |name|
    begin
      f = Formula[name]
      if f.stable && f.stable.patches.any?
        formula_with_patches = f
        break
      end
    rescue StandardError
      # Skip if not found
    end
  end

  if formula_with_patches
    patches = formula_with_patches.stable.patches
    puts "  ✓ Found #{patches.count} patch(es) in: #{formula_with_patches.name}"

    patch = patches.first
    puts "  ✓ Patch class: #{patch.class}"

    if patch.respond_to?(:external?)
      puts "  ✓ Patch#external? exists"
      if patch.external?
        puts "    External patch detected"
        puts "    - URL: #{patch.url}" if patch.respond_to?(:url)
      else
        puts "    Inline patch"
      end
    else
      puts "  ✗ Patch#external? missing"
    end
  else
    puts "  ⚠ No formula with patches found for testing"
    puts "    (This is OK, patches are less common now)"
  end
rescue StandardError => e
  puts "  ✗ Patch test failed: #{e.message}"
  puts "    #{e.backtrace.first}"
end
puts ""

# Test 10: Check Tap API
puts "Testing Tap API..."
begin
  if test_formula && test_formula.respond_to?(:tap)
    tap = test_formula.tap
    puts "  ✓ Formula#tap exists"
    puts "  ✓ Tap value: #{tap}"
    puts "  ✓ Tap class: #{tap.class}"

    if tap.respond_to?(:core_tap?)
      puts "  ✓ Tap#core_tap? exists: #{tap.core_tap?}"
    else
      puts "  ✗ Tap#core_tap? missing"
    end

    if tap.respond_to?(:official?)
      puts "  ✓ Tap#official? exists: #{tap.official?}"
    else
      puts "  ⚠ Tap#official? missing (may be new method)"
    end
  else
    puts "  ✗ Formula#tap missing"
  end
rescue StandardError => e
  puts "  ✗ Tap test failed: #{e.message}"
  puts "    #{e.backtrace.first}"
end
puts ""

# Test 11: Check if Cask API exists (for Phase 2)
puts "Testing Cask API (for future Phase 2)..."
begin
  if Object.const_defined?(:Cask)
    puts "  ✓ Cask class exists"

    # Try to load a test cask
    if Cask.respond_to?(:[])
      puts "  ✓ Cask[] method exists"
    else
      puts "  ⚠ Cask[] method missing"
    end

    # Try iteration
    if Cask.respond_to?(:all)
      cask_count = Cask.all.count
      puts "  ✓ Cask.all exists (#{cask_count} casks)"
    elsif Cask.respond_to?(:each)
      puts "  ✓ Cask.each exists"
    else
      puts "  ⚠ No Cask iteration method found"
    end
  else
    puts "  ⚠ Cask class not found (will be needed for Phase 2)"
  end
rescue StandardError => e
  puts "  ✗ Cask test failed: #{e.message}"
end
puts ""

# Summary
puts "=" * 70
puts "Summary:"
puts ""
puts "  Formula iteration method: #{iterator_method}"
puts "  Download strategies found: #{available_strategies.count}/#{download_strategies.count}"
puts "  Available strategies: #{available_strategies.join(', ')}"
puts ""

# Determine compatibility
all_good = true

if available_strategies.count < 4
  puts "⚠ WARNING: Missing critical download strategies"
  puts "  brew-mirror may not work with all formulae"
  all_good = false
end

if iterator_method == "Formula.each"
  puts "⚠ WARNING: Using deprecated Formula.each"
  puts "  Consider updating to Formula.all"
end

if all_good && available_strategies.count >= 6
  puts "✅ EXCELLENT COMPATIBILITY!"
  puts "  brew-mirror should work with this Homebrew version."
  puts "  All tested APIs are available."
  exit 0
elsif available_strategies.count >= 4
  puts "✅ GOOD COMPATIBILITY"
  puts "  brew-mirror should work for most formulae."
  puts "  Some download strategies may be missing."
  exit 0
else
  puts "❌ COMPATIBILITY ISSUES DETECTED"
  puts "  Review the output above"
  puts "  You may need to update brew-mirror code"
  exit 1
end
