# Task 1.3: Test Modern Homebrew API Compatibility

## Objective

Verify that brew-mirror works with the latest Homebrew API and identify any deprecated methods that need updating.

## Background

The codebase was written around 2019-2020. Homebrew's Ruby API has evolved since then. We need to verify:

1. Formula iteration still works (`Formula.each`)
2. Download strategy classes still exist
3. Methods like `.stable`, `.resources`, `.patches` still work
4. No deprecated warnings appear

**Why this matters:**
- Homebrew changes its internal APIs over time
- Deprecated methods may be removed in future versions
- Better to fix compatibility issues before adding new features

## Prerequisites

- Task 1.1 completed (Dynamic Homebrew Path Detection)
- Task 1.2 completed (Cross-Platform Home Directory)
- Homebrew installed and up-to-date on your system

## Implementation Steps

### Step 1: Update Homebrew

Make sure you have the latest Homebrew:

```bash
brew update
brew --version
```

Note the version for reference.

### Step 2: Create API Compatibility Test Script

Create `mirror/test/test_api_compatibility.rb`:

```ruby
#!/usr/bin/env brew ruby
# frozen_string_literal: true

# Test script to verify Homebrew API compatibility
# Run with: brew ruby mirror/test/test_api_compatibility.rb

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
begin
  # Try new API first
  if Formula.respond_to?(:all)
    formula_count = Formula.all.count
    iterator_method = "Formula.all"
  elsif Formula.respond_to?(:each)
    formula_count = Formula.each.count
    iterator_method = "Formula.each"
  else
    abort "  ✗ No Formula iteration method found (tried .all and .each)"
  end
  puts "  ✓ Formula iteration: #{iterator_method} (#{formula_count} formulae)"
rescue StandardError => e
  puts "  ✗ Formula iteration failed: #{e.message}"
  abort "FATAL: Cannot iterate formulae"
end

# Test 5: Test formula access
puts "  Testing formula access..."
begin
  # Try to load a common formula
  test_formula = Formula["wget"]
  puts "  ✓ Can load formula: wget"

  # Test formula methods
  methods_to_test = {
    stable: "Stable spec",
    full_name: "Full name",
    name: "Name",
    tap: "Tap",
  }

  methods_to_test.each do |method, description|
    if test_formula.respond_to?(method)
      puts "  ✓ Formula##{method} exists (#{description})"
    else
      puts "  ✗ Formula##{method} missing (#{description})"
    end
  end
rescue FormulaUnavailableError => e
  puts "  ⚠ wget not installed, trying different formula..."
  # Try another common formula
  begin
    test_formula = Formula["ruby"]
    puts "  ✓ Can load formula: ruby"
  rescue StandardError => e2
    puts "  ✗ Cannot load any test formula: #{e2.message}"
  end
rescue StandardError => e
  puts "  ✗ Formula access failed: #{e.message}"
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
end
puts ""

# Test 8: Check Resource API
puts "Testing Resource API..."
begin
  if test_formula && test_formula.stable && test_formula.stable.resources.any?
    resource = test_formula.stable.resources.first
    puts "  ✓ Resources available: #{test_formula.stable.resources.count}"
    puts "  ✓ Resource class: #{resource.last.class}"

    # Test resource methods
    res_methods = [:url, :checksum, :downloader]
    res_methods.each do |method|
      if resource.last.respond_to?(method)
        puts "  ✓ Resource##{method} exists"
      else
        puts "  ✗ Resource##{method} missing"
      end
    end
  else
    puts "  ⚠ Test formula has no resources, trying python..."
    # Python usually has resources
    begin
      python_formula = Formula["python"]
      if python_formula.stable.resources.any?
        puts "  ✓ Resources found in python formula"
      else
        puts "  ⚠ No resources found for testing"
      end
    rescue StandardError
      puts "  ⚠ Could not test resources"
    end
  end
rescue StandardError => e
  puts "  ✗ Resource test failed: #{e.message}"
end
puts ""

# Test 9: Check Patch API
puts "Testing Patch API..."
begin
  # Need to find a formula with patches
  puts "  Looking for formula with patches..."
  formula_with_patches = nil

  # Check a few common formulae that often have patches
  ["vim", "git", "openssl"].each do |name|
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
    patch = formula_with_patches.stable.patches.first
    puts "  ✓ Found patches in: #{formula_with_patches.name}"
    puts "  ✓ Patch class: #{patch.class}"

    if patch.respond_to?(:external?)
      puts "  ✓ Patch#external? exists"
      if patch.external?
        puts "  ✓ External patch detected"
        puts "    - URL: #{patch.url}" if patch.respond_to?(:url)
        puts "    - Resource: #{patch.resource.class}" if patch.respond_to?(:resource)
      end
    else
      puts "  ✗ Patch#external? missing"
    end
  else
    puts "  ⚠ No formula with patches found for testing"
  end
rescue StandardError => e
  puts "  ✗ Patch test failed: #{e.message}"
end
puts ""

# Test 10: Check Tap API
puts "Testing Tap API..."
begin
  if test_formula && test_formula.respond_to?(:tap)
    tap = test_formula.tap
    puts "  ✓ Formula#tap exists"
    puts "  ✓ Tap class: #{tap.class}"

    if tap.respond_to?(:core_tap?)
      puts "  ✓ Tap#core_tap? exists: #{tap.core_tap?}"
    else
      puts "  ✗ Tap#core_tap? missing"
    end
  else
    puts "  ✗ Formula#tap missing"
  end
rescue StandardError => e
  puts "  ✗ Tap test failed: #{e.message}"
end
puts ""

# Summary
puts "=" * 70
puts "Summary:"
puts "  Available download strategies: #{available_strategies.count}/#{download_strategies.count}"
puts "  Formula iteration: #{iterator_method}"
puts ""

if available_strategies.count >= 5
  puts "✓ All core APIs are compatible!"
  puts "  brew-mirror should work with this Homebrew version."
else
  puts "⚠ Some compatibility issues detected"
  puts "  Review the output above and update BREW_OFFLINE_DOWNLOAD_STRATEGIES"
end
```

