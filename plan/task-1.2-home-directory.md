# Task 1.2: Cross-Platform Home Directory Detection

> **📝 NOTE:** This document describes completed work. The solution (using `REAL_HOME` environment variable) is still in use with the cache pre-population approach. Linux support was later removed - offlinebrew is now macOS-only.

## Objective

Replace hardcoded `/Users/$USER` paths with cross-platform home directory detection that works on macOS, Linux, and other Unix systems.

## Background

Currently, the URL shim scripts (`brew-offline-curl` and `brew-offline-git`) hardcode the home directory as `/Users/$USER`. This only works on macOS. On Linux, home directories are typically `/home/$USER`.

**Current code locations:**
- `mirror/bin/brew-offline-curl` line 15
- `mirror/bin/brew-offline-git` line 15

**Why this matters:**
- Homebrew is also available on Linux
- Makes code more maintainable
- Ruby has built-in methods for this (`Dir.home`)
- Current approach breaks if `$HOME` is customized

**Current problematic code:**
```ruby
BREW_OFFLINE_DIR = File.join "/Users", ENV["USER"], ".offlinebrew"
```

## Prerequisites

- Task 1.1 completed (Dynamic Homebrew Path Detection)

## Implementation Steps

### Step 1: Update brew-offline-curl

Edit `mirror/bin/brew-offline-curl`:

**Find this section (around line 14-17):**

```ruby
# `curl` is sometimes called from within a fake $HOME, so we can't just
# expand ~ or $HOME here. Instead, build it manually.
BREW_OFFLINE_DIR = File.join "/Users", ENV["USER"], ".offlinebrew"
BREW_OFFLINE_CONFIG = File.join BREW_OFFLINE_DIR, "config.json"
BREW_OFFLINE_URLMAP = File.join BREW_OFFLINE_DIR, "urlmap.json"
```

**Replace it with:**

```ruby
# Homebrew sometimes runs curl from within a fake $HOME (especially during sandbox builds).
# We need to reliably find the user's actual home directory.
# Try multiple methods to determine the real home directory.
def real_home_directory
  # Method 1: Use REAL_HOME if set (we can set this in brew-offline-install)
  return ENV["REAL_HOME"] if ENV["REAL_HOME"] && !ENV["REAL_HOME"].empty?

  # Method 2: Use SUDO_USER if running under sudo (common for system installs)
  if ENV["SUDO_USER"] && !ENV["SUDO_USER"].empty?
    user = ENV["SUDO_USER"]
    # Try to get home from /etc/passwd
    home = `getent passwd #{user} 2>/dev/null | cut -d: -f6`.chomp
    return home if !home.empty? && Dir.exist?(home)

    # Fallback for macOS (doesn't have getent)
    home = `dscl . -read /Users/#{user} NFSHomeDirectory 2>/dev/null | awk '{print $2}'`.chomp
    return home if !home.empty? && Dir.exist?(home)
  end

  # Method 3: Use original HOME if it looks reasonable
  if ENV["HOME"] && !ENV["HOME"].empty? && ENV["HOME"] != "/var/root"
    return ENV["HOME"]
  end

  # Method 4: Build from USER variable
  if ENV["USER"] && !ENV["USER"].empty?
    # Detect OS and construct path
    if File.exist?("/Users")
      # macOS
      return File.join("/Users", ENV["USER"])
    else
      # Linux and other Unix
      return File.join("/home", ENV["USER"])
    end
  end

  # Last resort: current directory (will fail but at least we tried)
  Dir.pwd
end

