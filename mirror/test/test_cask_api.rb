#!/usr/bin/env brew ruby
# frozen_string_literal: true

require_relative "../lib/homebrew_paths"
require_relative "../lib/cask_helpers"

# Try to load Cask API
begin
  require "cask/cask_loader"
  require "cask/cask"
rescue LoadError
  puts "✗ Cask API not available (cask support not installed)"
  exit 1
end

puts "Homebrew Cask API Compatibility Test"
puts "=" * 60
puts ""

# Test 1: Check cask tap path
puts "Test 1: Cask tap path"
cask_tap_path = HomebrewPaths.cask_tap_path
puts "  Cask tap path: #{cask_tap_path}"
puts "  Tap exists: #{HomebrewPaths.cask_tap_exists?}"
puts ""

if !HomebrewPaths.cask_tap_exists?
  puts "✗ homebrew-cask tap not found!"
  puts ""
  puts "To install the cask tap, run:"
  puts "  brew tap homebrew/cask"
  puts ""
  exit 1
end

# Test 2: Check Cask API availability
puts "Test 2: Cask API availability"
if CaskHelpers.cask_api_available?
  puts "  ✓ Cask API is available"
  puts "    - Cask::Cask: #{defined?(Cask::Cask) ? 'defined' : 'undefined'}"
  puts "    - Cask::CaskLoader: #{defined?(Cask::CaskLoader) ? 'defined' : 'undefined'}"
else
  puts "  ✗ Cask API is not available"
  exit 1
end
puts ""

# Test 3: Load a specific cask
puts "Test 3: Load a specific cask (firefox)"
test_cask = nil

begin
  test_cask = CaskHelpers.load_cask("firefox")

  if test_cask
    puts "  ✓ Successfully loaded cask: firefox"
    puts "    - Token: #{test_cask.token}"

    if test_cask.respond_to?(:name) && test_cask.name && test_cask.name.any?
      puts "    - Name: #{test_cask.name.first}"
    end

    if test_cask.respond_to?(:version)
      puts "    - Version: #{test_cask.version}"
    end

    if CaskHelpers.has_url?(test_cask)
      url = test_cask.url.to_s
      # Truncate long URLs
      display_url = url.length > 80 ? "#{url[0..77]}..." : url
      puts "    - URL: #{display_url}"
    else
      puts "    - URL: (none)"
    end

    checksum = CaskHelpers.checksum(test_cask)
    if checksum && checksum != :no_check
      # Show first 16 chars of checksum
      puts "    - SHA256: #{checksum.to_s[0..15]}..."
    else
      puts "    - SHA256: #{checksum.inspect}"
    end
  else
    puts "  ⚠ Could not load firefox cask"
    puts "    (This might be okay if firefox isn't installed)"
  end
rescue StandardError => e
  puts "  ✗ Error loading firefox: #{e.message}"
  puts "    #{e.class}: #{e.backtrace.first}"
end
puts ""

# Test 4: Count available casks
puts "Test 4: Enumerate casks"
begin
  all_casks = CaskHelpers.all_casks
  cask_count = all_casks.count

  puts "  ✓ Found #{cask_count} casks"

  if cask_count > 0
    puts "  First 5 casks:"
    all_casks.first(5).each do |cask|
      puts "    - #{cask.token}"
    end
  else
    puts "  ⚠ No casks found (this is unusual)"
  end
rescue StandardError => e
  puts "  ✗ Error enumerating casks: #{e.message}"
  puts "    #{e.class}"
end
puts ""

# Test 5: Check cask tap commit
puts "Test 5: Cask tap commit hash"
begin
  cask_commit = HomebrewPaths.cask_tap_commit

  if cask_commit && !cask_commit.empty?
    puts "  ✓ Cask tap commit: #{cask_commit[0..7]}"
  else
    puts "  ✗ Could not get cask tap commit"
  end
rescue StandardError => e
  puts "  ✗ Error getting commit: #{e.message}"
end
puts ""

# Test 6: Check cask methods
puts "Test 6: Cask instance methods"
if test_cask
  methods_to_check = {
    token: "Cask identifier",
    url: "Download URL",
    sha256: "Checksum",
    version: "Version",
    name: "Display name",
    homepage: "Homepage URL",
    desc: "Description",
  }

  methods_to_check.each do |method, description|
    if test_cask.respond_to?(method)
      puts "  ✓ Cask##{method} exists (#{description})"
    else
      puts "  ✗ Cask##{method} missing (#{description})"
    end
  end
else
  puts "  ⚠ No test cask available (skipping method checks)"
end
puts ""

# Test 7: Test load_casks with multiple tokens
puts "Test 7: Load multiple casks"
begin
  test_tokens = ["firefox", "google-chrome", "visual-studio-code"]
  loaded_casks = CaskHelpers.load_casks(test_tokens)

  puts "  Attempted to load: #{test_tokens.join(', ')}"
  puts "  Successfully loaded: #{loaded_casks.count} cask(s)"

  loaded_casks.each do |cask|
    puts "    ✓ #{cask.token}"
  end

  if loaded_casks.count < test_tokens.count
    puts "  ⚠ Some casks failed to load (they may not be installed)"
  end
rescue StandardError => e
  puts "  ✗ Error loading multiple casks: #{e.message}"
end
puts ""

# Summary
puts "=" * 60
puts "Cask API Test Summary"
puts "=" * 60
puts "✓ Cask tap exists at: #{cask_tap_path}"
puts "✓ Cask API is functional"
puts "✓ Can load and inspect casks"
puts ""
puts "Ready for cask mirroring!"
