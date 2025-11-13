# Migration Guide: v1.x to v2.0

This guide helps you migrate from offlinebrew 1.x (formula-only) to 2.0 (with cask support and modern features).

## TL;DR

**Good news:** Your existing v1.x mirrors and configs still work! The new code is fully backward compatible.

**To add cask support:** Use `--update` to add casks without re-downloading formulas.

## What's Changed

### Breaking Changes

**None!** Version 2.0 is fully backward compatible. But you should know about these improvements:

| Aspect | v1.x | v2.0 | Compatible? |
|--------|------|------|-------------|
| Config format | `{"commit": "..."}` | `{"taps": {...}}` | ✅ Yes - auto-upgraded |
| Paths | Hardcoded `/usr/local` | Dynamic detection | ✅ Yes - works everywhere |
| Formulas | ✅ Supported | ✅ Supported | ✅ Yes |
| Casks | ❌ Not supported | ✅ Supported | ⚠️  Need to recreate or update |

### New Features in v2.0

- ✨ **Cask support** - Mirror and install GUI apps, fonts, drivers
- ✨ **Multi-tap configuration** - Support any Homebrew tap
- ✨ **Tap shortcuts** - Use `core` instead of `homebrew/homebrew-core`
- ✨ **Incremental updates** - 10-100x faster with `--update`
- ✨ **Mirror verification** - Validate integrity with `brew-mirror-verify`
- ✨ **Manifests** - JSON and HTML reports of mirror contents
- ✨ **Apple Silicon support** - Native M1/M2/M3 Mac support
- ✨ **Better error messages** - Clearer validation and debugging

## Migration Scenarios

Choose the scenario that matches your situation:

### Scenario 1: I have an existing v1.x mirror

#### Option A: Keep using it (no changes needed)

Your old mirror works perfectly with the new tools!

```bash
# This still works exactly as before
ruby mirror/bin/brew-offline-install wget
```

**When to choose this:**
- You only need formulas (no casks)
- Your mirror has everything you need
- You want zero downtime

#### Option B: Add casks without re-downloading everything

Use `--update` to add cask support incrementally:

```bash
# Add casks to existing mirror (formulas are skipped)
brew ruby mirror/bin/brew-mirror \
  -d /path/to/existing-mirror \
  --casks firefox,visual-studio-code \
  --update \
  -s 1
```

**When to choose this:**
- You want cask support
- You don't want to re-download formulas
- Your mirror is large

#### Option C: Start fresh with casks

Recreate the mirror with both formulas and casks:

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

**When to choose this:**
- You want a clean slate
- Your mirror is small
- You can afford the download time

### Scenario 2: I only have client configs (no mirror)

#### Nothing to do!

Your `~/.offlinebrew/config.json` still works:

```json
{
  "baseurl": "http://mirror-server:8000"
}
```

The tools auto-upgrade it when they fetch the remote config.

### Scenario 3: Fresh install

Follow the new Quick Start in [README.md](README.md):

```bash
# Create mirror
brew ruby mirror/bin/brew-mirror \
  -d ./mirror \
  -f wget \
  --casks firefox \
  -s 1

# Configure client
mkdir -p ~/.offlinebrew
echo '{"baseurl": "http://localhost:8000"}' > ~/.offlinebrew/config.json

# Install packages
ruby mirror/bin/brew-offline-install wget
ruby mirror/bin/brew-offline-install --cask firefox
```

## Step-by-Step Migration

### Step 1: Update Your Code

```bash
cd offlinebrew
git pull origin main
```

Or clone fresh:
```bash
git clone https://github.com/withzombies/offlinebrew.git
cd offlinebrew
```

### Step 2: Test Compatibility

Check that v2.0 works with your setup:

```bash
# Test API compatibility
brew ruby mirror/test/test_api_compatibility.rb

# Test with your existing mirror (if you have one)
ruby mirror/bin/brew-offline-install wget
```

All should work without errors.

### Step 3: Choose Your Migration Path

Based on the scenarios above:
- **Scenario 1A**: Continue using old mirror
- **Scenario 1B**: Add casks with `--update`
- **Scenario 1C**: Recreate mirror with casks

### Step 4: Verify Everything Works

**Test formula installation:**
```bash
ruby mirror/bin/brew-offline-install wget
wget --version
```

**Test cask installation (if you added cask support):**
```bash
ruby mirror/bin/brew-offline-install --cask firefox
# Firefox should install
```

**Verify mirror integrity:**
```bash
brew ruby mirror/bin/brew-mirror-verify /path/to/mirror
```

**View mirror contents:**
```bash
open /path/to/mirror/manifest.html
```

### Step 5: Update Your Procedures

Update any scripts or documentation to use new features:

**Before (v1.x):**
```bash
brew ruby bin/brew-mirror -d ./mirror -f wget
```

**After (v2.0, with new features):**
```bash
# Add casks
brew ruby bin/brew-mirror -d ./mirror -f wget --casks firefox

# Use shortcuts
brew ruby bin/brew-mirror -d ./mirror -f wget --taps core,cask

# Incremental updates
brew ruby bin/brew-mirror -d ./mirror -f wget --update --prune

# With verification
brew ruby bin/brew-mirror -d ./mirror -f wget --verify
```

