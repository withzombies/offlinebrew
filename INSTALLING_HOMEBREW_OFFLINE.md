# Installing Homebrew on Offline Machines

This guide explains how to install Homebrew on machines without internet access.

## Overview

Homebrew's standard installation requires internet access. For offline machines, you need to:

1. Clone Homebrew on an online machine
2. Transfer it to the offline machine
3. Install manually

## Requirements

- **macOS 12.0+** on Apple Silicon (arm64)
- **Xcode Command Line Tools** (install on online machine, transfer if needed)
- **USB drive or network access** to transfer files

## Method 1: Clone and Transfer (Recommended)

### On Online Machine

```bash
# 1. Clone Homebrew repository
cd /tmp
git clone https://github.com/Homebrew/brew homebrew

# 2. Clone core tap (required for formulas)
mkdir -p homebrew/Library/Taps/homebrew
cd homebrew/Library/Taps/homebrew
git clone https://github.com/Homebrew/homebrew-core

# 3. Clone cask tap (if you need GUI apps)
git clone https://github.com/Homebrew/homebrew-cask

# 4. Go back to homebrew directory
cd /tmp/homebrew

# 5. Check size
du -sh .
# Expected: ~500MB

# 6. Copy to USB drive
cp -r /tmp/homebrew /Volumes/USB/
```

### On Offline Machine

```bash
# 1. Copy from USB to final location
sudo mkdir -p /opt/homebrew
sudo cp -r /Volumes/USB/homebrew/* /opt/homebrew/
sudo chown -R $(whoami):admin /opt/homebrew

# 2. Add to PATH
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# 3. Verify installation
brew --version
# Should show: Homebrew 5.x.x

# 4. Check taps
brew tap
# Should show:
# homebrew/core
# homebrew/cask (if installed)
```

## Method 2: Download Release Tarball

### On Online Machine

```bash
# 1. Download latest Homebrew release
curl -L https://github.com/Homebrew/brew/tarball/master -o homebrew.tar.gz

# 2. Download core tap
curl -L https://github.com/Homebrew/homebrew-core/tarball/master -o homebrew-core.tar.gz

# 3. Download cask tap (optional)
curl -L https://github.com/Homebrew/homebrew-cask/tarball/master -o homebrew-cask.tar.gz

# 4. Copy to USB
cp homebrew*.tar.gz /Volumes/USB/
```

### On Offline Machine

```bash
# 1. Create Homebrew directory
sudo mkdir -p /opt/homebrew
cd /opt/homebrew

# 2. Extract Homebrew
sudo tar -xzf /Volumes/USB/homebrew.tar.gz --strip-components=1

# 3. Create taps directory
sudo mkdir -p /opt/homebrew/Library/Taps/homebrew

# 4. Extract core tap
cd /opt/homebrew/Library/Taps/homebrew
sudo mkdir homebrew-core
cd homebrew-core
sudo tar -xzf /Volumes/USB/homebrew-core.tar.gz --strip-components=1

# 5. Extract cask tap (if needed)
cd /opt/homebrew/Library/Taps/homebrew
sudo mkdir homebrew-cask
cd homebrew-cask
sudo tar -xzf /Volumes/USB/homebrew-cask.tar.gz --strip-components=1

# 6. Fix permissions
sudo chown -R $(whoami):admin /opt/homebrew

# 7. Add to PATH
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# 8. Verify
brew --version
```

## Installing Xcode Command Line Tools Offline

Homebrew requires Xcode Command Line Tools. If not already installed:

### On Online Machine

```bash
# Check version needed
xcode-select --version

# Download from Apple Developer:
# 1. Visit https://developer.apple.com/download/all/
# 2. Search for "Command Line Tools for Xcode"
# 3. Download the .dmg for your macOS version
# 4. Copy to USB drive
```

### On Offline Machine

```bash
# 1. Mount the .dmg from USB
open /Volumes/USB/Command_Line_Tools_*.dmg

# 2. Install the package
sudo installer -pkg /Volumes/Command\ Line\ Tools/Command\ Line\ Tools.pkg -target /

# 3. Verify
xcode-select -p
# Should show: /Library/Developer/CommandLineTools
```

## Verification

After installation, verify Homebrew works:

```bash
# Check version
brew --version

# Check taps
brew tap

# Check paths
brew --prefix
# Should show: /opt/homebrew

# Try a simple command
brew config
```

## Common Issues

**"brew: command not found"**
Add to PATH:
```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
source ~/.zprofile
```

**"Permission denied"**
Fix ownership:
```bash
sudo chown -R $(whoami):admin /opt/homebrew
```

**"No such file or directory: /opt/homebrew/Library/Taps/homebrew/homebrew-core"**
Core tap is missing. Clone it on the online machine and transfer:
```bash
# On online machine
cd /tmp/homebrew/Library/Taps/homebrew
git clone https://github.com/Homebrew/homebrew-core
```

**"Git is not installed"**
Xcode Command Line Tools includes git. Install those first (see section above).

## Keeping Homebrew Updated (Offline)

Since `brew update` requires internet, update manually:

### On Online Machine

```bash
# 1. Pull latest changes
cd /path/to/homebrew
git pull origin master

cd Library/Taps/homebrew/homebrew-core
git pull origin master

cd ../homebrew-cask
git pull origin master

# 2. Copy updated homebrew to USB
cd /path/to
cp -r homebrew /Volumes/USB/
```

### On Offline Machine

```bash
# 1. Backup current installation (optional)
sudo mv /opt/homebrew /opt/homebrew.backup

# 2. Copy new version
sudo cp -r /Volumes/USB/homebrew /opt/homebrew

# 3. Fix permissions
sudo chown -R $(whoami):admin /opt/homebrew

# 4. Verify
brew --version
```

## Using with Offlinebrew

After Homebrew is installed, you can use offlinebrew:

```bash
# 1. Install offlinebrew (transfer from online machine)
cd /path/to/offlinebrew
export PATH="$(pwd)/bin:$PATH"

# 2. Configure mirror location
mkdir -p ~/.offlinebrew
echo '{"baseurl": "http://mirror-server:8000"}' > ~/.offlinebrew/config.json

# 3. Install packages
brew offline install wget
brew offline install --cask firefox
```

See [GETTING_STARTED.md](GETTING_STARTED.md) for complete offlinebrew usage.

## Alternative: Portable Homebrew Installation

For environments where you can't install to `/opt/homebrew`:

```bash
# Install to user directory
mkdir -p ~/homebrew
cd ~/homebrew
tar -xzf /Volumes/USB/homebrew.tar.gz --strip-components=1

# Add to PATH
echo 'export PATH="$HOME/homebrew/bin:$PATH"' >> ~/.zprofile
source ~/.zprofile
```

**Note**: Some packages may not work correctly outside `/opt/homebrew`.

## Next Steps

- **Install offlinebrew**: See [GETTING_STARTED.md](GETTING_STARTED.md)
- **Create mirrors**: See [GETTING_STARTED.md#creating-mirrors](GETTING_STARTED.md#creating-mirrors)
- **Report issues**: https://github.com/withzombies/offlinebrew/issues
