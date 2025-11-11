# Task 2.1: Add Homebrew-Cask Tap Mirroring

## Objective

Extend brew-mirror to mirror the `homebrew/homebrew-cask` tap alongside `homebrew/homebrew-core`, enabling offline cask installations.

## Background

Currently, brew-mirror only mirrors formulae from `homebrew/homebrew-core`. Casks (GUI applications, fonts, etc.) are stored in `homebrew/homebrew-cask` and need to be mirrored separately.

**Key differences between formulae and casks:**
- **Formulae**: Source code that's compiled (or bottles = pre-compiled binaries)
- **Casks**: Pre-built applications (DMG, PKG, ZIP files)
- **Formulae tap**: `homebrew/homebrew-core`
- **Casks tap**: `homebrew/homebrew-cask`

**Why this matters:**
- Users want to install GUI apps offline (Firefox, Chrome, VSCode, etc.)
- Casks are completely separate from formulae
- Need to track separate commit hash for cask tap

## Prerequisites

- Task 1.1 completed (Dynamic Homebrew Path Detection)
- Task 1.2 completed (Cross-Platform Home Directory)
- Task 1.3 completed (API Compatibility Testing)
- Homebrew-cask tap installed: `brew tap homebrew/cask`

## Implementation Steps

### Step 1: Verify Cask Tap Exists

Check if the cask tap is installed:

```bash
ls -la $(brew --repository)/Library/Taps/homebrew/homebrew-cask
brew tap | grep cask
```

If not installed:

```bash
brew tap homebrew/cask
```

### Step 2: Add Cask Support to HomebrewPaths Module

Edit `mirror/lib/homebrew_paths.rb`:

**Add this method to the `HomebrewPaths` module (after the `cask_tap_path` method):**

```ruby
  # Verify a tap exists
  # Args:
  #   tap_path: String path to tap directory
  # Returns: Boolean
  def self.tap_exists?(tap_path)
    Dir.exist?(tap_path) && Dir.exist?(File.join(tap_path, ".git"))
  end

  # Get commit hash for a tap
  # Args:
  #   tap_path: String path to tap directory
  # Returns: String commit hash
  def self.tap_commit(tap_path)
    abort "Tap not found: #{tap_path}" unless tap_exists?(tap_path)

    Dir.chdir tap_path do
      `git rev-parse HEAD`.chomp
    end
  end
```

### Step 3: Update brew-mirror Configuration Structure

Edit `mirror/bin/brew-mirror`:

**Find the config generation section (around line 98-114):**

```ruby
ohai "Writing brew-offline config..."

config = {}

commit = begin
  core_dir = HomebrewPaths.core_tap_path
  abort "Fatal: homebrew-core tap not found at #{core_dir}" unless Dir.exist?(core_dir)

  Dir.chdir core_dir do
    `git rev-parse HEAD`.chomp
  end
end

config[:commit] = commit
config[:stamp] = Time.now.to_i.to_s
config[:cache] = options[:directory]
config[:baseurl] = options[:baseurl]

File.write File.join(options[:directory], "config.json"), config.to_json
```

**Replace with:**

```ruby
ohai "Writing brew-offline config..."

config = {}

# Get commit hash for homebrew-core
core_dir = HomebrewPaths.core_tap_path
abort "Fatal: homebrew-core tap not found at #{core_dir}" unless HomebrewPaths.tap_exists?(core_dir)
core_commit = HomebrewPaths.tap_commit(core_dir)

# Get commit hash for homebrew-cask (if it exists)
cask_dir = HomebrewPaths.cask_tap_path
cask_commit = if HomebrewPaths.tap_exists?(cask_dir)
                HomebrewPaths.tap_commit(cask_dir)
              else
                opoo "homebrew-cask tap not found, skipping cask mirroring"
                nil
              end

# Store tap information
config[:taps] = {
  "homebrew/homebrew-core" => {
    "commit" => core_commit,
    "type" => "formula",
  },
}

if cask_commit
  config[:taps]["homebrew/homebrew-cask"] = {
    "commit" => cask_commit,
    "type" => "cask",
  }
end

# Legacy fields for backward compatibility
config[:commit] = core_commit  # Old format
config[:stamp] = Time.now.to_i.to_s
config[:cache] = options[:directory]
config[:baseurl] = options[:baseurl]

File.write File.join(options[:directory], "config.json"), config.to_json
```

**What changed:**
- Config now has a `taps` hash with commit for each tap
- Supports both `homebrew-core` and `homebrew-cask`
- Keeps legacy `commit` field for backward compatibility
- Gracefully handles missing cask tap

### Step 4: Add Cask Iteration Logic

Edit `mirror/bin/brew-mirror`:

**After the `require` statements at the top, add:**

```ruby
require "cask/cask_loader"
require "cask/cask"
```

**Find the formula iteration section (around line 121):**

```ruby
exit if options[:config_only]

urlmap = {}

# Finally, fetch the (stable) resources for each formula in homebrew-core.
options[:iterator].each do |formula|
```