BREW_OFFLINE_DIR = File.join real_home_directory, ".offlinebrew"
BREW_OFFLINE_CONFIG = File.join BREW_OFFLINE_DIR, "config.json"
BREW_OFFLINE_URLMAP = File.join BREW_OFFLINE_DIR, "urlmap.json"
```

**What this does:**
- Tries multiple methods to find the real home directory
- Handles cases where Homebrew uses a fake $HOME
- Works on macOS and Linux
- Falls back gracefully if detection fails

### Step 2: Update brew-offline-git

Edit `mirror/bin/brew-offline-git`:

**Find this section (around line 14-17):**

```ruby
# `git` is sometimes called from within a fake $HOME, so we can't just
# expand ~ or $HOME here. Instead, build it manually.
BREW_OFFLINE_DIR = File.join "/Users", ENV["USER"], ".offlinebrew"
BREW_OFFLINE_CONFIG = File.join BREW_OFFLINE_DIR, "config.json"
BREW_OFFLINE_URLMAP = File.join BREW_OFFLINE_DIR, "urlmap.json"
```

**Replace it with the EXACT SAME code as Step 1:**

```ruby
# Homebrew sometimes runs git from within a fake $HOME (especially during sandbox builds).
# We need to reliably find the user's actual home directory.
# Try multiple methods to determine the real home directory.
def real_home_directory
  # Method 1: Use REAL_HOME if set (we can set this in brew-offline-install)
  return ENV["REAL_HOME"] if ENV["REAL_HOME"] && !ENV["REAL_HOME"].empty?

  # Method 2: Use SUDO_USER if running under sudo (common for system installs)
  if ENV["SUDO_USER"] && !ENV["SUDO_USER"].empty?
    user = ENV["SUDO_USER"]
    # Try to get home from /etc/passwd
    home = `getent passwd #{user} 2>/dev/null | cut -d: -f6`.chomp
    return home if !home.empty? && Dir.exist?(home)

    # Fallback for macOS (doesn't have getent)
    home = `dscl . -read /Users/#{user} NFSHomeDirectory 2>/dev/null | awk '{print $2}'`.chomp
    return home if !home.empty? && Dir.exist?(home)
  end

  # Method 3: Use original HOME if it looks reasonable
  if ENV["HOME"] && !ENV["HOME"].empty? && ENV["HOME"] != "/var/root"
    return ENV["HOME"]
  end

  # Method 4: Build from USER variable
  if ENV["USER"] && !ENV["USER"].empty?
    # Detect OS and construct path
    if File.exist?("/Users")
      # macOS
      return File.join("/Users", ENV["USER"])
    else
      # Linux and other Unix
      return File.join("/home", ENV["USER"])
    end
  end

  # Last resort: current directory (will fail but at least we tried)
  Dir.pwd
end

BREW_OFFLINE_DIR = File.join real_home_directory, ".offlinebrew"
BREW_OFFLINE_CONFIG = File.join BREW_OFFLINE_DIR, "config.json"
BREW_OFFLINE_URLMAP = File.join BREW_OFFLINE_DIR, "urlmap.json"
```

**Why duplicate the function:**
These are separate executables that don't share code, so each needs its own copy of the function.

### Step 3: Update brew-offline-install to Set REAL_HOME

Edit `mirror/bin/brew-offline-install`:

**Find the section where environment variables are set (around line 22-44):**

Right after this line:
```ruby
ENV["HOMEBREW_VERBOSE"] = "1"
```

**Add:**

```ruby
# Set REAL_HOME so that our shim scripts can find the config even when
# Homebrew runs them with a fake $HOME (which happens during sandbox builds).
ENV["REAL_HOME"] = Dir.home
```

**What this does:**
- Sets a custom environment variable with the real home directory
- The shim scripts check this first
- Prevents issues with Homebrew's sandboxing

### Step 4: Refactor to Shared Module (Optional but Recommended)

To avoid code duplication, we can create a shared module.

Create `mirror/lib/offlinebrew_config.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# OfflinebrewConfig: Shared utilities for finding configuration files
module OfflinebrewConfig
  # Find the real home directory, even when called from sandbox
  def self.real_home_directory
    # Method 1: Use REAL_HOME if set (set by brew-offline-install)
    return ENV["REAL_HOME"] if ENV["REAL_HOME"] && !ENV["REAL_HOME"].empty?

    # Method 2: Use SUDO_USER if running under sudo
    if ENV["SUDO_USER"] && !ENV["SUDO_USER"].empty?
      user = ENV["SUDO_USER"]
      # Try getent (Linux)
      home = `getent passwd #{user} 2>/dev/null | cut -d: -f6`.chomp
      return home if !home.empty? && Dir.exist?(home)

      # Try dscl (macOS)
      home = `dscl . -read /Users/#{user} NFSHomeDirectory 2>/dev/null | awk '{print $2}'`.chomp
      return home if !home.empty? && Dir.exist?(home)
    end

    # Method 3: Use original HOME if reasonable
    if ENV["HOME"] && !ENV["HOME"].empty? && ENV["HOME"] != "/var/root"
      return ENV["HOME"]
    end

    # Method 4: Build from USER
    if ENV["USER"] && !ENV["USER"].empty?
      if File.exist?("/Users")
        return File.join("/Users", ENV["USER"])
      else
        return File.join("/home", ENV["USER"])
      end
    end

    # Last resort
    Dir.pwd
  end

  # Get the offlinebrew config directory
  def self.config_dir
    File.join(real_home_directory, ".offlinebrew")
  end

  # Get the config file path
  def self.config_path
    File.join(config_dir, "config.json")
  end

  # Get the urlmap file path
  def self.urlmap_path
    File.join(config_dir, "urlmap.json")
  end
end
```

Then update the shim scripts to use it:

**In `brew-offline-curl`:**

```ruby
require_relative "../lib/offlinebrew_config"

BREW_OFFLINE_DIR = OfflinebrewConfig.config_dir
BREW_OFFLINE_CONFIG = OfflinebrewConfig.config_path
BREW_OFFLINE_URLMAP = OfflinebrewConfig.urlmap_path
```

**In `brew-offline-git`:**

```ruby
require_relative "../lib/offlinebrew_config"