## Config Format Migration

### Old Format (v1.x)

```json
{
  "commit": "abc123def456...",
  "stamp": "1699999999",
  "cache": "/path/to/mirror",
  "baseurl": "http://localhost:8000"
}
```

### New Format (v2.0)

```json
{
  "taps": {
    "homebrew/homebrew-core": {
      "commit": "abc123def456...",
      "type": "formula"
    },
    "homebrew/homebrew-cask": {
      "commit": "def456abc123...",
      "type": "cask"
    }
  },
  "stamp": "1699999999",
  "cache": "/path/to/mirror",
  "baseurl": "http://localhost:8000",
  "commit": "abc123def456..."  // kept for backward compat
}
```

### Automatic Migration

The tools automatically handle old configs:

1. **Reading:** Old configs are read and interpreted correctly
2. **Writing:** New mirrors use new format
3. **Compatibility:** Old "commit" field is preserved for v1.x tools

**You don't need to manually migrate!** But if you want to:

```bash
# Manual migration (optional)
ruby scripts/migrate_config.rb /path/to/mirror/config.json
```

## Compatibility Matrix

| Component | v1.x Tool | v2.0 Tool | Notes |
|-----------|-----------|-----------|-------|
| v1.x mirror | ✅ Works | ✅ Works | Full compatibility |
| v2.0 mirror | ⚠️  Partial | ✅ Works | v1.x won't understand taps/casks |
| v1.x config | ✅ Works | ✅ Works | Auto-upgraded |
| v2.0 config | ⚠️  Partial | ✅ Works | v1.x uses legacy "commit" field |

## Common Migration Issues

### Issue: "Tap not found: homebrew/homebrew-cask"

**Cause:** Cask tap not installed.

**Solution:**
```bash
brew tap homebrew/cask
```

### Issue: Old mirror missing casks

**Cause:** v1.x mirrors don't include cask data.

**Solution:** Add casks incrementally:
```bash
brew ruby bin/brew-mirror -d /path/to/mirror --casks firefox --update
```

### Issue: Scripts break with new options

**Cause:** Using new options that old scripts don't expect.

**Solution:** New options are additions, not replacements. Old syntax still works:

```bash
# Old way - still works
brew ruby bin/brew-mirror -d ./mirror -f wget

# New way - adds features
brew ruby bin/brew-mirror -d ./mirror -f wget --casks firefox --update
```

### Issue: "undefined method 'downloader'"

**Cause:** Old offlinebrew with new Homebrew.

**Solution:** Update offlinebrew to v2.0:
```bash
cd offlinebrew && git pull origin main
```

## Rollback Plan

If you need to roll back to v1.x:

```bash
# Restore old mirror (if you backed it up)
mv /path/to/old-mirror.backup /path/to/old-mirror

# Revert code
cd offlinebrew
git checkout v1.0.0

# Old tools work with old mirror
ruby mirror/bin/brew-offline-install wget
```

**Note:** You can't use v2.0 features (casks, multi-tap) with v1.x tools.

## FAQ

**Q: Do I need to recreate my entire mirror?**

A: No! Old mirrors work fine. Only recreate if you want cask support and don't want to use `--update`.

**Q: Will my old configs break?**

A: No. The new tools read old config formats perfectly.

**Q: Can I install casks from an old mirror?**

A: No. Old mirrors don't include cask data. Use `--update` to add casks.

**Q: How much space do casks need?**

A: Plan for 50-100GB for common casks. Individual casks range from 50MB to 2GB.

**Q: What if I don't want casks?**

A: Don't use `--casks`! The tools work exactly like v1.x without it.

**Q: Can v1.x and v2.0 tools coexist?**

A: Yes, but use one or the other for consistency.

**Q: Do I need to update client machines?**

A: No, if they only use `brew-offline-install`. But updating gives them access to cask installation.

**Q: What about Apple Silicon Macs?**

A: v2.0 natively supports Apple Silicon. v1.x had hardcoded Intel paths.

## Performance Improvements

Version 2.0 is significantly faster:

| Task | v1.x | v2.0 | Improvement |
|------|------|------|-------------|
| Full mirror | ~8 hours | ~8 hours | Same |
| Update mirror | N/A (not supported) | ~10 minutes | New feature |
| Install formula | ~30 seconds | ~30 seconds | Same |
| Install cask | N/A | ~60 seconds | New feature |
| Verification | N/A | ~10 seconds | New feature |

## Getting Help

- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Enable debug: `export BREW_OFFLINE_DEBUG=1`
- Open an issue with:
  - Old version used
  - New version used
  - Error messages
  - Steps to reproduce

## Next Steps After Migration

1. ✅ Verify everything works
2. 📖 Read the updated [README.md](README.md)
3. 🔍 Try `brew-mirror-verify` to check mirror integrity
4. ⚡ Explore incremental updates with `--update`
5. 📊 Check out `manifest.html` for mirror reports
6. 🎨 Install some casks!

Welcome to offlinebrew 2.0! 🎉
