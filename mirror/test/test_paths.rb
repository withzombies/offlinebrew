#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/homebrew_paths"

puts "Homebrew Path Detection Test"
puts "=" * 60
puts ""

# Test 1: Homebrew Installation
puts "Test 1: Homebrew Installation"
puts "-" * 60
if HomebrewPaths.homebrew_installed?
  puts "  ✓ Homebrew is installed"
  version = HomebrewPaths.homebrew_version
  puts "  ✓ Version: #{version}" if version
else
  puts "  ✗ Homebrew is NOT installed"
  puts "    Please install Homebrew: https://brew.sh"
end
puts ""

# Test 2: Path Detection
puts "Test 2: Detected Paths"
puts "-" * 60
HomebrewPaths.all_paths.each do |name, path|
  exists = Dir.exist?(path) || File.exist?(path)
  status = exists ? "✓" : "✗"
  puts "  #{status} #{name.to_s.ljust(12)}: #{path}"
end
puts ""

# Test 3: Tap Existence
puts "Test 3: Tap Existence"
puts "-" * 60
if HomebrewPaths.core_tap_exists?
  puts "  ✓ homebrew-core tap exists"
  commit = HomebrewPaths.core_tap_commit
  puts "    Current commit: #{commit[0..7]}" if commit
else
  puts "  ✗ homebrew-core tap NOT found"
  puts "    Run: brew tap homebrew/core"
end

if HomebrewPaths.cask_tap_exists?
  puts "  ✓ homebrew-cask tap exists"
  commit = HomebrewPaths.cask_tap_commit
  puts "    Current commit: #{commit[0..7]}" if commit
else
  puts "  ⚠  homebrew-cask tap NOT found"
  puts "    Run: brew tap homebrew/cask"
end
puts ""

# Test 4: Platform Detection
puts "Test 4: Platform Information"
puts "-" * 60
puts "  Ruby Platform: #{RUBY_PLATFORM}"
if RUBY_PLATFORM.include?("arm64") || RUBY_PLATFORM.include?("aarch64")
  puts "  Architecture:  Apple Silicon / ARM64"
  puts "  Expected prefix: /opt/homebrew"
else
  puts "  Architecture:  Intel / x86_64"
  puts "  Expected prefix: /usr/local"
end
puts "  Actual prefix: #{HomebrewPaths.homebrew_prefix}"
puts ""

# Test 5: Summary
puts "Test 5: Summary"
puts "-" * 60
all_exist = HomebrewPaths.all_paths.values.all? { |p| Dir.exist?(p) || File.exist?(p) }
if all_exist && HomebrewPaths.homebrew_installed?
  puts "  ✓ All tests passed!"
  puts "  ✓ Homebrew paths are correctly detected"
  puts "  ✓ Ready for offlinebrew operations"
else
  puts "  ⚠  Some paths are missing"
  puts "  Please ensure Homebrew is properly installed"
  puts "  Run: brew update && brew tap homebrew/core"
end
puts ""