**After the entire formula loop (after `sleep options[:sleep]` and before the urlmap write), add:**

```ruby
# Mirror casks if homebrew-cask tap exists
if HomebrewPaths.tap_exists?(HomebrewPaths.cask_tap_path)
  ohai "Mirroring casks from homebrew/homebrew-cask..."

  # Determine which casks to mirror
  cask_iterator = if options[:casks]
                    # Specific casks requested via CLI
                    options[:casks].map { |c| Cask::CaskLoader.load(c) }
                  else
                    # All casks
                    Cask::Cask.all
                  end

  cask_iterator.each do |cask|
    ohai "Collecting resources for cask: #{cask.token}..."

    # Casks have a simpler structure than formulae
    # They typically have one URL that points to the application bundle
    begin
      url = cask.url
      next unless url  # Some casks may not have URLs (e.g., extract_only)

      url_str = url.to_s
      ohai "\tCask URL: #{url_str}"

      # Determine download strategy
      # Casks typically use CurlDownloadStrategy
      downloader = url.downloader

      unless BREW_OFFLINE_DOWNLOAD_STRATEGIES.include?(downloader.class)
        opoo "#{cask.token} uses unsupported download strategy: #{downloader.class}"
        next
      end

      # Create a sensible identifier (casks usually have checksums)
      checksum = cask.sha256
      identifier = if checksum && checksum != :no_check
                     checksum.to_s
                   else
                     # No checksum, use URL-based hash
                     require "digest"
                     Digest::SHA256.hexdigest(url_str)
                   end

      # Download location
      downloader.shutup!
      old_location = downloader.cached_location
      new_location = Pathname.new(File.join(options[:directory],
                                            "#{identifier}#{old_location.extname}"))

      # Download if not already present
      downloader.fetch unless new_location.exist?

      if new_location.exist?
        ohai "\tAlready mirrored!"
      else
        FileUtils.mv old_location.to_s, new_location.to_s, force: true
        ohai "\t#{old_location} -> #{new_location}"
      end

      # Add to urlmap
      urlmap[url_str] = new_location.basename.to_s

    rescue StandardError => e
      opoo "Failed to mirror cask #{cask.token}: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      next
    end

    sleep options[:sleep]
  end
else
  ohai "Skipping cask mirroring (homebrew-cask tap not found)"
end

# Write urlmap.json
File.write File.join(options[:directory], "urlmap.json"), urlmap.to_json
```

### Step 5: Add CLI Option for Specific Casks

Edit `mirror/bin/brew-mirror`:

**In the options hash (around line 66-72):**

```ruby
options = {
  directory: "/Users/william/tmp/brew-mirror",
  baseurl: "http://localhost:8000",
  sleep: 0.5,
  config_only: false,
  iterator: nil,
}
```

**Add:**

```ruby
options = {
  directory: "/Users/william/tmp/brew-mirror",
  baseurl: "http://localhost:8000",
  sleep: 0.5,
  config_only: false,
  iterator: nil,
  casks: nil,  # Add this line
}
```

**In the OptionParser section (around line 89), add:**

```ruby
  parser.on "-f", "--formulae f1,f2,f3", Array, "mirror just the given formulae" do |formulae|
    options[:iterator] = formulae.map { |f| Formula[f] }
  end

  # Add this new option:
  parser.on "--casks c1,c2,c3", Array, "mirror just the given casks" do |casks|
    options[:casks] = casks
  end
```

### Step 6: Handle Cask API Differences

Casks have a different API than formulae. Add error handling:

**Create `mirror/lib/cask_helpers.rb`:**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# CaskHelpers: Utilities for working with Homebrew casks
module CaskHelpers
  # Safely get all casks, handling API differences
  def self.all_casks
    begin
      # Try modern API first
      if defined?(Cask::Cask) && Cask::Cask.respond_to?(:all)
        return Cask::Cask.all
      end

      # Try alternative methods
      if defined?(Cask) && Cask.respond_to?(:to_a)
        return Cask.to_a
      end

      # Last resort: iterate tap directory
      cask_dir = File.join(HomebrewPaths.cask_tap_path, "Casks")
      return [] unless Dir.exist?(cask_dir)

      Dir.glob("#{cask_dir}/*.rb").map do |path|
        token = File.basename(path, ".rb")
        Cask::CaskLoader.load(token)
      end
    rescue StandardError => e
      warn "Error loading casks: #{e.message}"
      []
    end
  end

  # Check if cask API is available
  def self.cask_api_available?
    defined?(Cask::Cask) && defined?(Cask::CaskLoader)
  end
end
```

**Then update brew-mirror to use it:**

```ruby
require_relative "../lib/cask_helpers"

# In the cask iteration section, change:
cask_iterator = if options[:casks]
                  options[:casks].map { |c| Cask::CaskLoader.load(c) }
                else
                  CaskHelpers.all_casks
                end
