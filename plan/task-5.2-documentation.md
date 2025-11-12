# Task 5.2: Update Documentation

## Objective

Update all documentation to reflect new features (cask support, multi-tap, etc.).

## Prerequisites

- All previous tasks completed

## Implementation Steps

### Step 1: Update Main README

Edit `README.md`:

```markdown
# offlinebrew

Offlinebrew is a collection of tools for running [Homebrew](https://brew.sh) in offline environments.

## Features

- ✓ Mirror formulas from homebrew-core
- ✓ Mirror casks from homebrew-cask (GUI apps, fonts, etc.)
- ✓ Support for multiple taps
- ✓ Offline installation of formulas and casks
- ✓ Point-in-time snapshots with commit pinning
- ✓ Incremental updates
- ✓ Mirror verification
- ✓ Works on Intel and Apple Silicon Macs

## Quick Start

### 1. Create a Mirror (on a machine with internet)

```bash
# Mirror some popular packages
brew ruby mirror/bin/brew-mirror \
  -d /path/to/mirror \
  -f wget,jq,htop \
  --casks firefox,visual-studio-code \
  -s 1

# Verify the mirror
brew ruby mirror/bin/brew-mirror-verify /path/to/mirror

# Serve the mirror
cd /path/to/mirror
python3 -m http.server 8000
```

### 2. Install from Mirror (on offline machine)

```bash
# Configure client
mkdir -p ~/.offlinebrew
echo '{"baseurl": "http://mirror-server:8000"}' > ~/.offlinebrew/config.json

# Install a formula
ruby mirror/bin/brew-offline-install wget

# Install a cask
ruby mirror/bin/brew-offline-install --cask firefox
```

## Documentation

- [Mirror Usage Guide](mirror/README.md) - Detailed mirror documentation
- [Migration Guide](MIGRATION.md) - Upgrading from old versions
- [Architecture](docs/ARCHITECTURE.md) - Technical design

## Requirements

- macOS (Intel or Apple Silicon) or Linux with Homebrew
- Ruby 2.6+ (included with macOS)
- 100GB+ disk space for full mirror
- Python 3 (for serving mirror)

## Supported Platforms

- macOS 10.15+ (Intel)
- macOS 11.0+ (Apple Silicon)
- Linux with Homebrew (experimental)

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

## License

MIT License - see [LICENSE](LICENSE) for details.
```

### Step 2: Update Mirror README

Edit `mirror/README.md`:

```markdown
# Offlinebrew Mirror

The mirror-based approach uses URL rewriting to redirect all Homebrew downloads to a local HTTP server.

## Tools

### brew-mirror

Creates an offline mirror of Homebrew packages.

**Usage:**
```bash
brew ruby mirror/bin/brew-mirror [options]
```

**Options:**
- `-d, --directory DIR` - Output directory (required)
- `-f, --formulae f1,f2` - Mirror specific formulae only
- `--casks c1,c2` - Mirror specific casks only
- `--taps tap1,tap2` - Taps to mirror (default: core,cask)
- `-s, --sleep SECS` - Sleep between downloads (default: 0.5)
- `-c, --config-only` - Write config without downloading
- `--update` - Update existing mirror (skip unchanged)
- `--prune` - Remove old versions when updating
- `--verify` - Verify mirror after creation

**Examples:**
```bash
# Mirror everything (requires ~100GB)
brew ruby bin/brew-mirror -d /Volumes/USB/brew-mirror -s 1

# Mirror specific packages
brew ruby bin/brew-mirror -d ./mirror -f wget,jq --casks firefox

# Update existing mirror
brew ruby bin/brew-mirror -d ./mirror --update --prune

# Mirror with custom taps
brew ruby bin/brew-mirror -d ./mirror --taps homebrew/homebrew-core,homebrew/homebrew-cask-fonts
```

### brew-offline-install

Installs packages from the offline mirror.

**Usage:**
```bash
ruby mirror/bin/brew-offline-install [--cask] <package>
```

**Examples:**
```bash
# Install formula
ruby bin/brew-offline-install wget

# Install cask
ruby bin/brew-offline-install --cask firefox

# Install multiple
ruby bin/brew-offline-install jq htop
```

### brew-mirror-verify

Verifies mirror integrity.

**Usage:**
```bash
brew ruby mirror/bin/brew-mirror-verify <mirror-directory>
```

### brew-mirror-prune

Removes orphaned files from mirror.

**Usage:**
```bash
brew ruby mirror/bin/brew-mirror-prune <mirror-directory>
```

## Configuration

Client configuration: `~/.offlinebrew/config.json`

```json
{
  "baseurl": "http://mirror-server:8000"
}
```

Mirror configuration: `<mirror>/config.json` (auto-generated)

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
  "stamp": "1699999999",
  "cache": "/path/to/mirror",
  "baseurl": "http://localhost:8000"
}
```

