# Task: Implement Bottle Downloader for Formulas

## Goal

Download and mirror Homebrew bottles (precompiled binaries) for formulas. This enables <10 second formula installations versus hours for source builds.

## Context

Completed bd-vam: API JSON generator successfully creates formula definitions with bottle metadata.

Current gap: Mirror has API JSON pointing to bottles, but no bottles are actually downloaded. When brew-offline-install runs, it will fail to find bottles in cache.

## Implementation

### 1. Study existing patterns

**Similar code to review:**
- mirror/bin/brew-mirror:600-700 - Resource download loop (how we download sources)
- mirror/bin/brew-mirror:700-900 - Cask download (how we handle binary downloads)
- Formula#bottle method - Access bottle metadata
- Formula#bottle.checksums - Platform-specific SHA256s and URLs

**Research:**
- BOTTLES_IMPLEMENTATION_GUIDE.md - Detailed bottle structure
- BOTTLES_AND_GIT_QUICK_REFERENCE.md - Quick reference

### 2. Write tests first (TDD)

**Create: mirror/test/lib/test_bottle_downloader.rb**

Test cases:
- `test_extracts_bottle_url_for_platform` - Gets correct ARM64 Sonoma URL
- `test_downloads_bottle_to_bottles_directory` - Saves to bottles/ subdirectory
- `test_verifies_bottle_sha256` - Fails on checksum mismatch
- `test_skips_formula_without_bottles` - No error when formula lacks bottles
- `test_updates_urlmap_with_bottle_urls` - Adds bottle mappings to urlmap.json
- `test_intel_bottles_with_flag` - Downloads x86_64 when --include-intel passed

**Test formulas:** jq (has bottles), oniguruma (has bottles)

### 3. Implementation checklist

**Create: mirror/lib/bottle_downloader.rb**

- [ ] BottleDownloader class with download_all(formulas, options) method
- [ ] extract_bottle_url(formula, platform) - Get URL for platform
- [ ] download_bottle(formula, platform, output_dir) - Download single bottle
- [ ] supported_platforms(options) - Determine which platforms to download
- [ ] update_urlmap(formula, bottle_path, urlmap_hash) - Add bottle mapping

**File locations:**
- mirror/lib/bottle_downloader.rb - Main implementation
- mirror/test/lib/test_bottle_downloader.rb - Test suite

### 4. Integration with brew-mirror

**Modify: mirror/bin/brew-mirror (after formula resource collection, around line 600)**

### 5. Platform detection

**Default:** Detect current platform (arm64_sonoma, etc.)
**With --include-intel:** Download both ARM64 and Intel bottles

## Success Criteria

- [ ] Tests pass: ruby mirror/test/lib/test_bottle_downloader.rb
- [ ] brew-mirror -f jq downloads jq bottle to bottles/ directory
- [ ] Bottle filename matches: jq--1.8.1.arm64_sonoma.bottle.tar.gz
- [ ] SHA256 verification passes for downloaded bottles
- [ ] urlmap.json contains bottle URL mappings
- [ ] Formulas without bottles don't cause errors
- [ ] Pre-commit hooks pass
