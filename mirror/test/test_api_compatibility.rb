#!/usr/bin/env brew ruby
# frozen_string_literal: true

# Test script to verify Homebrew API compatibility
# Run with: brew ruby mirror/test/test_api_compatibility.rb
#
# This script tests that brew-mirror is compatible with the current
# Homebrew version by checking that all required APIs still exist.

require_relative "../lib/homebrew_paths"

puts "Homebrew API Compatibility Test"
puts "=" * 70
puts ""

# Test 1: Check if running under brew ruby
abort "ERROR: Must run with `brew ruby`!" unless Object.const_defined?(:Homebrew)
puts "✓ Running under brew ruby"

# Test 2: Check Homebrew version
brew_version = `brew --version`.lines.first.chomp
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

# Test 4: Check Formula iteration methods
puts "  Testing Formula iteration..."
iterator_method = nil
formula_count = 0
begin
  # Try new API first (Formula.all)
  if Formula.respond_to?(:all)
    formula_count = Formula.all.count
    iterator_method = "Formula.all"
    puts "  ✓ Formula iteration: #{iterator_method} (#{formula_count} formulae)"
  # Fall back to old API (Formula.each)
  elsif Formula.respond_to?(:each)
    formula_count = Formula.each.count
    iterator_method = "Formula.each"
    puts "  ✓ Formula iteration: #{iterator_method} (#{formula_count} formulae)"
    puts "  ⚠ Warning: Formula.each may be deprecated, prefer Formula.all"
  else
    abort "  ✗ No Formula iteration method found (tried .all and .each)"
  end
rescue StandardError => e
  puts "  ✗ Formula iteration failed: #{e.message}"
  abort "FATAL: Cannot iterate formulae"
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
puts "  Total formulae available: #{formula_count}"
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
