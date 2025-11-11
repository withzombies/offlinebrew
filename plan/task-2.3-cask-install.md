# Task 2.3: Update brew-offline-install for Casks

## Objective

Extend `brew-offline-install` to support installing casks from the offline mirror, handling both formula and cask installations.

## Background

Currently, `brew-offline-install` only handles `brew install <formula>`. We need to add support for:
- `brew install --cask <caskname>`
- Resetting the homebrew-cask tap to the mirrored commit
- Handling cask-specific installation requirements

## Prerequisites

- Task 2.1 completed (Cask tap mirroring)
- Task 2.2 completed (Cask download handling)

## Implementation Steps

### Step 1: Update Configuration Handling

Edit `mirror/bin/brew-offline-install`:

**Find the section that reads the remote config (around line 65-82):**

```ruby
# Clobber our config, and write the remote config/urlmap to disk
# locally for the `curl` and `git` shims to read.
begin
  config = JSON.parse Net::HTTP.get(BREW_OFFLINE_REMOTE_CONFIG)
  urlmap = JSON.parse Net::HTTP.get(BREW_OFFLINE_REMOTE_URLMAP)

  # The remote config doesn't get to clobber our baseurl.
  config[:baseurl] = baseurl
rescue StandardError => e
  abort "#{e}: #{e.message} while fetching remote config and urlmap!"
end
```

**Add after this section:**

```ruby
# Parse config and handle both old and new formats
config = JSON.parse(config) if config.is_a?(String)
config = config.transform_keys(&:to_sym)

# Handle new tap-based config format
taps = if config[:taps]
         # New format
         config[:taps]
       elsif config[:commit]
         # Old format - convert to new format
         {
           "homebrew/homebrew-core" => {
             "commit" => config[:commit],
             "type" => "formula",
           },
         }
       else
         abort "Invalid config format: no taps or commit found"
       end
```

### Step 2: Reset Multiple Taps

**Find the section that resets homebrew-core (around line 104-109):**

```ruby
# Reset homebrew/homebrew-core to the commit that we mirrored the package
# tree at. This prevents us from attempting to install either earlier or later
# versions of packages/resources than we have mirrored.
Dir.chdir CORE_TAP_DIR do
  `git checkout #{config[:commit]}`
end
```

**Replace with:**

```ruby
# Reset all mirrored taps to their respective commits
# This ensures we install the exact versions we mirrored
taps.each do |tap_name, tap_info|
  tap_commit = tap_info["commit"] || tap_info[:commit]
  tap_type = tap_info["type"] || tap_info[:type] || "unknown"

  # Determine tap directory
  tap_dir = case tap_name
            when "homebrew/homebrew-core"
              HomebrewPaths.core_tap_path
            when "homebrew/homebrew-cask"
              HomebrewPaths.cask_tap_path
            else
              # Generic tap path
              user, repo = tap_name.split("/")
              HomebrewPaths.tap_path(user, repo)
            end

  unless Dir.exist?(tap_dir)
    opoo "Tap not found: #{tap_name} at #{tap_dir}, skipping"
    next
  end

  ohai "Resetting #{tap_name} to #{tap_commit[0..7]}..."
  Dir.chdir tap_dir do
    system "git", "fetch", "--quiet"  # Ensure we have the commit
    result = system "git", "checkout", "--quiet", tap_commit

    unless result
      opoo "Failed to checkout #{tap_name} at #{tap_commit}"
      opoo "This may cause installation to fail"
    end
  end
end
```

**Add the require at the top:**

```ruby
require_relative "../lib/homebrew_paths"
require_relative "../lib/offlinebrew_config"
```

### Step 3: Detect Cask vs Formula Installation

**Add before the argument parsing section (around line 83):**

```ruby
# Detect if user is trying to install a cask
is_cask_install = ARGV.include?("--cask") || ARGV.include?("cask")

# Also check if the command starts with "cask"
is_cask_install = true if ARGV.first == "cask"
```

### Step 4: Handle Cask-Specific Flags

**Find the invalid flags section (around line 86-94):**

```ruby
INVALID_FLAGS = %w[
  --force-bottle
  --devel
  --HEAD
].freeze

invalid_flags = ARGV & INVALID_FLAGS

abort "One or more invalid flags passed: #{invalid_flags.join(", ")}" if invalid_flags.any?
```

**Update to:**

```ruby
# Flags that would cause us to download assets we haven't mirrored
INVALID_FORMULA_FLAGS = %w[
  --force-bottle
  --devel
  --HEAD
].freeze

INVALID_CASK_FLAGS = %w[
  --no-quarantine
  --language
  --greedy
].freeze

if is_cask_install
  invalid_flags = ARGV & INVALID_CASK_FLAGS
  abort "Cask installation with these flags not supported: #{invalid_flags.join(", ")}" if invalid_flags.any?
else
  invalid_flags = ARGV & INVALID_FORMULA_FLAGS
  abort "One or more invalid flags passed: #{invalid_flags.join(", ")}" if invalid_flags.any?
end
```

### Step 5: Update the Install Command

**Find the install command (around line 111):**

```ruby
system "brew", "install", *ARGV
```

**Replace with:**

```ruby
# Run the appropriate install command
if is_cask_install
  # For cask installs
  # Remove 'cask' from ARGV if it's the first argument
  args = ARGV.dup
  args.shift if args.first == "cask"

  ohai "Installing cask(s): #{args.join(", ")}"
  success = system "brew", "install", "--cask", *args
else
  # For formula installs
  ohai "Installing formula(e): #{ARGV.join(", ")}"
  success = system "brew", "install", "--build-from-source", *ARGV
end

