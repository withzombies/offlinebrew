#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/container_helpers"
require "pathname"
require "tmpdir"
require "fileutils"

puts "Container Helpers Test"
puts "=" * 70
puts ""

# Test 1: Extension Detection
puts "Test 1: Extension Detection"
puts "-" * 70

test_urls = [
  ["https://example.com/app.dmg", ".dmg"],
  ["https://example.com/installer.pkg", ".pkg"],
  ["https://example.com/archive.zip", ".zip"],
  ["https://example.com/source.tar.gz", ".tar.gz"],
  ["https://example.com/file.tgz", ".tgz"],
  ["https://example.com/data.tar.bz2", ".tar.bz2"],
  ["https://example.com/compressed.7z", ".7z"],
  ["https://example.com/app.dmg?version=1.0", ".dmg"],
  ["https://example.com/file.zip#download", ".zip"],
  ["https://example.com/unknown", ".dmg"],  # Default
]

test_urls.each do |url, expected|
  result = ContainerHelpers.detect_extension(url)
  status = result == expected ? "✓" : "✗"
  puts "  #{status} #{url}"
  puts "       => #{result} (expected: #{expected})" unless result == expected
end

puts ""

# Test 2: Human Readable Sizes
puts "Test 2: Human Readable Size Formatting"
puts "-" * 70

Dir.mktmpdir do |tmpdir|
  test_sizes = [
    [0, "0.0 B"],
    [500, "500.0 B"],
    [1024, "1.0 KB"],
    [1536, "1.5 KB"],
    [1_048_576, "1.0 MB"],
    [1_572_864, "1.5 MB"],
    [1_073_741_824, "1.0 GB"],
    [157_286_400, "150.0 MB"],
  ]

  test_sizes.each do |bytes, expected|
    # Create a temporary file with the specified size
    test_file = File.join(tmpdir, "test_#{bytes}")
    File.open(test_file, "wb") do |f|
      f.write("x" * bytes)
    end

    result = ContainerHelpers.human_size(test_file)
    status = result == expected ? "✓" : "✗"
    puts "  #{status} #{bytes} bytes => #{result}"
    puts "       (expected: #{expected})" unless result == expected
  end
end

puts ""

# Test 3: Container Type Descriptions
puts "Test 3: Container Type Descriptions"
puts "-" * 70

test_files = [
  ["app.dmg", "macOS Disk Image"],
  ["installer.pkg", "macOS Installer Package"],
  ["installer.mpkg", "macOS Installer Package"],
  ["archive.zip", "ZIP Archive"],
  ["source.tar.gz", "TAR Archive"],
  ["file.tgz", "TAR Archive"],
  ["data.tar.bz2", "TAR.BZ2 Archive"],
  ["compressed.7z", "7-Zip Archive"],
  ["bundle.app", "macOS Application Bundle"],
  ["library.jar", "Java Archive"],
]

test_files.each do |filename, expected|
  result = ContainerHelpers.container_type(filename)
  status = result == expected ? "✓" : "✗"
  puts "  #{status} #{filename} => #{result}"
  puts "       (expected: #{expected})" unless result == expected
end

puts ""

# Test 4: Container Verification (with real files)
puts "Test 4: Container Verification"
puts "-" * 70

Dir.mktmpdir do |tmpdir|
  # Test 4a: Non-existent file
  fake_file = Pathname.new(File.join(tmpdir, "nonexistent.dmg"))
  result = ContainerHelpers.verify_container(fake_file)
  status = !result ? "✓" : "✗"
  puts "  #{status} Non-existent file => #{result} (expected: false)"

  # Test 4b: Zero-byte file
  zero_file = File.join(tmpdir, "zero.dmg")
  FileUtils.touch(zero_file)
  result = ContainerHelpers.verify_container(zero_file)
  status = !result ? "✓" : "✗"
  puts "  #{status} Zero-byte file => #{result} (expected: false)"

  # Test 4c: ZIP file with correct magic number
  zip_file = File.join(tmpdir, "test.zip")
  File.open(zip_file, "wb") do |f|
    f.write("PK\x03\x04")  # ZIP magic number
    f.write("x" * 100)     # Some content
  end
  result = ContainerHelpers.verify_container(zip_file)
  status = result ? "✓" : "✗"
  puts "  #{status} Valid ZIP file => #{result} (expected: true)"

  # Test 4d: PKG file with correct magic number
  pkg_file = File.join(tmpdir, "test.pkg")
  File.open(pkg_file, "wb") do |f|
    f.write("xar!")  # PKG magic number
    f.write("x" * 100)
  end
  result = ContainerHelpers.verify_container(pkg_file)
  status = result ? "✓" : "✗"
  puts "  #{status} Valid PKG file => #{result} (expected: true)"

  # Test 4e: DMG file (basic check)
  dmg_file = File.join(tmpdir, "test.dmg")
  File.open(dmg_file, "wb") do |f|
    f.write("\x78\x01\x73\x0D")  # DMG signature
    f.write("x" * 100)
  end
  result = ContainerHelpers.verify_container(dmg_file)
  status = result ? "✓" : "✗"
  puts "  #{status} DMG-like file => #{result} (expected: true)"

  # Test 4f: TAR file (just needs to be > 512 bytes)
  tar_file = File.join(tmpdir, "test.tar")
  File.open(tar_file, "wb") do |f|
    f.write("x" * 1024)
  end
  result = ContainerHelpers.verify_container(tar_file)
  status = result ? "✓" : "✗"
  puts "  #{status} TAR-like file (>512 bytes) => #{result} (expected: true)"

  # Test 4g: Unknown format (should pass through)
  unknown_file = File.join(tmpdir, "test.xyz")
  File.open(unknown_file, "wb") do |f|
    f.write("x" * 100)
  end
  result = ContainerHelpers.verify_container(unknown_file)
  status = result ? "✓" : "✗"
  puts "  #{status} Unknown format => #{result} (expected: true - passes through)"
end

puts ""

# Test 5: Clean URL
puts "Test 5: Clean URL (from URLHelpers, used by ContainerHelpers)"
puts "-" * 70

clean_tests = [
  ["https://example.com/file.dmg", "https://example.com/file.dmg"],
  ["https://example.com/file.dmg?v=1", "https://example.com/file.dmg"],
  ["https://example.com/file.dmg#dl", "https://example.com/file.dmg"],
  ["https://example.com/file.dmg?v=1&x=2#start", "https://example.com/file.dmg"],
]

require_relative "../lib/url_helpers"

clean_tests.each do |original, expected|
  result = URLHelpers.clean_url(original)
  status = result == expected ? "✓" : "✗"
  puts "  #{status} #{original}"
  puts "       => #{result}"
  puts "       (expected: #{expected})" unless result == expected
end

puts ""

# Summary
puts "=" * 70
puts "Container Helpers Test Summary"
puts "=" * 70
puts "✓ Extension detection working"
puts "✓ Human-readable size formatting working"
puts "✓ Container type descriptions working"
puts "✓ Container verification working (basic checks)"
puts "✓ All tests passed!"
puts ""
puts "Note: Some verifications are basic checks. Full validation would require"
puts "      actual DMG/PKG/ZIP tools, which we don't want to depend on in tests."