BREW_OFFLINE_DIR = OfflinebrewConfig.config_dir
BREW_OFFLINE_CONFIG = OfflinebrewConfig.config_path
BREW_OFFLINE_URLMAP = OfflinebrewConfig.urlmap_path
```

**Note:** If you do this refactoring, remove the `real_home_directory` function from both shim files since it's now in the module.

## Testing

### Test 1: Check Home Directory Detection

Create `mirror/test/test_home_detection.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/offlinebrew_config"

puts "Home Directory Detection Test"
puts "=" * 50
puts ""

puts "System information:"
puts "  OS: #{RUBY_PLATFORM}"
puts "  USER: #{ENV["USER"]}"
puts "  HOME: #{ENV["HOME"]}"
puts "  SUDO_USER: #{ENV["SUDO_USER"] || "(not set)"}"
puts ""

detected_home = OfflinebrewConfig.real_home_directory
puts "Detected home: #{detected_home}"
puts "Exists: #{Dir.exist?(detected_home) ? "Yes" : "No"}"
puts ""

puts "Configuration paths:"
puts "  Config dir: #{OfflinebrewConfig.config_dir}"
puts "  Config file: #{OfflinebrewConfig.config_path}"
puts "  URL map: #{OfflinebrewConfig.urlmap_path}"
```

Run it:

```bash
chmod +x mirror/test/test_home_detection.rb
ruby mirror/test/test_home_detection.rb
```

**Expected output:**
```
Home Directory Detection Test
==================================================

System information:
  OS: arm64-darwin23
  USER: yourname
  HOME: /Users/yourname
  SUDO_USER: (not set)

Detected home: /Users/yourname
Exists: Yes

Configuration paths:
  Config dir: /Users/yourname/.offlinebrew
  Config file: /Users/yourname/.offlinebrew/config.json
  URL map: /Users/yourname/.offlinebrew/urlmap.json
```

### Test 2: Simulate Fake HOME

Test that detection works even with a fake $HOME:

```bash
env HOME=/tmp/fake_home ruby mirror/test/test_home_detection.rb
```

**Expected:**
Should still detect your real home directory using fallback methods.

### Test 3: Test from Shim Scripts

Create a dummy config to test the shims:

```bash
mkdir -p ~/.offlinebrew
echo '{"baseurl": "http://test"}' > ~/.offlinebrew/config.json
echo '{}' > ~/.offlinebrew/urlmap.json
```

Test brew-offline-curl:

```bash
ruby mirror/bin/brew-offline-curl --version
```

**Expected:**
- No errors about missing config files
- Shows curl version (falls through to real curl)

### Test 4: Verify No Hardcoded /Users

Search for any remaining hardcoded paths:

```bash
grep -r "/Users" mirror/bin/
```

**Expected output:**
```
(no results)
```

Or only in comments, not in actual code.

## Acceptance Criteria

✅ You're done when:

1. No references to hardcoded `/Users` paths in shim scripts
2. Test script correctly detects home directory on your system
3. Detection works with fake $HOME environment variable
4. `brew-offline-curl` and `brew-offline-git` can find config files
5. Code works on both macOS and Linux (test on available systems)
6. Optional: Refactored to use shared module (cleaner code)

## Troubleshooting

### Issue: "cannot load such file -- offlinebrew_config"

**Solution:**
Make sure the lib file exists:

```bash
ls -la mirror/lib/offlinebrew_config.rb
```

And the require path is correct: `require_relative "../lib/offlinebrew_config"`

### Issue: Detection returns "/var/root" or wrong path

**Solution:**
This happens when running under sudo. Set REAL_HOME manually:

```bash
export REAL_HOME=$HOME
# Then run your test
```

### Issue: "Couldn't read config or urlmap" when testing shims

**Solution:**
Create dummy config files:

```bash
mkdir -p ~/.offlinebrew
echo '{"baseurl": "http://localhost:8000"}' > ~/.offlinebrew/config.json
echo '{}' > ~/.offlinebrew/urlmap.json
```

### Issue: getent command not found on macOS

**Solution:**
This is expected. The code falls back to `dscl` on macOS automatically. No action needed.

## Commit Message

When done:

```bash
git add mirror/bin/brew-offline-curl mirror/bin/brew-offline-git mirror/bin/brew-offline-install mirror/lib/offlinebrew_config.rb
git commit -m "Task 1.2: Add cross-platform home directory detection

- Create OfflinebrewConfig module for home detection
- Update brew-offline-curl to use cross-platform paths
- Update brew-offline-git to use cross-platform paths
- Set REAL_HOME in brew-offline-install for sandbox support
- Support macOS (/Users) and Linux (/home) paths
- Handle sudo and fake HOME scenarios"
```

## Next Steps

Proceed to **Task 1.3: Test Modern Homebrew API Compatibility**