# Check result
unless success
  abort "Installation failed! Check the output above for errors."
end
```

### Step 6: Add Usage Information

**At the top of the file, add a usage comment:**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# brew-offline-install: Install formulae or casks from an offline mirror
#
# Usage:
#   brew-offline-install <formula>           # Install a formula
#   brew-offline-install --cask <caskname>   # Install a cask
#   brew-offline-install <formula> <formula> # Install multiple formulae
#   brew-offline-install --cask <cask> <cask> # Install multiple casks
#
# Configuration:
#   ~/.offlinebrew/config.json must contain:
#     {"baseurl": "http://mirror-server:8000"}
```

### Step 7: Add Better Error Messages

**Add a validation function before the main code:**

```ruby
def validate_configuration(config, is_cask_install)
  # Check if the mirror has the required tap
  taps = config[:taps] || {}

  if is_cask_install
    unless taps["homebrew/homebrew-cask"]
      abort <<~ERROR
        ERROR: This mirror does not include casks.
        The mirror was created without the homebrew-cask tap.
        Please re-create the mirror with cask support.
      ERROR
    end
  end

  # Check if taps are installed locally
  taps.each do |tap_name, _tap_info|
    case tap_name
    when "homebrew/homebrew-core"
      tap_dir = HomebrewPaths.core_tap_path
    when "homebrew/homebrew-cask"
      tap_dir = HomebrewPaths.cask_tap_path
      unless Dir.exist?(tap_dir)
        abort <<~ERROR
          ERROR: homebrew-cask tap not installed locally.
          Please run: brew tap homebrew/cask
        ERROR
      end
    end
  end
end
```

**Call it after loading the config:**

```ruby
# After parsing config
validate_configuration(config, is_cask_install)
```

## Testing

### Test 1: Create a Test Mirror with Casks

```bash
rm -rf /tmp/test-mirror
mkdir /tmp/test-mirror

# Mirror a formula and a cask
brew ruby mirror/bin/brew-mirror \
  -d /tmp/test-mirror \
  -f jq \
  --casks firefox \
  -s 1
```

### Test 2: Serve the Mirror

In one terminal:

```bash
cd /tmp/test-mirror
python3 -m http.server 8000
```

### Test 3: Configure Client

In another terminal:

```bash
mkdir -p ~/.offlinebrew
cat > ~/.offlinebrew/config.json << 'EOF'
{
  "baseurl": "http://localhost:8000"
}
EOF
```

### Test 4: Test Formula Installation

```bash
# Uninstall if already installed
brew uninstall jq 2>/dev/null || true

# Install from offline mirror
ruby mirror/bin/brew-offline-install jq

# Verify it works
jq --version
```

**Expected:**
- Installs successfully from mirror
- No network access required
- jq command works

### Test 5: Test Cask Installation

```bash
# Uninstall if already installed
brew uninstall --cask firefox 2>/dev/null || true

# Install from offline mirror
ruby mirror/bin/brew-offline-install --cask firefox

# Verify
ls -la /Applications/Firefox.app
```

**Expected:**
- Downloads Firefox from local mirror
- Installs successfully
- Firefox.app appears in /Applications

### Test 6: Test Error Handling

Test that errors are caught:

```bash
# Try to install non-mirrored cask
ruby mirror/bin/brew-offline-install --cask google-chrome
```

**Expected:**
```
Error: google-chrome not found in mirror
```

Or Homebrew's error about missing cask.

### Test 7: Test Mixed Installation (Should Fail)

```bash
ruby mirror/bin/brew-offline-install jq --cask firefox
```

**Expected:**
Should give clear error that mixed installations aren't supported. User should run separate commands.

## Acceptance Criteria

✅ You're done when:

1. Can install formulae from offline mirror (existing functionality preserved)
2. Can install casks from offline mirror with `--cask` flag
3. Both homebrew-core and homebrew-cask are reset to mirrored commits
4. Clear error messages when:
   - Mirror doesn't include casks
   - Required tap not installed locally
   - Package not in mirror
5. Installation works with HTTP server serving the mirror
6. Tests pass for both formula and cask installation

## Troubleshooting

### Issue: "Tap not found: homebrew/homebrew-cask"

**Solution:**
Install the cask tap:

```bash
brew tap homebrew/cask
```

### Issue: Cask installs but downloads from internet

**Solution:**
Check that:
1. The cask was actually mirrored (check urlmap.json)
2. The shim scripts are being used (check HOMEBREW_CURL_PATH)
3. The baseurl is correct in config.json

Debug by adding verbosity:

```bash
export HOMEBREW_VERBOSE=1
ruby mirror/bin/brew-offline-install --cask firefox
```

### Issue: "Download failed" during cask install

**Solution:**
Check that the HTTP server is running:

```bash
curl http://localhost:8000/config.json
```

And that the DMG file exists:

```bash
ls -la /tmp/test-mirror/*.dmg
```

### Issue: Git checkout fails for tap

**Solution:**
The mirror commit may not exist locally. Fetch it:

```bash
cd $(brew --repository)/Library/Taps/homebrew/homebrew-cask
git fetch origin
```

## Commit Message

When done:

```bash
git add mirror/bin/brew-offline-install mirror/lib/homebrew_paths.rb
git commit -m "Task 2.3: Add cask installation support to brew-offline-install

- Support both formula and cask installations
- Handle new tap-based config format with backward compatibility
- Reset both homebrew-core and homebrew-cask to mirrored commits
- Add --cask flag detection
- Validate mirror includes required taps
- Add clear error messages for missing taps/casks
- Support both old and new config formats
- Add usage documentation in comments"
```

## Next Steps

Proceed to **Task 2.4: Update URL Shims for Casks**
