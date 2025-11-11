# Task 4.1: Create Verification System

## Objective

Add a verification tool to check mirror completeness and integrity.

## Background

After mirroring thousands of packages, you need to verify:
- All expected files were downloaded
- No corrupted files
- Mirror matches config.json
- Checksums are valid

## Prerequisites

- Phase 3 completed

## Implementation Steps

### Step 1: Create Verification Script

Create `mirror/bin/brew-mirror-verify`:

```ruby
#!/usr/bin/env brew ruby
# frozen_string_literal: true

require "json"
require "digest"
require_relative "../lib/homebrew_paths"
require_relative "../lib/container_helpers"

# Verify mirror integrity
class MirrorVerifier
  attr_reader :mirror_dir, :config, :urlmap, :errors, :warnings

  def initialize(mirror_dir)
    @mirror_dir = mirror_dir
    @errors = []
    @warnings = []
    load_config
    load_urlmap
  end

  def load_config
    config_file = File.join(mirror_dir, "config.json")
    unless File.exist?(config_file)
      @errors << "config.json not found"
      return
    end
    @config = JSON.parse(File.read(config_file))
  end

  def load_urlmap
    urlmap_file = File.join(mirror_dir, "urlmap.json")
    unless File.exist?(urlmap_file)
      @errors << "urlmap.json not found"
      return
    end
    @urlmap = JSON.parse(File.read(urlmap_file))
  end

  def verify!
    puts "Verifying mirror at: #{mirror_dir}"
    puts "=" * 60

    verify_config
    verify_files
    verify_checksums if ENV["VERIFY_CHECKSUMS"]

    print_summary
    errors.empty?
  end

  def verify_config
    puts "\n[1/3] Verifying configuration..."

    if config["taps"]
      puts "  ✓ Taps: #{config["taps"].keys.join(", ")}"
    elsif config["commit"]
      warnings << "Using old config format"
      puts "  ⚠ Old config format (commit only)"
    else
      errors << "Invalid config: no taps or commit"
    end

    puts "  ✓ Mirror created: #{Time.at(config["stamp"].to_i)}"
    puts "  ✓ Base URL: #{config["baseurl"]}"
  end

  def verify_files
    puts "\n[2/3] Verifying files..."

    missing_files = []
    urlmap.each do |url, filename|
      filepath = File.join(mirror_dir, filename)
      unless File.exist?(filepath)
        missing_files << filename
      end
    end

    if missing_files.any?
      errors << "#{missing_files.count} files missing from mirror"
      missing_files.first(5).each { |f| puts "  ✗ Missing: #{f}" }
      puts "  ... and #{missing_files.count - 5} more" if missing_files.count > 5
    else
      puts "  ✓ All #{urlmap.count} files present"
    end

    # Check for orphaned files
    mirror_files = Dir.glob("#{mirror_dir}/*").map { |f| File.basename(f) }
    expected_files = urlmap.values + ["config.json", "urlmap.json", "identifier_cache.json"]
    orphaned = mirror_files - expected_files

    if orphaned.any?
      warnings << "#{orphaned.count} orphaned files found"
      puts "  ⚠ #{orphaned.count} orphaned files (use brew-mirror-prune)"
    end

    # Check file sizes
    total_size = `du -sh #{mirror_dir}`.split.first
    puts "  ✓ Total mirror size: #{total_size}"
  end

  def verify_checksums
    puts "\n[3/3] Verifying checksums (slow)..."
    puts "  This may take a while..."
    # TODO: Implement checksum verification
    warnings << "Checksum verification not yet implemented"
  end

  def print_summary
    puts "\n" + "=" * 60
    puts "Verification Summary"
    puts "=" * 60

    if errors.empty? && warnings.empty?
      puts "✓ Mirror is valid and complete!"
    else
      puts "Errors: #{errors.count}" if errors.any?
      errors.each { |e| puts "  ✗ #{e}" }

      puts "Warnings: #{warnings.count}" if warnings.any?
      warnings.each { |w| puts "  ⚠ #{w}" }
    end
  end
end

# Parse CLI
mirror_dir = ARGV.first || abort("Usage: brew ruby brew-mirror-verify <mirror-directory>")
abort "Directory not found: #{mirror_dir}" unless Dir.exist?(mirror_dir)

# Run verification
verifier = MirrorVerifier.new(mirror_dir)
exit(verifier.verify? ? 0 : 1)
```

### Step 2: Make Executable

```bash
chmod +x mirror/bin/brew-mirror-verify
```

### Step 3: Add to Main Mirror Script

In `mirror/bin/brew-mirror`, add option:

```ruby
parser.on "--verify", "verify mirror after creation" do
  options[:verify] = true
end
```

At the end:

```ruby
if options[:verify]
  system "brew", "ruby", File.expand_path("brew-mirror-verify", __dir__), options[:directory]
end
```

## Testing

```bash
# Create mirror
brew ruby mirror/bin/brew-mirror -d /tmp/test-mirror -f wget -s 1

# Verify it
brew ruby mirror/bin/brew-mirror-verify /tmp/test-mirror
```

**Expected output:**
```
Verifying mirror at: /tmp/test-mirror
============================================================

[1/3] Verifying configuration...
  ✓ Taps: homebrew/homebrew-core
  ✓ Mirror created: 2025-11-11 10:00:00
  ✓ Base URL: http://localhost:8000

[2/3] Verifying files...
  ✓ All 3 files present
  ✓ Total mirror size: 2.5M

============================================================
Verification Summary
============================================================
✓ Mirror is valid and complete!
```

## Acceptance Criteria

✅ Done when:
1. brew-mirror-verify script works
2. Checks config, files, and integrity
3. Reports errors and warnings
4. Exit code indicates success/failure
5. --verify option in brew-mirror works

## Commit Message

```bash
git add mirror/bin/brew-mirror-verify mirror/bin/brew-mirror
git commit -m "Task 4.1: Add mirror verification system

- Create brew-mirror-verify tool
- Check config format and completeness
- Verify all files present in mirror
- Detect orphaned files
- Add --verify option to brew-mirror
- Report errors and warnings with exit codes"
```

## Next Steps

Proceed to **Task 4.2: Generate Mirror Manifest**
