# Task 1.1: Dynamic Homebrew Path Detection

## Objective

Replace hardcoded Homebrew paths with dynamic detection to support both Intel Macs (`/usr/local/Homebrew`) and Apple Silicon Macs (`/opt/homebrew`).

## Background

Currently, offlinebrew hardcodes the Homebrew installation path as `/usr/local/Homebrew`. This works on Intel Macs but fails on Apple Silicon Macs where Homebrew installs to `/opt/homebrew`.

**Current code locations:**
- `mirror/bin/brew-mirror` line 103: Uses `HOMEBREW_LIBRARY` constant
- `mirror/bin/brew-offline-install` line 8: Hardcoded `CORE_TAP_DIR`

**Why this matters:**
- Apple Silicon Macs are now the standard
- Linux users may have Homebrew in different locations
- Makes the codebase more maintainable

## Prerequisites

- None (this is the first task)

## Implementation Steps

### Step 1: Create a Helper Module

Create a new file `mirror/lib/homebrew_paths.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# HomebrewPaths: Utility module for detecting Homebrew installation paths
# across different platforms and architectures.
module HomebrewPaths
  # Detect the Homebrew prefix (installation root)
  # Returns: String path to Homebrew prefix
  def self.homebrew_prefix
    # First, try to use Homebrew's own environment variable
    return ENV["HOMEBREW_PREFIX"] if ENV["HOMEBREW_PREFIX"] && !ENV["HOMEBREW_PREFIX"].empty?

    # Next, try running `brew --prefix` command
    prefix = `brew --prefix 2>/dev/null`.chomp
    return prefix if $?.success? && !prefix.empty?

    # Fall back to architecture-specific defaults
    if RUBY_PLATFORM.include?("arm64") || RUBY_PLATFORM.include?("aarch64")
      # Apple Silicon or ARM64 Linux
      "/opt/homebrew"
    else
      # Intel Mac or x86_64 Linux
      "/usr/local"
    end
  end

  # Get the Homebrew repository path (where Homebrew itself is installed)
  # Returns: String path to Homebrew repository
  def self.homebrew_repository
    return ENV["HOMEBREW_REPOSITORY"] if ENV["HOMEBREW_REPOSITORY"] && !ENV["HOMEBREW_REPOSITORY"].empty?

    repo = `brew --repository 2>/dev/null`.chomp
    return repo if $?.success? && !repo.empty?

    # Default: Homebrew directory under prefix
    File.join(homebrew_prefix, "Homebrew")
  end

  # Get the Homebrew library path (where taps and formulae are stored)
  # Returns: String path to Homebrew library
  def self.homebrew_library
    return ENV["HOMEBREW_LIBRARY"] if ENV["HOMEBREW_LIBRARY"] && !ENV["HOMEBREW_LIBRARY"].empty?

    File.join(homebrew_repository, "Library")
  end

  # Get the path to a specific tap
  # Args:
  #   user: String (e.g., "homebrew")
  #   repo: String (e.g., "homebrew-core")
  # Returns: String path to tap directory
  def self.tap_path(user, repo)
    File.join(homebrew_library, "Taps", user, repo)
  end

  # Convenience method for homebrew-core tap
  def self.core_tap_path
    tap_path("homebrew", "homebrew-core")
  end

  # Convenience method for homebrew-cask tap
  def self.cask_tap_path
    tap_path("homebrew", "homebrew-cask")
  end

  # Verify that Homebrew is actually installed
  # Returns: Boolean
  def self.homebrew_installed?
    system("which brew > /dev/null 2>&1")
  end

  # Get all paths as a hash (useful for debugging)
  def self.all_paths
    {
      prefix: homebrew_prefix,
      repository: homebrew_repository,
      library: homebrew_library,
      core_tap: core_tap_path,
      cask_tap: cask_tap_path,
    }
  end
end
```

**What this does:**
- Tries Homebrew environment variables first (most reliable)
- Falls back to `brew --prefix` command
- Uses platform detection as last resort
- Provides helper methods for common paths

### Step 2: Update brew-mirror

Edit `mirror/bin/brew-mirror`:

**At the top of the file (after the frozen_string_literal comment):**

```ruby
#!/usr/bin/env brew ruby
# frozen_string_literal: true

# Add this line after the requires at the top
require_relative "../lib/homebrew_paths"
```

**Find this section (around line 102-107):**

```ruby
commit = begin
  core_dir = File.join HOMEBREW_LIBRARY, "Taps/homebrew/homebrew-core"
  Dir.chdir core_dir do
    `git rev-parse HEAD`.chomp
  end
end
```

**Replace it with:**

```ruby
commit = begin
  core_dir = HomebrewPaths.core_tap_path
  abort "Fatal: homebrew-core tap not found at #{core_dir}" unless Dir.exist?(core_dir)

  Dir.chdir core_dir do
    `git rev-parse HEAD`.chomp
  end
end
```

**What changed:**
- Uses dynamic path detection instead of hardcoded `HOMEBREW_LIBRARY`
- Adds error checking if tap doesn't exist
- More robust and portable

### Step 3: Update brew-offline-install

Edit `mirror/bin/brew-offline-install`:

