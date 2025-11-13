# Getting Started with Offlinebrew

This guide walks you through setting up and using Offlinebrew for offline Homebrew package installation.

## What is Offlinebrew?

Offlinebrew lets you create a complete offline mirror of Homebrew packages (formulas and casks), then install them on machines without internet access. Perfect for air-gapped environments, locations with poor connectivity, or situations where you need reproducible builds.

## Quick Overview

The process has three main steps:

1. **Create a mirror** (on a machine with internet) - Download packages and their dependencies
2. **Serve the mirror** (on a local network) - Make the mirror accessible via HTTP
3. **Install packages** (on offline machines) - Install from the mirror instead of the internet

## Prerequisites

### Online Machine (for creating mirror)
- macOS 10.15+ or Linux with Homebrew installed
- 100GB+ free disk space (for full mirror) or 1-10GB (for specific packages)
- Internet connection
- Ruby 2.6+ (included with macOS)
- Python 3 (for serving mirror)

### Offline Machine (for installations)
- macOS 10.15+ or Linux with Homebrew installed
- Network access to mirror server
- Ruby 2.6+ (included with macOS)

## Installation

### Step 1: Clone Offlinebrew

On your **online machine**, clone this repository:

```bash
git clone https://github.com/withzombies/offlinebrew.git
cd offlinebrew
```

### Step 2: Add to PATH (Optional but Recommended)

To use the convenient `brew offline` command, add offlinebrew's `bin/` directory to your PATH:

```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="/path/to/offlinebrew/bin:$PATH"

# Or create a symlink (requires sudo)
sudo ln -s /path/to/offlinebrew/bin/brew-offline /usr/local/bin/brew-offline
```

After adding to PATH, reload your shell:
```bash
source ~/.bashrc  # or source ~/.zshrc
```

Now you can use `brew offline` commands!

## Usage

### Part 1: Create a Mirror (Online Machine)

#### Option A: Mirror Specific Packages (Recommended for Getting Started)

Start with a small mirror of specific packages:

```bash
brew offline mirror \
  -d ~/brew-mirror \
  -f wget,jq,htop \
  --with-deps \
  --casks firefox,visual-studio-code \
  -s 1
```

This creates a mirror with:
- 3 command-line tools (wget, jq, htop)
- **All their dependencies** (automatically resolved with `--with-deps`)
- 2 GUI applications (Firefox, Visual Studio Code)
- 1 second delay between downloads (polite to servers)

**Expected**: ~500MB download, takes 5-10 minutes

**Why `--with-deps`?** Without this flag, only the specified packages are mirrored. On an offline machine, installations would fail due to missing dependencies. The `--with-deps` flag automatically resolves and includes all required dependencies.

#### Option B: Mirror Everything (for Production Use)

For a complete mirror of all Homebrew packages:

```bash
brew offline mirror \
  -d /Volumes/ExternalDrive/brew-mirror \
  -s 1
```

**Expected**: ~100GB download, takes several hours

#### Option C: Mirror with Multiple Taps

Include fonts and other specialized packages:

```bash
brew offline mirror \
  -d ~/brew-mirror \
  --taps core,cask,fonts \
  -f wget,jq \
  --casks font-fira-code,font-jetbrains-mono \
  -s 1
```

#### Understanding Mirror Options

- `-d, --directory` - Where to store the mirror (required)
- `-f, --formulae` - Specific command-line tools to mirror (comma-separated)
- `--casks` - Specific GUI apps to mirror (comma-separated)
- `--with-deps` - ⭐ **Automatically resolve and mirror all dependencies** (highly recommended!)
- `--include-build` - Include build dependencies (requires `--with-deps`)
- `--taps` - Which Homebrew taps to include (default: core,cask)
  - Available shortcuts: `core`, `cask`, `fonts`, `versions`, `drivers`
- `-s, --sleep` - Seconds to wait between downloads (default: 0.5, recommended: 1)
- `-c, --config-only` - Create configuration without downloading (for testing)
- `--update` - Update existing mirror (skip unchanged packages, 10-100x faster!)
- `--verify` - Verify mirror integrity after creation

### Part 2: Verify the Mirror (Optional but Recommended)

Check that your mirror is complete and valid:

```bash
brew offline verify ~/brew-mirror
```

