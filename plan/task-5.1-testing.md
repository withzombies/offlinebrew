# Task 5.1: Create Test Scripts

## Objective

Create comprehensive test suite to verify all functionality works correctly.

## Prerequisites

- All previous tasks completed

## Implementation Steps

### Step 1: Create Test Framework

Create `mirror/test/test_runner.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test framework
class TestRunner
  attr_reader :tests, :passed, :failed

  def initialize
    @tests = []
    @passed = []
    @failed = []
  end

  def test(name, &block)
    @tests << { name: name, block: block }
  end

  def run_all
    puts "Running #{tests.count} tests..."
    puts "=" * 60

    tests.each do |test|
      print "#{test[:name]}... "
      begin
        test[:block].call
        puts "✓ PASS"
        @passed << test[:name]
      rescue StandardError => e
        puts "✗ FAIL"
        puts "  Error: #{e.message}"
        puts "  #{e.backtrace.first(3).join("\n  ")}"
        @failed << test[:name]
      end
    end

    print_summary
    failed.empty?
  end

  def print_summary
    puts "\n" + "=" * 60
    puts "Test Summary"
    puts "=" * 60
    puts "Passed: #{passed.count}/#{tests.count}"
    puts "Failed: #{failed.count}/#{tests.count}"

    if failed.any?
      puts "\nFailed tests:"
      failed.each { |name| puts "  ✗ #{name}" }
    end
  end
end
```

### Step 2: Create Integration Tests

Create `mirror/test/integration_test.rb`:

```ruby
#!/usr/bin/env brew ruby
# frozen_string_literal: true

require_relative "test_runner"
require_relative "../lib/homebrew_paths"
require_relative "../lib/tap_manager"
require "fileutils"
require "json"

TEST_DIR = "/tmp/offlinebrew-test-#{Time.now.to_i}"

def cleanup_test_dir
  FileUtils.rm_rf(TEST_DIR) if Dir.exist?(TEST_DIR)
end

# Setup
FileUtils.mkdir_p(TEST_DIR)
at_exit { cleanup_test_dir }

runner = TestRunner.new

# Test 1: Path detection
runner.test "Homebrew path detection works" do
  prefix = HomebrewPaths.homebrew_prefix
  raise "Empty prefix" if prefix.empty?
  raise "Prefix doesn't exist" unless Dir.exist?(prefix)
end

# Test 2: Tap detection
runner.test "Core tap detected" do
  core = HomebrewPaths.core_tap_path
  raise "Core tap not found" unless Dir.exist?(core)
end

# Test 3: Mirror small formula
runner.test "Mirror single formula" do
  mirror_dir = File.join(TEST_DIR, "mirror1")
  FileUtils.mkdir_p(mirror_dir)

  system("brew", "ruby", File.expand_path("../bin/brew-mirror", __dir__),
         "-d", mirror_dir,
         "-f", "jq",
         "-s", "0.5",
         out: "/dev/null", err: "/dev/null")

  raise "Mirror failed" unless $?.success?
  raise "Config not created" unless File.exist?(File.join(mirror_dir, "config.json"))
  raise "Urlmap not created" unless File.exist?(File.join(mirror_dir, "urlmap.json"))
end

# Test 4: Mirror includes cask
runner.test "Mirror cask" do
  next unless HomebrewPaths.tap_exists?(HomebrewPaths.cask_tap_path)

  mirror_dir = File.join(TEST_DIR, "mirror2")
  FileUtils.mkdir_p(mirror_dir)

  system("brew", "ruby", File.expand_path("../bin/brew-mirror", __dir__),
         "-d", mirror_dir,
         "--casks", "hex-fiend",  # Small cask
         "-s", "1",
         out: "/dev/null", err: "/dev/null")

  raise "Cask mirror failed" unless $?.success?

  config = JSON.parse(File.read(File.join(mirror_dir, "config.json")))
  raise "No cask tap in config" unless config["taps"]["homebrew/homebrew-cask"]
end

# Test 5: Verification works
runner.test "Mirror verification" do
  mirror_dir = File.join(TEST_DIR, "mirror1")
  next unless Dir.exist?(mirror_dir)

  result = system("brew", "ruby", File.expand_path("../bin/brew-mirror-verify", __dir__),
                  mirror_dir,
                  out: "/dev/null", err: "/dev/null")

  raise "Verification failed" unless result
end

# Test 6: URL helpers
runner.test "URL normalization" do
  require_relative "../lib/url_helpers"

  variants = URLHelpers.normalize_for_matching("https://example.com/file.zip?v=1")
  raise "No variants generated" if variants.empty?
  raise "Should include base URL" unless variants.include?("https://example.com/file.zip")
end

# Run all tests
exit(runner.run_all ? 0 : 1)
```

### Step 3: Create Unit Tests

Create `mirror/test/unit_test.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_runner"
require_relative "../lib/url_helpers"
require_relative "../lib/container_helpers"
require_relative "../lib/offlinebrew_config"

runner = TestRunner.new

# URL Helper tests
runner.test "URL normalization handles query params" do
  url = "https://example.com/file.dmg?version=1.0"
  variants = URLHelpers.normalize_for_matching(url)
  raise "Missing base URL" unless variants.include?("https://example.com/file.dmg")
end

runner.test "URL normalization handles fragments" do
  url = "https://example.com/file.dmg#download"
  variants = URLHelpers.normalize_for_matching(url)
  raise "Missing base URL" unless variants.include?("https://example.com/file.dmg")
end

# Container Helper tests
runner.test "Container extension detection" do
  ext = ContainerHelpers.detect_extension("https://example.com/app.dmg")
  raise "Wrong extension: #{ext}" unless ext == ".dmg"
end

runner.test "Human size formatting" do
  require "tempfile"
  file = Tempfile.new("test")
  file.write("x" * 1024 * 1024)  # 1 MB
  file.close

  size = ContainerHelpers.human_size(Pathname.new(file.path))
  raise "Wrong size: #{size}" unless size.include?("MB")

  file.unlink
end

# Config tests
runner.test "Home directory detection" do
  home = OfflinebrewConfig.real_home_directory
  raise "Empty home" if home.empty?
  raise "Home doesn't exist" unless Dir.exist?(home)
end

exit(runner.run_all ? 0 : 1)
```

### Step 4: Create Test Script

Create `mirror/test/run_tests.sh`:

```bash
#!/bin/bash
set -e

echo "Running Offlinebrew Test Suite"
echo "=============================="
echo ""

echo "1. Unit Tests"
echo "-------------"
ruby mirror/test/unit_test.rb
echo ""

echo "2. Integration Tests"
echo "-------------------"
brew ruby mirror/test/integration_test.rb
echo ""

echo "=============================="
echo "All tests passed!"
```

Make executable:
```bash
chmod +x mirror/test/run_tests.sh
```

## Testing

Run the tests:

```bash
./mirror/test/run_tests.sh
```

**Expected:** All tests pass

## Acceptance Criteria

✅ Done when:
1. Unit tests cover all helper modules
2. Integration tests cover end-to-end workflows
3. Test runner framework works
4. All tests pass
5. Easy to add new tests

## Commit Message

```bash
git add mirror/test/
git commit -m "Task 5.1: Add comprehensive test suite

- Create test framework (test_runner.rb)
- Add unit tests for helper modules
- Add integration tests for mirror/install workflows
- Create run_tests.sh script
- Test all major functionality
- Document how to add new tests"
```

## Next Steps

Proceed to **Task 5.2: Update Documentation**
