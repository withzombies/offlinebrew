# Task 5.3: Create Migration Guide

## Objective

Create a guide for users upgrading from the old version to the new version with cask support.

## Prerequisites

- All previous tasks completed

## Implementation Steps

### Step 1: Create Migration Guide

Create `MIGRATION.md`:

```markdown
# Migration Guide: v1.x to v2.0

This guide helps you migrate from offlinebrew 1.x (formula-only) to 2.0 (with cask support).

## What's Changed

### Breaking Changes

**Config Format:**
- Old: `{"commit": "...", "stamp": "...", "cache": "..."}`
- New: `{"taps": {...}, "stamp": "...", "cache": "..."}`
- **Good news:** Old configs still work! The new code is backward compatible.

**Path Detection:**
- Old: Hardcoded `/usr/local/Homebrew`
- New: Dynamic detection (supports Apple Silicon `/opt/homebrew`)

### New Features

- ✨ Cask support (GUI apps, fonts, etc.)
- ✨ Multi-tap configuration
- ✨ Incremental updates
- ✨ Mirror verification
- ✨ Better error messages

## Migration Paths

### Scenario 1: You have an existing 1.x mirror

**Option A: Keep using it (no changes needed)**

Your old mirror will continue to work with the new tools. The new code reads old config formats.

```bash
# This still works!
ruby mirror/bin/brew-offline-install wget
```

**Option B: Recreate with cask support**

To add casks, recreate your mirror:

```bash
# Backup old mirror
mv /path/to/old-mirror /path/to/old-mirror.backup

# Create new mirror with casks
brew ruby mirror/bin/brew-mirror \
  -d /path/to/new-mirror \
  -f wget,jq,htop \
  --casks firefox,chrome,vscode \
  -s 1
```

**Option C: Update incrementally**

Use the new --update mode to add casks without re-downloading formulas:

```bash
# Add casks to existing mirror
brew ruby mirror/bin/brew-mirror \
  -d /path/to/existing-mirror \
  --casks firefox,chrome \
  --update \
  -s 1
```

### Scenario 2: You only have local configs

**What to do:**

Your `~/.offlinebrew/config.json` still works! No changes needed.

```json
{
  "baseurl": "http://mirror:8000"
}
```

The tools will auto-upgrade this when they fetch the remote config.

### Scenario 3: Fresh install

**Just follow the new Quick Start:**

```bash
# Create mirror
brew ruby mirror/bin/brew-mirror -d ./mirror -f wget --casks firefox -s 1

# Configure client
mkdir -p ~/.offlinebrew
echo '{"baseurl": "http://localhost:8000"}' > ~/.offlinebrew/config.json

# Install
ruby mirror/bin/brew-offline-install wget
ruby mirror/bin/brew-offline-install --cask firefox
```

## Step-by-Step Migration

### Step 1: Update Your Code

```bash
cd offlinebrew
git pull origin main
```

### Step 2: Test Compatibility

Run the API compatibility test:

```bash
brew ruby mirror/test/test_api_compatibility.rb
```

All tests should pass.

### Step 3: Choose Your Migration Path

See "Migration Paths" above and choose based on your needs.

### Step 4: Verify Everything Works

Test a formula install:
```bash
ruby mirror/bin/brew-offline-install wget
```

Test a cask install (if you added cask support):
```bash
ruby mirror/bin/brew-offline-install --cask firefox
```

### Step 5: Update Your Procedures

Update any scripts or documentation to:
- Use new CLI options (--casks, --taps, etc.)
- Handle both formula and cask installations
- Use brew-mirror-verify for quality checks

## Compatibility Matrix

| Old Version | New Version | Compatible? | Notes |
|-------------|-------------|-------------|-------|
| 1.x mirror  | 2.0 tools   | ✅ Yes      | Old mirrors work with new tools |
| 2.0 mirror  | 1.x tools   | ⚠️ Partial | New config won't break old tools, but they won't understand taps |
| 1.x config  | 2.0 tools   | ✅ Yes      | Auto-upgraded |
| 2.0 config  | 1.x tools   | ⚠️ Partial | Will use legacy "commit" field |

## Rollback Plan

If you need to roll back:

```bash
# Restore old mirror
mv /path/to/old-mirror.backup /path/to/old-mirror

# Revert code
cd offlinebrew
git checkout v1.0.0

# Old tools will work with old mirror
```

## Common Migration Issues

### Issue: "Tap not found: homebrew/homebrew-cask"

**Solution:** Install the cask tap:
```bash
brew tap homebrew/cask
```

### Issue: Old mirror missing cask support

**Solution:** Either recreate mirror or use --update to add casks:
```bash
brew ruby bin/brew-mirror -d /path/to/mirror --casks firefox --update
```

### Issue: Scripts break with new options

**Solution:** Old options still work! New options are additions, not replacements.

```bash
# Old way - still works
brew ruby bin/brew-mirror -d ./mirror -f wget