Expected output:
```
==> Verifying mirror: /Users/you/brew-mirror
✓ Configuration file valid
✓ URL mapping file valid
✓ All files present
✓ No orphaned files

Mirror Statistics:
  Formulae: 3
  Casks: 2
  Total Files: 5
  Total Size: 487.3 MB

Mirror is valid!
```

For detailed verification:
```bash
brew offline verify --verbose ~/brew-mirror
```

### Part 3: Serve the Mirror

Use Python's built-in HTTP server to make the mirror accessible:

```bash
cd ~/brew-mirror
python3 -m http.server 8000
```

The mirror is now available at `http://localhost:8000`

**For other machines on your network:**
1. Find your IP address: `ifconfig | grep "inet "` (look for 192.168.x.x or 10.x.x.x)
2. The mirror URL will be: `http://YOUR_IP:8000`
3. Keep the terminal window open while serving

**For production use**, consider using a proper web server like nginx or Apache.

### Part 4: Configure Offline Machines

On each **offline machine** that will install from the mirror:

#### Step 1: Copy Offlinebrew to Offline Machine

Transfer the offlinebrew directory to your offline machine:
```bash
# Option 1: USB drive
cp -r offlinebrew /Volumes/USB/
# Then copy from USB to offline machine

# Option 2: scp (if machines can communicate)
scp -r offlinebrew user@offline-machine:/path/to/offlinebrew

# Option 3: Git clone (if offline machine has network to your server)
git clone http://your-server/offlinebrew.git
```

#### Step 2: Create Configuration

On the offline machine, create the configuration file:

```bash
mkdir -p ~/.offlinebrew
cat > ~/.offlinebrew/config.json <<EOF
{
  "baseurl": "http://192.168.1.100:8000"
}
EOF
```

Replace `192.168.1.100:8000` with your mirror server's IP and port.

#### Step 3: Add to PATH (Optional)

Same as on the online machine:
```bash
export PATH="/path/to/offlinebrew/bin:$PATH"
```

### Part 5: Install Packages from Mirror

Now you can install packages on the offline machine!

#### Install a Command-Line Tool

```bash
brew offline install wget
```

#### Install a GUI Application (Cask)

```bash
brew offline install --cask firefox
```

#### Install Multiple Packages

```bash
brew offline install jq htop wget
```

#### What Happens During Installation?

1. The install command reads `~/.offlinebrew/config.json` to find the mirror
2. It resets Homebrew taps to the versions captured in the mirror
3. It uses URL shims to redirect all downloads to your mirror
4. Homebrew installs the package normally, but from your mirror
5. After installation, taps are restored to their original state

## Updating Your Mirror

As Homebrew packages are updated, you can refresh your mirror:

### Update Incrementally (Fast!)

Only download packages that have changed:

```bash
brew offline mirror -d ~/brew-mirror --update --prune
```

The `--update` flag skips unchanged packages (10-100x faster!), and `--prune` reports which old versions were replaced.

### Add New Packages to Existing Mirror

```bash
brew offline mirror \
  -d ~/brew-mirror \
  -f tree,ncdu \
  --casks slack \
  --update
```

This adds new packages without re-downloading existing ones.

## Complete Example Workflow

Here's a complete example from start to finish:

### On Online Machine

```bash
# 1. Clone offlinebrew
git clone https://github.com/withzombies/offlinebrew.git
cd offlinebrew

# 2. Add to PATH
export PATH="$(pwd)/bin:$PATH"

# 3. Create mirror with specific packages
brew offline mirror \
  -d ~/my-mirror \
  -f wget,jq,htop,tree \
  --casks firefox,visual-studio-code \
  -s 1 \
  --verify

# 4. Verify mirror (already done by --verify flag)
brew offline verify ~/my-mirror

# 5. Check the manifest
open ~/my-mirror/manifest.html
# Or: cat ~/my-mirror/manifest.json

# 6. Serve mirror
cd ~/my-mirror
python3 -m http.server 8000
```

### On Offline Machine

```bash
# 1. Copy offlinebrew to offline machine (via USB, scp, etc.)
cd /path/to/offlinebrew

# 2. Add to PATH
export PATH="$(pwd)/bin:$PATH"

# 3. Configure mirror location
mkdir -p ~/.offlinebrew
echo '{"baseurl": "http://192.168.1.100:8000"}' > ~/.offlinebrew/config.json

# 4. Install packages
brew offline install wget
brew offline install jq htop
brew offline install --cask firefox
brew offline install --cask visual-studio-code

# 5. Verify installations
wget --version
jq --version
which firefox
```