**At the top of the file (after the requires):**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require_relative "../lib/homebrew_paths"
```

**Find this line (line 8):**

```ruby
# TODO(ww): Grab this from Homebrew's API instead of hardcoding it.
CORE_TAP_DIR = "/usr/local/Homebrew/Library/Taps/homebrew/homebrew-core/"
```

**Replace it with:**

```ruby
# Dynamically detect homebrew-core tap location
CORE_TAP_DIR = HomebrewPaths.core_tap_path

# Verify Homebrew is installed before proceeding
unless HomebrewPaths.homebrew_installed?
  abort "Fatal: Homebrew is not installed or not in PATH"
end

# Verify homebrew-core tap exists
unless Dir.exist?(CORE_TAP_DIR)
  abort "Fatal: homebrew-core tap not found at #{CORE_TAP_DIR}"
end
```

**What changed:**
- Removed TODO comment (we're fixing it!)
- Uses dynamic path detection
- Adds validation checks
- More helpful error messages

### Step 4: Ensure the lib Directory Exists

```bash
mkdir -p mirror/lib
```

## Testing

### Test 1: Verify Path Detection

Create a test script `mirror/test/test_paths.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/homebrew_paths"

puts "Homebrew Path Detection Test"
puts "=" * 50
puts ""
puts "Detected paths:"
HomebrewPaths.all_paths.each do |name, path|
  exists = Dir.exist?(path) || File.exist?(path)
  status = exists ? "✓" : "✗"
  puts "  #{status} #{name}: #{path}"
end
puts ""
puts "Homebrew installed: #{HomebrewPaths.homebrew_installed? ? "Yes" : "No"}"
puts ""

# Try to get commit hash
if Dir.exist?(HomebrewPaths.core_tap_path)
  Dir.chdir(HomebrewPaths.core_tap_path) do
    commit = `git rev-parse HEAD`.chomp
    puts "Current homebrew-core commit: #{commit[0..7]}"
  end
else
  puts "WARNING: homebrew-core tap not found"
end
```

Run it:

```bash
chmod +x mirror/test/test_paths.rb
ruby mirror/test/test_paths.rb
```

**Expected output:**
```
Homebrew Path Detection Test
==================================================

Detected paths:
  ✓ prefix: /opt/homebrew
  ✓ repository: /opt/homebrew/Homebrew
  ✓ library: /opt/homebrew/Homebrew/Library
  ✓ core_tap: /opt/homebrew/Homebrew/Library/Taps/homebrew/homebrew-core
  ✓ cask_tap: /opt/homebrew/Homebrew/Library/Taps/homebrew/homebrew-cask

Homebrew installed: Yes

Current homebrew-core commit: abc1234
```

### Test 2: Verify brew-mirror Works

Run brew-mirror in config-only mode (doesn't download anything):

```bash
cd mirror
mkdir -p /tmp/test-mirror
brew ruby bin/brew-mirror -d /tmp/test-mirror -c
```

**Expected output:**
- No errors about missing paths
- Successfully writes `config.json`
- Check the config file:

```bash
cat /tmp/test-mirror/config.json
```

Should show valid commit hash from your system's homebrew-core.

### Test 3: Verify brew-offline-install Validates

Try running brew-offline-install (it will fail, but should fail gracefully):

```bash
cd mirror
ruby bin/brew-offline-install --help
```

**Expected:**
- Error about missing configuration (not about missing paths)
- Error messages should be clear and helpful

## Acceptance Criteria

✅ You're done when:

1. `mirror/lib/homebrew_paths.rb` exists and contains the HomebrewPaths module
2. Test script shows all paths with ✓ checkmarks
3. `brew-mirror` can detect homebrew-core without hardcoded paths
4. `brew-offline-install` can detect homebrew-core without hardcoded paths
5. No references to `/usr/local/Homebrew` remain in modified files
6. Code works on both Intel and Apple Silicon Macs (test on your system)

## Troubleshooting

### Issue: "brew: command not found"

**Solution:**
Homebrew is not in your PATH. Add it:

```bash
# For Apple Silicon:
export PATH="/opt/homebrew/bin:$PATH"

# For Intel:
export PATH="/usr/local/bin:$PATH"
```

### Issue: "homebrew-core tap not found"

**Solution:**
Install/update Homebrew taps:

```bash
brew update
brew tap homebrew/core
```

### Issue: Test script shows ✗ for paths that exist

**Solution:**
Check if paths are correct for your system:

```bash
brew --prefix
brew --repository
ls -la $(brew --repository)/Library/Taps/homebrew/
```

### Issue: "cannot load such file -- homebrew_paths"

**Solution:**
Make sure the lib directory exists and the path is correct:

```bash
ls -la mirror/lib/homebrew_paths.rb
```

The `require_relative` should be: `require_relative "../lib/homebrew_paths"`

## Commit Message

When done:

```bash
git add mirror/lib/homebrew_paths.rb mirror/bin/brew-mirror mirror/bin/brew-offline-install
git commit -m "Task 1.1: Add dynamic Homebrew path detection

- Create HomebrewPaths module for cross-platform path detection
- Update brew-mirror to use dynamic paths
- Update brew-offline-install to use dynamic paths
- Remove hardcoded /usr/local/Homebrew references
- Add validation checks for tap existence
- Supports Intel (/usr/local) and Apple Silicon (/opt/homebrew)"
```

## Next Steps

Proceed to **Task 1.2: Cross-Platform Home Directory**