```

## Testing

### Test 1: Verify Cask API Works

Create `mirror/test/test_cask_api.rb`:

```ruby
#!/usr/bin/env brew ruby
# frozen_string_literal: true

require_relative "../lib/homebrew_paths"
require_relative "../lib/cask_helpers"
require "cask/cask_loader"
require "cask/cask"

puts "Cask API Test"
puts "=" * 50

puts "Cask tap path: #{HomebrewPaths.cask_tap_path}"
puts "Tap exists: #{HomebrewPaths.tap_exists?(HomebrewPaths.cask_tap_path)}"
puts ""

if CaskHelpers.cask_api_available?
  puts "✓ Cask API available"

  # Test loading a specific cask
  begin
    test_cask = Cask::CaskLoader.load("firefox")
    puts "✓ Can load cask: firefox"
    puts "  Token: #{test_cask.token}"
    puts "  Name: #{test_cask.name.first}"
    puts "  URL: #{test_cask.url}"
    puts "  SHA256: #{test_cask.sha256}"
  rescue StandardError => e
    puts "✗ Cannot load firefox: #{e.message}"
  end

  # Test getting all casks
  all_casks = CaskHelpers.all_casks
  puts ""
  puts "Total casks available: #{all_casks.count}"
  puts "First 5 casks:"
  all_casks.first(5).each do |cask|
    puts "  - #{cask.token}"
  end
else
  puts "✗ Cask API not available"
end
```

Run it:

```bash
chmod +x mirror/test/test_cask_api.rb
brew ruby mirror/test/test_cask_api.rb
```

**Expected output:**
```
Cask API Test
==================================================
Cask tap path: /opt/homebrew/Homebrew/Library/Taps/homebrew/homebrew-cask
Tap exists: true

✓ Cask API available
✓ Can load cask: firefox
  Token: firefox
  Name: Firefox
  URL: https://download-installer.cdn.mozilla.net/...
  SHA256: abc123...

Total casks available: 4523
First 5 casks:
  - 1password
  - 4k-video-downloader
  - ...
```

### Test 2: Mirror a Single Cask

```bash
mkdir -p /tmp/test-cask-mirror
brew ruby mirror/bin/brew-mirror \
  -d /tmp/test-cask-mirror \
  --casks firefox \
  -f wget \
  -s 1
```

**Expected:**
- Downloads Firefox DMG
- Downloads wget source
- Creates config.json with both taps
- Creates urlmap.json with both formula and cask URLs

**Verify:**

```bash
ls -lh /tmp/test-cask-mirror/
cat /tmp/test-cask-mirror/config.json | jq .
```

Should show:
```json
{
  "taps": {
    "homebrew/homebrew-core": {
      "commit": "abc123...",
      "type": "formula"
    },
    "homebrew/homebrew-cask": {
      "commit": "def456...",
      "type": "cask"
    }
  },
  "commit": "abc123...",
  "stamp": "1699999999",
  "cache": "/tmp/test-cask-mirror",
  "baseurl": "http://localhost:8000"
}
```

### Test 3: Check File Sizes

Cask files are typically large (50MB - 500MB):

```bash
du -sh /tmp/test-cask-mirror/*.dmg
```

**Expected:**
```
150M    /tmp/test-cask-mirror/abc123def.dmg
```

## Acceptance Criteria

✅ You're done when:

1. Config.json includes `taps` hash with both homebrew-core and homebrew-cask
2. Can mirror at least one cask (e.g., firefox)
3. Cask files are downloaded to mirror directory
4. urlmap.json includes both formula and cask URLs
5. No errors when cask tap is missing (graceful fallback)
6. Test scripts pass
7. CLI option `--casks` works for specific casks

## Troubleshooting

### Issue: "uninitialized constant Cask"

**Solution:**
Add require statements:

```ruby
require "cask/cask_loader"
require "cask/cask"
```

### Issue: "No cask with this name exists"

**Solution:**
Check available casks:

```bash
brew search --cask firefox
```

Use exact token name.

### Issue: Cask download fails with SSL error

**Solution:**
Some cask URLs may have SSL issues. Test with a different cask:

```bash
brew ruby mirror/bin/brew-mirror -d /tmp/test --casks google-chrome -s 1
```

### Issue: "SHA256 mismatch"

**Solution:**
The cask may have been updated. Update the cask tap:

```bash
brew update
```

Then retry.

## Commit Message

When done:

```bash
git add mirror/bin/brew-mirror mirror/lib/homebrew_paths.rb mirror/lib/cask_helpers.rb mirror/test/test_cask_api.rb
git commit -m "Task 2.1: Add homebrew-cask tap mirroring support

- Update config format to include taps hash
- Add cask iteration and download logic
- Create CaskHelpers module for cask API
- Add --casks CLI option for specific casks
- Mirror both formulae and casks in single run
- Track separate commits for core and cask taps
- Maintain backward compatibility with old config format"
```

## Next Steps

Proceed to **Task 2.2: Implement Cask Download Logic** (refinements and edge cases)
