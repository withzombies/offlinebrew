#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/url_helpers"

puts "URL Helpers Test"
puts "=" * 60
puts ""

# Test 1: URL Normalization
puts "Test 1: URL Normalization"
puts "-" * 60

test_cases = [
  "https://example.com/file.dmg",
  "https://example.com/file.dmg?version=1.0",
  "https://example.com/file.dmg#anchor",
  "https://example.com/file.dmg?v=1&arch=x64",
  "https://example.com/path/",
  "https://example.com/file.dmg?download=true#start",
]

test_cases.each do |url|
  puts "\nURL: #{url}"
  variants = URLHelpers.normalize_for_matching(url)
  puts "  Variants (#{variants.length}):"
  variants.each do |variant|
    puts "    - #{variant}"
  end
end

puts "\n"
puts "=" * 60
puts ""

# Test 2: URL Matching
puts "Test 2: URL Matching in urlmap"
puts "-" * 60
puts ""

# Create a test urlmap
urlmap = {
  "https://example.com/file.dmg" => "abc123.dmg",
  "https://example.com/other.zip" => "def456.zip",
  "https://example.com/app.pkg" => "789xyz.pkg",
}

puts "urlmap contents:"
urlmap.each do |url, file|
  puts "  #{url} => #{file}"
end
puts ""

# Test URLs that should match
test_urls = [
  {
    url: "https://example.com/file.dmg",
    expected: "abc123.dmg",
    description: "Exact match",
  },
  {
    url: "https://example.com/file.dmg?version=1.0",
    expected: "abc123.dmg",
    description: "With query parameter",
  },
  {
    url: "https://example.com/file.dmg#download",
    expected: "abc123.dmg",
    description: "With fragment",
  },
  {
    url: "https://example.com/file.dmg?v=1.0&arch=x64#start",
    expected: "abc123.dmg",
    description: "With both query and fragment",
  },
  {
    url: "https://example.com/missing.dmg",
    expected: nil,
    description: "Not in urlmap",
  },
]

puts "Test cases:"
test_urls.each do |test|
  result = URLHelpers.find_in_urlmap(test[:url], urlmap)
  success = result == test[:expected]
  status = success ? "✓" : "✗"

  puts "  #{status} #{test[:description]}"
  puts "    URL: #{test[:url]}"
  puts "    Expected: #{test[:expected] || "nil"}"
  puts "    Got: #{result || "nil"}"
  puts "" unless success
end

puts ""
puts "=" * 60
puts ""

# Test 3: URL Cleaning
puts "Test 3: URL Cleaning"
puts "-" * 60
puts ""

clean_test_cases = [
  ["https://example.com/file.dmg", "https://example.com/file.dmg"],
  ["https://example.com/file.dmg?v=1.0", "https://example.com/file.dmg"],
  ["https://example.com/file.dmg#anchor", "https://example.com/file.dmg"],
  ["https://example.com/file.dmg?v=1&x=2#end", "https://example.com/file.dmg"],
]

clean_test_cases.each do |original, expected|
  result = URLHelpers.clean_url(original)
  success = result == expected
  status = success ? "✓" : "✗"

  puts "  #{status} #{original}"
  puts "       => #{result}"
  puts "" unless success
end

puts ""
puts "=" * 60
puts ""

# Test 4: URL Equivalence
puts "Test 4: URL Equivalence"
puts "-" * 60
puts ""

equiv_test_cases = [
  ["https://example.com/file.dmg", "https://example.com/file.dmg", true],
  ["https://example.com/file.dmg?v=1", "https://example.com/file.dmg", true],
  ["https://example.com/file.dmg", "https://example.com/file.dmg#anchor", true],
  ["https://example.com/file.dmg", "https://example.com/other.dmg", false],
]

equiv_test_cases.each do |url1, url2, expected|
  result = URLHelpers.equivalent?(url1, url2)
  success = result == expected
  status = success ? "✓" : "✗"

  puts "  #{status} #{url1}"
  puts "       vs #{url2}"
  puts "       => #{result ? "equivalent" : "different"} (expected: #{expected ? "equivalent" : "different"})"
  puts "" unless success
end

puts ""
puts "=" * 60
puts "All tests complete!"
puts "=" * 60