### Step 3: Run the Compatibility Test

```bash
mkdir -p mirror/test
chmod +x mirror/test/test_api_compatibility.rb
brew ruby mirror/test/test_api_compatibility.rb
```

**Review the output carefully.**

### Step 4: Fix Any Compatibility Issues

Based on the test output, you may need to make changes:

#### Issue A: Formula.each is deprecated

If the test shows `Formula.all` is preferred:

**In `mirror/bin/brew-mirror`, find (around line 71):**

```ruby
options = {
  directory: "/Users/william/tmp/brew-mirror",
  baseurl: "http://localhost:8000",
  sleep: 0.5,
  config_only: false,
  iterator: Formula,
}
```

**And later (around line 121):**

```ruby
options[:iterator].each do |formula|
```

**Change to:**

```ruby
# Around line 71
options = {
  directory: "/Users/william/tmp/brew-mirror",
  baseurl: "http://localhost:8000",
  sleep: 0.5,
  config_only: false,
  iterator: nil,  # Will be set based on CLI args
}

# Around line 89 (in the --formulae option handler)
parser.on "-f", "--formulae f1,f2,f2", Array, "mirror just the given formulae" do |formulae|
  options[:iterator] = formulae.map { |f| Formula[f] }
end

# After the parser (around line 92), add:
# Set default iterator if not specified via --formulae
options[:iterator] ||= Formula.all

# Around line 121 - this stays the same
options[:iterator].each do |formula|
```

**Why:**
- `Formula.all` is the modern way to get all formulae
- `Formula` by itself might be deprecated as an iterator
- Still supports `--formulae` option for specific formulas

#### Issue B: Download strategies changed

If any download strategies are missing from the test output:

**In `mirror/bin/brew-mirror`, find (around line 23-31):**

```ruby
BREW_OFFLINE_DOWNLOAD_STRATEGIES = [
  CurlDownloadStrategy,
  CurlApacheMirrorDownloadStrategy,
  NoUnzipCurlDownloadStrategy,
  # NOTE: These don't have a stable checksum, so we fabricate an identifier for them.
  # See `sensible_identifier`.
  GitDownloadStrategy,
  GitHubGitDownloadStrategy,
].freeze
```

**Update based on test output:**

```ruby
# Only include strategies that exist in your Homebrew version
BREW_OFFLINE_DOWNLOAD_STRATEGIES = [
  CurlDownloadStrategy,
  CurlApacheMirrorDownloadStrategy,
  NoUnzipCurlDownloadStrategy,
  GitDownloadStrategy,
  GitHubGitDownloadStrategy,
  # Add any new strategies found by the test:
  # GitLabDownloadStrategy,  # Uncomment if test shows it exists
  # FossilDownloadStrategy,  # Uncomment if test shows it exists
].compact.freeze  # compact removes nils if any class doesn't exist
```

### Step 5: Test brew-mirror with Real Formulae