## Troubleshooting

### "Command not found: brew"

Homebrew is not installed. Install it first:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### "Mirror verification failed"

Check specific errors with verbose mode:
```bash
brew offline verify --verbose ~/brew-mirror
```

Common issues:
- Missing files: Re-run mirror command
- Corrupted downloads: Delete mirror and recreate
- Network interruption: Use `--update` to resume

### "Cannot find mirror at http://..."

1. Check mirror server is running: `curl http://192.168.1.100:8000/config.json`
2. Check firewall settings on server machine
3. Verify IP address in `~/.offlinebrew/config.json`
4. Try from server machine first: `curl http://localhost:8000/config.json`

### "Package not found in mirror"

The package wasn't included when creating the mirror. Add it:
```bash
brew offline mirror -d ~/brew-mirror -f missing-package --update
```

### Installation fails with "checksum mismatch"

The package version in the mirror doesn't match what Homebrew expects:
1. Update the mirror: `brew offline mirror -d ~/brew-mirror --update`
2. Verify the mirror: `brew offline verify ~/brew-mirror`
3. Try installation again

### For more help

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed solutions to common issues.

## Next Steps

- **Production deployment**: Set up nginx/Apache for better performance
- **Automation**: Schedule mirror updates with cron/launchd
- **CI/CD**: Use offlinebrew in build pipelines
- **Multiple mirrors**: Create specialized mirrors for different teams

## Advanced Topics

### Mirror Size Management

Control mirror size by being selective:

```bash
# Minimal mirror (formulas only, no casks)
brew offline mirror -d ~/mirror-small --taps core -f wget,jq,curl

# Medium mirror (common packages)
brew offline mirror -d ~/mirror-medium -f wget,jq,curl,htop,tree --casks firefox

# Large mirror (everything)
brew offline mirror -d ~/mirror-full
```

### Point-in-Time Snapshots

Each mirror captures specific versions:
- Tap commits are recorded in `config.json`
- All packages are pinned to those versions
- Reproducible builds across all offline machines

To create a new snapshot:
```bash
brew update  # Get latest Homebrew versions
brew offline mirror -d ~/mirror-$(date +%Y-%m-%d) -f wget,jq
```

### Multi-Tap Support

Include packages from specialized taps:

```bash
# Include fonts
brew offline mirror -d ~/mirror --taps core,cask,fonts --casks font-fira-code

# Include version casks (older versions of apps)
brew offline mirror -d ~/mirror --taps core,cask,versions
```

Available tap shortcuts:
- `core` - Command-line tools (homebrew-core)
- `cask` - GUI applications (homebrew-cask)
- `fonts` - Fonts (homebrew-cask-fonts)
- `versions` - Alternative versions (homebrew-cask-versions)
- `drivers` - Hardware drivers (homebrew-cask-drivers)

### Custom Taps

Use full tap names for custom taps:

```bash
brew offline mirror -d ~/mirror --taps homebrew/homebrew-core,mycompany/homebrew-private
```

## FAQ

**Q: How much disk space do I need?**
A: Depends on what you mirror:
- Specific packages: 100MB - 10GB
- Common developer tools: 10-20GB
- Everything: ~100GB

**Q: Can I mirror only formulas or only casks?**
A: Yes! Use `--taps core` for formulas only, or `--taps cask` for casks only.

**Q: How often should I update my mirror?**
A: Depends on your needs:
- Security-critical: Weekly
- Development: Monthly
- Stable environments: Quarterly

**Q: Can I use this with Homebrew on Linux?**
A: Partially. Formula support is good, cask support is limited (casks are macOS-only).

**Q: Does this work with bottles (pre-compiled binaries)?**
A: Yes! Bottles are automatically included when available.

**Q: Can I mirror private/custom taps?**
A: Yes, use the full tap name with `--taps`.

**Q: What if my mirror is on a different port?**
A: Just update the `baseurl` in `~/.offlinebrew/config.json` to include the port.

## Summary

Offlinebrew makes offline Homebrew installation straightforward:

1. **Create**: `brew offline mirror -d /path -f wget,jq --casks firefox`
2. **Serve**: `python3 -m http.server 8000` (in mirror directory)
3. **Configure**: Set `baseurl` in `~/.offlinebrew/config.json`
4. **Install**: `brew offline install wget`

For more information, see the [README](README.md) and [mirror documentation](mirror/README.md).