## Serving the Mirror

Any HTTP server works:

```bash
# Python (built-in)
cd /path/to/mirror
python3 -m http.server 8000

# Nginx
# Add to nginx.conf:
server {
  listen 8000;
  root /path/to/mirror;
  autoindex on;
}

# Apache
# Configure DocumentRoot to mirror directory
```

## Troubleshooting

See [TROUBLESHOOTING.md](../TROUBLESHOOTING.md)

## Architecture

See [ARCHITECTURE.md](../docs/ARCHITECTURE.md) for technical details.
```

### Step 3: Create CHANGELOG

Create `CHANGELOG.md`:

```markdown
# Changelog

All notable changes to offlinebrew will be documented here.

## [2.0.0] - 2025-11-11

### Added
- Full cask support (GUI applications, fonts, etc.)
- Multi-tap configuration with --taps option
- Incremental mirror updates with --update
- Mirror verification tool (brew-mirror-verify)
- Manifest generation (JSON and HTML)
- Deterministic Git repository identifiers
- Support for Apple Silicon Macs
- Cross-platform home directory detection
- URL normalization for better cask matching
- Comprehensive test suite
- Download retry logic with exponential backoff
- Container format verification
- Progress tracking for large downloads

### Changed
- Config format now uses taps hash (backward compatible)
- Improved error messages and validation
- Better handling of download failures
- Enhanced debugging with BREW_OFFLINE_DEBUG

### Fixed
- Git UUID collision causing duplicate repos
- Hardcoded /usr/local/Homebrew paths
- Hardcoded /Users home directory
- URL matching for casks with query parameters
- Homebrew API compatibility issues

## [1.0.0] - 2020-03-01

### Added
- Initial release
- Formula mirroring from homebrew-core
- Cache-based approach
- Basic offline installation

[2.0.0]: https://github.com/user/offlinebrew/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/user/offlinebrew/releases/tag/v1.0.0
```

### Step 4: Create Troubleshooting Guide

Create `TROUBLESHOOTING.md`:

```markdown
# Troubleshooting Guide

Common issues and solutions.

## Mirror Creation Issues

### Error: "homebrew-core tap not found"

**Solution:** Update Homebrew:
```bash
brew update
```

### Error: "No cask with this name exists"

**Solution:** Check cask name:
```bash
brew search --cask firefox
```

### Mirror takes forever / runs out of disk space

**Solution:** Start with specific packages:
```bash
brew ruby bin/brew-mirror -d ./mirror -f wget,jq --casks firefox
```

## Installation Issues

### Error: "Couldn't read config or urlmap"

**Solution:** Create config:
```bash
mkdir -p ~/.offlinebrew
echo '{"baseurl": "http://mirror:8000"}' > ~/.offlinebrew/config.json
```

### Downloads still go to internet

**Solution:** Check shims are in PATH:
```bash
export BREW_OFFLINE_DEBUG=1
ruby bin/brew-offline-install wget
# Look for "[brew-offline-curl]" messages
```

### Cask installation fails

**Solution:** Verify cask is in mirror:
```bash
brew ruby bin/brew-mirror-verify /path/to/mirror
```

## Server Issues

### Port 8000 already in use

**Solution:** Use different port:
```bash
python3 -m http.server 8080
# Update baseurl in config.json
```

### Slow downloads from mirror

**Solution:** Use a faster HTTP server (nginx, apache) instead of Python's http.server.

## Getting Help

1. Enable verbose mode: `export HOMEBREW_VERBOSE=1`
2. Enable debug mode: `export BREW_OFFLINE_DEBUG=1`
3. Check the logs
4. Open an issue with full output
```

## Testing

Read through all documentation to check for:
- Typos
- Broken links
- Incorrect commands
- Missing information

## Acceptance Criteria

✅ Done when:
1. README.md updated with new features
2. mirror/README.md comprehensive
3. CHANGELOG.md created
4. TROUBLESHOOTING.md created
5. All commands tested and verified
6. No broken links

## Commit Message

```bash
git add README.md mirror/README.md CHANGELOG.md TROUBLESHOOTING.md
git commit -m "Task 5.2: Update documentation for v2.0

- Rewrite README with cask support examples
- Update mirror/README with all new options
- Create CHANGELOG documenting all changes
- Add comprehensive troubleshooting guide
- Document new configuration format
- Add examples for all new features"
```

## Next Steps

Proceed to **Task 5.3: Create Migration Guide** (Final task!)