Run brew-mirror on a small set of formulae to verify it works:

```bash
mkdir -p /tmp/test-mirror
brew ruby mirror/bin/brew-mirror \
  -d /tmp/test-mirror \
  -f wget,curl,jq \
  -s 1
```

**Expected output:**
- No deprecation warnings
- Successfully collects resources
- Downloads complete
- Creates config.json and urlmap.json

**Check the results:**

```bash
ls -lh /tmp/test-mirror/
cat /tmp/test-mirror/config.json
```

### Step 6: Document Any API Changes

Create `mirror/docs/API_CHANGES.md`:

```markdown
# Homebrew API Changes

This document tracks Homebrew API changes that affect offlinebrew.

## Homebrew 4.x Changes (2024-2025)

### Formula Iteration
- **Old:** `Formula.each`
- **New:** `Formula.all`
- **Status:** Changed in brew-mirror to use `Formula.all`

### Download Strategies
- **Supported:** CurlDownloadStrategy, CurlApacheMirrorDownloadStrategy, NoUnzipCurlDownloadStrategy, GitDownloadStrategy, GitHubGitDownloadStrategy
- **Unsupported:** SubversionDownloadStrategy (SVN repos not mirrored)

### Other Changes
(Document any other changes you discovered during testing)

## Testing

To verify API compatibility:
```bash
brew ruby mirror/test/test_api_compatibility.rb
```

Last tested: [DATE] with Homebrew [VERSION]
```

Fill in the date and version from your testing.

## Testing

### Test 1: Compatibility Test Passes

The test script from Step 2 should show mostly ✓ marks:

```bash
brew ruby mirror/test/test_api_compatibility.rb
```

### Test 2: Mirror Small Formula Set

```bash
rm -rf /tmp/test-mirror
mkdir /tmp/test-mirror
brew ruby mirror/bin/brew-mirror -d /tmp/test-mirror -f wget,jq -s 1
```

**Expected:**
- No errors
- No deprecation warnings
- Files downloaded to /tmp/test-mirror/
- config.json and urlmap.json created

### Test 3: Verify Downloaded Files

```bash
ls -lh /tmp/test-mirror/
wc -l /tmp/test-mirror/urlmap.json
cat /tmp/test-mirror/config.json
```

**Expected:**
- Multiple .tar.gz or .git files
- urlmap.json has multiple entries
- config.json has valid commit hash

### Test 4: Check for Deprecation Warnings

```bash
brew ruby mirror/bin/brew-mirror -d /tmp/test-mirror -f curl -s 1 2>&1 | grep -i deprecat
```

**Expected:**
```
(no output)
```

If you see deprecation warnings, investigate and fix them.

## Acceptance Criteria

✅ You're done when:

1. Compatibility test script runs without errors
2. No deprecation warnings appear
3. brew-mirror can download at least 5 test formulae
4. All download strategies in use are confirmed to exist
5. Formula iteration works with modern API
6. API_CHANGES.md documents any changes made
7. Tests pass on your Homebrew version

## Troubleshooting

### Issue: "Formula class not found"

**Solution:**
You're not running under `brew ruby`. Must use:

```bash
brew ruby mirror/test/test_api_compatibility.rb
```

Not:

```bash
ruby mirror/test/test_api_compatibility.rb  # Wrong!
```

### Issue: "FormulaUnavailableError: No available formula with the name 'wget'"

**Solution:**
Install test formulae:

```bash
brew install wget jq curl
```

Or modify the test script to use formulae you already have installed.

### Issue: Many download strategies missing

**Solution:**
Update Homebrew first:

```bash
brew update
brew --version
```

If still missing, those strategies may have been removed. Update `BREW_OFFLINE_DOWNLOAD_STRATEGIES` to only include available ones.

### Issue: "No such file or directory @ rb_sysopen - config.json"

**Solution:**
This is expected if testing without a full mirror. The test is checking if brew-mirror can write files, not read them.

## Commit Message

When done:

```bash
git add mirror/test/test_api_compatibility.rb mirror/bin/brew-mirror mirror/docs/API_CHANGES.md
git commit -m "Task 1.3: Verify and update Homebrew API compatibility

- Create API compatibility test script
- Update Formula iteration to use Formula.all
- Verify all download strategies still exist
- Document API changes in API_CHANGES.md
- Test with modern Homebrew version
- Remove deprecation warnings"
```

## Next Steps

Proceed to **Task 2.1: Add Homebrew-Cask Tap Mirroring** (Phase 2 begins!)
