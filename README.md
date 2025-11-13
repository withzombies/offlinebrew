# offlinebrew

Create offline mirrors of Homebrew packages for air-gapped and low-connectivity environments.

Perfect for secure networks, remote locations, CI/CD pipelines, and reproducible builds.

## Features

- ✅ **Full Homebrew support** - Mirror both formulas (CLI tools) and casks (GUI apps)
- ✅ **Multi-tap support** - Include core, cask, fonts, and custom taps
- ✅ **Incremental updates** - Skip unchanged packages (10-100x faster!)
- ✅ **Point-in-time snapshots** - Reproducible builds with commit pinning
- ✅ **Integrity verification** - Validate mirrors with checksums and completeness checks
- ✅ **Universal compatibility** - Works on Intel and Apple Silicon Macs
- ✅ **Beautiful reports** - HTML and JSON manifests of mirror contents
- ✅ **Production-ready** - Security hardening, error handling, and comprehensive tests

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/withzombies/offlinebrew.git
cd offlinebrew

# Add to PATH (optional but recommended)
export PATH="$(pwd)/bin:$PATH"
```

### 1. Create a Mirror (on a machine with internet)

```bash
# Mirror specific packages
brew offline mirror \
  -d ~/brew-mirror \
  -f wget,jq,htop \
  --casks firefox,visual-studio-code \
  -s 1

# Verify the mirror
brew offline verify ~/brew-mirror

# View manifest
open ~/brew-mirror/manifest.html
```

### 2. Serve the Mirror

```bash
cd ~/brew-mirror
python3 -m http.server 8000
```

### 3. Install from Mirror (on offline machine)

```bash
# Configure client (one-time setup)
mkdir -p ~/.offlinebrew
echo '{"baseurl": "http://mirror-server:8000"}' > ~/.offlinebrew/config.json

# Install packages
brew offline install wget
brew offline install jq htop
brew offline install --cask firefox
```

That's it! 🎉

## Documentation

### Getting Started
- **[Getting Started Guide](GETTING_STARTED.md)** ⭐ **Start here!** - Complete walkthrough with examples
- **[Installation Guide](INSTALLATION.md)** - Detailed setup instructions
- **[Mirror Usage Guide](mirror/README.md)** - Advanced mirror features

### Reference
- **[Changelog](CHANGELOG.md)** - Version history and new features
- **[Migration Guide](MIGRATION.md)** - Upgrading from v1.x to v2.0
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions

## Common Use Cases

- **Air-gapped networks** - Security-critical environments without internet access
- **Remote locations** - Field operations with limited or expensive connectivity
- **CI/CD pipelines** - Reproducible builds with pinned package versions
- **Disaster recovery** - Local package repositories for emergency situations
- **Development teams** - Consistent environments across all team members
- **Compliance** - Auditable package sources and versions

## How It Works

Offlinebrew creates a **point-in-time snapshot** of Homebrew packages:

1. **Mirror Creation** - Downloads packages and their dependencies from Homebrew
2. **Version Pinning** - Records exact Git commits of Homebrew taps
3. **URL Mapping** - Creates a mapping of URLs to local files
4. **HTTP Serving** - Serves the mirror via a simple HTTP server
5. **URL Rewriting** - Client shims redirect package downloads to your mirror

The result: Homebrew works normally, but all downloads come from your local mirror!

## Requirements

### System Requirements
- **OS**: macOS 10.15+ or Linux with Homebrew
- **Architecture**: Intel (x86_64) or Apple Silicon (arm64)
- **Ruby**: 2.6+ (included with macOS)
- **Python**: 3.x (for serving mirrors)
- **Disk**: 1-100GB depending on mirror size

### Software Requirements
- Homebrew (latest version recommended)
- Git
- curl (included with macOS)

See [INSTALLATION.md](INSTALLATION.md) for detailed requirements.

## Advanced Features

### Incremental Updates

Update existing mirrors without re-downloading everything:

```bash
brew offline mirror -d ~/brew-mirror --update --prune
```

10-100x faster than full mirror updates!

### Multi-Tap Support

Include fonts, drivers, and custom taps:

```bash
brew offline mirror -d ~/brew-mirror \
  --taps core,cask,fonts \
  --casks font-fira-code,font-jetbrains-mono
```

### Mirror Verification

Ensure mirror integrity:

```bash
brew offline verify ~/brew-mirror
brew offline verify --verbose ~/brew-mirror
```

### Beautiful Reports

Every mirror includes:
- `manifest.json` - Machine-readable package list
- `manifest.html` - Beautiful HTML report with statistics

## Architecture

Offlinebrew uses a **mirror-based approach** that provides full-featured offline Homebrew support:

- ✅ URL rewriting and redirection
- ✅ Supports both formulas and casks
- ✅ Point-in-time snapshots
- ✅ Incremental updates
- ✅ Mirror verification
- ✅ Manifest generation

All functionality is in the `mirror/` directory.

## Version 2.0 Highlights

🎉 **Major release with comprehensive improvements!**

- **Full cask support** - Install GUI apps, fonts, drivers
- **Multi-tap configuration** - Any Homebrew tap, not just core
- **Incremental updates** - 10-100x faster mirror updates
- **Mirror verification** - Validate mirror integrity
- **Beautiful manifests** - JSON and HTML reports
- **Apple Silicon native** - Full M1/M2/M3 support
- **Security hardening** - Protection against injection attacks
- **Comprehensive tests** - 39+ integration tests

See [CHANGELOG.md](CHANGELOG.md) for complete details.

## Contributing

Contributions are welcome! Here's how you can help:

- **Report bugs** - Open an issue with details and reproduction steps
- **Suggest features** - Discuss improvements and new capabilities
- **Submit PRs** - Code contributions are appreciated
- **Improve docs** - Help make the documentation clearer
- **Share feedback** - Let us know how you're using offlinebrew

See [GitHub Issues](https://github.com/withzombies/offlinebrew/issues) to get started.

## Support

### Getting Help

- **Documentation**: Start with [GETTING_STARTED.md](GETTING_STARTED.md)
- **Common Issues**: Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Questions**: Open a [GitHub Issue](https://github.com/withzombies/offlinebrew/issues)

### Debug Mode

Enable detailed logging:

```bash
# Offlinebrew debug output
export BREW_OFFLINE_DEBUG=1
brew offline mirror -d ~/mirror -f wget

# Homebrew verbose output
export HOMEBREW_VERBOSE=1
brew offline install wget
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

Built for the Homebrew community with ❤️

- **Homebrew** - The amazing package manager for macOS
- **Contributors** - Everyone who has helped improve offlinebrew
- **Users** - Thank you for using offlinebrew in your environments
