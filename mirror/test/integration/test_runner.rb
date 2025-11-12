#!/usr/bin/env ruby
# frozen_string_literal: true

# Integration Test Runner
#
# Runs all integration tests in order with proper reporting.
#
# Usage:
#   ruby test_runner.rb
#   ruby test_runner.rb --verbose

require "minitest/autorun"

# Load test helper
require_relative "../test_helper"

# Determine which tests to run
test_files = Dir.glob(File.join(__dir__, "test_*.rb")).reject { |f| f.end_with?("test_runner.rb") }

puts "=" * 80
puts "Offlinebrew Integration Test Suite"
puts "=" * 80
puts ""
puts "Loading #{test_files.count} test files..."
puts ""

test_files.sort.each do |test_file|
  puts "  - #{File.basename(test_file)}"
  require test_file
end

puts ""
puts "=" * 80
puts "Starting Tests"
puts "=" * 80
