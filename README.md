# offlinebrew

Offlinebrew is a collection of tools for running [Homebrew](https://brew.sh) in offline environments.

## Features

- ✅ Mirror formulas from homebrew-core
- ✅ Mirror casks from homebrew-cask (GUI apps, fonts, etc.)
- ✅ Support for multiple taps
- ✅ Offline installation of formulas and casks
- ✅ Point-in-time snapshots with commit pinning
- ✅ Incremental updates
- ✅ Mirror verification
- ✅ Works on Intel and Apple Silicon Macs

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

# View manifest
open /path/to/mirror/manifest.html
```

### 2. Serve the Mirror

```bash
cd /path/to/mirror
python3 -m http.server 8000
```

### 3. Install from Mirror (on offline machine)

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
- [Migration Guide](MIGRATION.md) - Upgrading from v1.x to v2.0
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues and solutions
- [Changelog](CHANGELOG.md) - Version history

## Requirements

- macOS (Intel or Apple Silicon) or Linux with Homebrew
- Ruby 2.6+ (included with macOS)
- 100GB+ disk space for full mirror
- Python 3 (for serving mirror)

## Supported Platforms

- macOS 10.15+ (Catalina and later) on Intel
- macOS 11.0+ (Big Sur and later) on Apple Silicon
- Linux with Homebrew (experimental)

## Architecture

### Two Approaches

**1. Cache-based** ([cache_based/](cache_based/))
- Initial proof-of-concept
- Spoofs `HOMEBREW_CACHE`
- Limited functionality

**2. Mirror-based** ([mirror/](mirror/)) ⭐ **Recommended**
- Full-featured approach
- URL rewriting and redirection
- Supports formulas and casks
- Point-in-time snapshots
- Incremental updates

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please open an issue or pull request.

## Support

- Report bugs: [GitHub Issues](https://github.com/withzombies/offlinebrew/issues)
- Enable debug mode: `export BREW_OFFLINE_DEBUG=1`
- Enable verbose mode: `export HOMEBREW_VERBOSE=1`