# New way - adds features
brew ruby bin/brew-mirror -d ./mirror -f wget --casks firefox
```

## FAQ

**Q: Do I need to recreate my entire mirror?**

A: No! Old mirrors work fine. Only recreate if you want cask support.

**Q: Will my old configs break?**

A: No. The new tools read old config formats.

**Q: Can I install casks from an old mirror?**

A: No. Old mirrors don't include cask data. Use --update to add casks.

**Q: How much space do casks need?**

A: Plan for ~50-100GB for common casks. Individual casks range from 50MB to 2GB.

**Q: What if I don't want casks?**

A: Don't use --casks! The tools work the same as before without it.

## Getting Help

- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Run with `HOMEBREW_VERBOSE=1` for debug output
- Open an issue with:
  - Old version used
  - New version used
  - Error messages
  - Steps to reproduce

## Next Steps

After migration:
1. Read the updated [README.md](README.md)
2. Check out [mirror/README.md](mirror/README.md) for new features
3. Try `brew-mirror-verify` to check mirror integrity
4. Explore incremental updates with --update
5. Generate HTML reports with manifests

Welcome to offlinebrew 2.0! 🎉
```

### Step 2: Add Migration Script

Create `scripts/migrate_config.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Migrate old config format to new format
require "json"

config_file = ARGV.first || abort("Usage: ruby migrate_config.rb <config.json>")
abort "File not found: #{config_file}" unless File.exist?(config_file)

config = JSON.parse(File.read(config_file))

# Check if already new format
if config["taps"]
  puts "✓ Config already in new format"
  exit 0
end

# Check if old format
unless config["commit"]
  puts "⚠ Config doesn't look like old or new format"
  puts "Cannot migrate"
  exit 1
end

# Migrate
new_config = {
  "taps" => {
    "homebrew/homebrew-core" => {
      "commit" => config["commit"],
      "type" => "formula",
    },
  },
  "stamp" => config["stamp"],
  "cache" => config["cache"],
  "baseurl" => config["baseurl"],
  # Keep old fields for backward compat
  "commit" => config["commit"],
}

# Backup old config
backup_file = "#{config_file}.backup"
FileUtils.cp(config_file, backup_file)
puts "✓ Backed up to: #{backup_file}"

# Write new config
File.write(config_file, JSON.pretty_generate(new_config))
puts "✓ Migrated config to new format"
puts ""
puts "New config:"
puts JSON.pretty_generate(new_config)
```

Make executable:
```bash
chmod +x scripts/migrate_config.rb
```

### Step 3: Add Migration Check to Tools

In `mirror/bin/brew-offline-install`, add:

```ruby
# Check for old config format and warn
if config[:commit] && !config[:taps]
  opoo "Using old config format (still works, but consider updating)"
  opoo "Run: ruby scripts/migrate_config.rb ~/.offlinebrew/config.json"
end
```

## Testing

### Test 1: Old Config Works

Create an old-format config:
```bash
mkdir -p ~/.offlinebrew
cat > ~/.offlinebrew/config.json << 'EOF'
{
  "commit": "abc123",
  "stamp": "1699999999",
  "cache": "/tmp/test",
  "baseurl": "http://localhost:8000"
}
EOF
```

Verify tools accept it without error.

### Test 2: Migration Script

```bash
ruby scripts/migrate_config.rb ~/.offlinebrew/config.json
cat ~/.offlinebrew/config.json
```

Should show new format.

### Test 3: Read the Migration Guide

Read through MIGRATION.md and verify:
- All scenarios covered
- Examples work
- No broken links
- Clear instructions

## Acceptance Criteria

✅ Done when:
1. MIGRATION.md created and comprehensive
2. All migration scenarios documented
3. Migration script works
4. Backward compatibility verified
5. FAQ answers common questions
6. Clear rollback plan provided

## Commit Message

```bash
git add MIGRATION.md scripts/migrate_config.rb mirror/bin/brew-offline-install
git commit -m "Task 5.3: Add migration guide and tools

- Create comprehensive migration guide
- Document all migration scenarios
- Add config migration script
- Ensure backward compatibility
- Add FAQ for common issues
- Provide rollback instructions
- Test old configs work with new tools"
```

## Next Steps

🎉 **You're done!** All tasks completed!

Final checklist:
- [ ] Run full test suite: `./mirror/test/run_tests.sh`
- [ ] Create a test mirror with casks
- [ ] Install from test mirror
- [ ] Read all documentation
- [ ] Commit all changes
- [ ] Create release tag

Congratulations on completing the offlinebrew modernization! 🚀
