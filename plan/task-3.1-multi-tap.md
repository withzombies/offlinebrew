# Task 3.1: Multi-Tap Configuration Support

## Objective

Add support for mirroring multiple taps beyond just homebrew-core and homebrew-cask, with configuration options.

## Background

Users may want to mirror:
- `homebrew/homebrew-cask-fonts` (fonts)
- `homebrew/homebrew-cask-versions` (older app versions)
- Custom third-party taps
- Internal company taps

## Prerequisites

- Phase 2 completed (Tasks 2.1-2.4)

## Implementation Steps

### Step 1: Add --taps CLI Option

Edit `mirror/bin/brew-mirror`:

**In options hash:**

```ruby
options = {
  directory: "/Users/william/tmp/brew-mirror",
  baseurl: "http://localhost:8000",
  sleep: 0.5,
  config_only: false,
  iterator: nil,
  casks: nil,
  taps: ["homebrew/homebrew-core", "homebrew/homebrew-cask"],  # Default taps
}
```

**In OptionParser:**

```ruby
  parser.on "--taps tap1,tap2", Array, "specify taps to mirror (default: core,cask)" do |taps|
    options[:taps] = taps
  end
```

### Step 2: Create Tap Manager Module

Create `mirror/lib/tap_manager.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "homebrew_paths"

# TapManager: Utilities for managing Homebrew taps
module TapManager
  # Parse tap name into user/repo
  def self.parse_tap_name(tap_name)
    parts = tap_name.split("/")
    if parts.length == 2
      { user: parts[0], repo: parts[1] }
    else
      abort "Invalid tap name: #{tap_name}. Expected format: user/repo"
    end
  end

  # Get tap directory path
  def self.tap_directory(tap_name)
    parsed = parse_tap_name(tap_name)
    HomebrewPaths.tap_path(parsed[:user], parsed[:repo])
  end

  # Check if tap is installed
  def self.tap_installed?(tap_name)
    HomebrewPaths.tap_exists?(tap_directory(tap_name))
  end

  # Get tap commit
  def self.tap_commit(tap_name)
    HomebrewPaths.tap_commit(tap_directory(tap_name))
  end

  # Determine tap type (formula, cask, or unknown)
  def self.tap_type(tap_name)
    return "formula" if tap_name == "homebrew/homebrew-core"
    return "cask" if tap_name.include?("cask")
    "mixed"
  end

  # Install tap if not present
  def self.ensure_tap_installed(tap_name)
    return if tap_installed?(tap_name)

    puts "Tap not installed: #{tap_name}"
    print "Install now? (y/n): "
    return unless $stdin.gets.chomp.downcase == "y"

    system "brew", "tap", tap_name
  end
end
```

### Step 3: Update Config Generation

In `mirror/bin/brew-mirror`:

```ruby
require_relative "../lib/tap_manager"

# Replace the config generation section:
config[:taps] = {}

options[:taps].each do |tap_name|
  unless TapManager.tap_installed?(tap_name)
    opoo "Tap not installed: #{tap_name}, skipping"
    next
  end

  commit = TapManager.tap_commit(tap_name)
  tap_type = TapManager.tap_type(tap_name)

  config[:taps][tap_name] = {
    "commit" => commit,
    "type" => tap_type,
  }

  ohai "Will mirror #{tap_name} (#{tap_type}) at commit #{commit[0..7]}"
end

# Ensure at least one tap configured
abort "No valid taps configured!" if config[:taps].empty?
```

### Step 4: Mirror All Configured Taps

Add generic tap mirroring after cask mirroring:

```ruby
# Mirror from all configured taps
config[:taps].each do |tap_name, tap_info|
  tap_type = tap_info["type"]

  case tap_type
  when "formula"
    # Already handled by Formula.all
    next
  when "cask"
    # Already handled by cask iteration
    next
  when "mixed"
    # Handle mixed taps (both formulae and casks)
    ohai "Mirroring mixed tap: #{tap_name}"

    # Try formulae first
    tap_dir = TapManager.tap_directory(tap_name)
    formula_dir = File.join(tap_dir, "Formula")

    if Dir.exist?(formula_dir)
      Dir.glob("#{formula_dir}/*.rb").each do |formula_file|
        formula_name = File.basename(formula_file, ".rb")
        begin
          formula = Formula["#{tap_name}/#{formula_name}"]
          # Mirror formula (reuse existing logic)
          # ... (similar to main formula loop)
        rescue StandardError => e
          opoo "Failed to load formula #{formula_name}: #{e.message}"
        end
      end
    end

    # Try casks
    cask_dir = File.join(tap_dir, "Casks")
    if Dir.exist?(cask_dir)
      Dir.glob("#{cask_dir}/*.rb").each do |cask_file|
        cask_token = File.basename(cask_file, ".rb")
        begin
          cask = Cask::CaskLoader.load("#{tap_name}/#{cask_token}")
          # Mirror cask (reuse existing logic)
          # ... (similar to cask loop)
        rescue StandardError => e
          opoo "Failed to load cask #{cask_token}: #{e.message}"
        end
      end
    end
  end
end
```

### Step 5: Update brew-offline-install

In `mirror/bin/brew-offline-install`:

**Update tap checkout section to handle all taps:**

```ruby
# Reset all taps (already done in Task 2.3, just verify it handles any tap)
taps.each do |tap_name, tap_info|
  # ... existing code handles this ...
end
```

## Testing

```bash
# Test with font tap
brew tap homebrew/cask-fonts

# Mirror with multiple taps
brew ruby mirror/bin/brew-mirror \
  -d /tmp/multi-tap-test \
  --taps homebrew/homebrew-core,homebrew/homebrew-cask,homebrew/homebrew-cask-fonts \
  -f wget \
  --casks firefox,font-fira-code \
  -s 1
```

## Acceptance Criteria

✅ Done when:
1. Can specify custom taps via --taps option
2. All specified taps are included in config
3. Can mirror formulae/casks from non-default taps
4. Gracefully handles missing taps
5. Works with font taps and version taps

## Commit Message

```bash
git add mirror/bin/brew-mirror mirror/lib/tap_manager.rb
git commit -m "Task 3.1: Add multi-tap configuration support

- Add --taps CLI option for custom tap selection
- Create TapManager module for tap operations
- Support mixed taps (both formulae and casks)
- Mirror from any installed Homebrew tap
- Default to core and cask taps"
```

## Next Steps

Proceed to **Task 3.2: Fix Git Repository UUID Collision**
