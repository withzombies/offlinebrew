# Getting Started with Offlinebrew

Complete guide to installing and using Offlinebrew for offline Homebrew packages.

## What is Offlinebrew?

Offlinebrew creates offline mirrors of Homebrew packages (formulas and casks) so you can install them on machines without internet access. Perfect for air-gapped environments, remote locations, or reproducible builds.

**The process**: Create mirror (online) → Serve mirror (network) → Install packages (offline)

## Requirements

- **macOS 12.0+** on Apple Silicon (arm64)
- **Homebrew 5.0+** (required)
- **Ruby 3.0+** (included with macOS)
- **Python 3** (for serving mirrors)
- **Disk space**: 1-100GB depending on mirror size

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/withzombies/offlinebrew.git
cd offlinebrew
```

### 2. Add to PATH

For **zsh** (default on macOS):
```bash
echo 'export PATH="'$(pwd)'/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

For **bash**:
```bash
echo 'export PATH="'$(pwd)'/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 3. Verify

```bash
brew offline help
```

## Quick Start

### Create a Mirror (Online Machine)

Mirror specific packages with dependencies:

```bash
brew offline mirror \
  -d ~/brew-mirror \
  -f wget,jq,htop \
  --casks firefox \
  --with-deps \
  -s 1
```

**What this does:**
- Creates mirror at `~/brew-mirror`
- Includes wget, jq, htop (command-line tools)
- Includes Firefox (GUI app)
- **Automatically includes all dependencies** (`--with-deps`)
- 1 second delay between downloads (polite to servers)

**Expected**: ~500MB download, 5-10 minutes

### Serve the Mirror

```bash
cd ~/brew-mirror
python3 -m http.server 8000
```

Mirror is now at `http://localhost:8000` (or `http://YOUR_IP:8000` for other machines)

### Install from Mirror (Offline Machine)

**First**, copy offlinebrew to the offline machine (USB/scp/network), then:

```bash
# Configure mirror location
mkdir -p ~/.offlinebrew
echo '{"baseurl": "http://192.168.1.100:8000"}' > ~/.offlinebrew/config.json

# Install packages
brew offline install wget
brew offline install --cask firefox
```

**Done!** 🎉

## Creating Mirrors

### Mirror Options

Common options:

- `-d, --directory` - Where to store mirror (required)
- `-f, --formulae` - Command-line tools (comma-separated)
- `--casks` - GUI apps (comma-separated)
- `--with-deps` - **Automatically include dependencies** (recommended!)
- `-s, --sleep` - Delay between downloads (default: 0.5, recommended: 1)
- `--verify` - Verify mirror after creation
- `--update` - Update existing mirror (10-100x faster!)

### Examples

**Specific packages with dependencies:**
```bash
brew offline mirror -d ~/mirror -f wget,curl --with-deps -s 1
```

**GUI apps:**
```bash
brew offline mirror -d ~/mirror --casks firefox,chrome,vscode -s 1
```

**Include fonts:**
```bash
brew offline mirror -d ~/mirror \
  --taps core,cask,fonts \
  --casks font-fira-code,font-jetbrains-mono \
  -s 1
```

**Update existing mirror:**
```bash
brew offline mirror -d ~/mirror --update --prune
```

**Add packages to existing mirror:**
```bash
brew offline mirror -d ~/mirror -f tree,ncdu --update
```

## Verification

Verify mirror integrity:

```bash
brew offline verify ~/mirror
```

Expected output:
```
✓ Configuration file valid
✓ URL mapping file valid
✓ All files present

Mirror Statistics:
  Formulae: 3
  Casks: 1
  Total Files: 8
  Total Size: 487.3 MB

Mirror is valid!
```

View manifest:
```bash
open ~/mirror/manifest.html
```

## Serving Mirrors

### Quick (Development)

```bash
cd ~/mirror
python3 -m http.server 8000
```

### Production

Use nginx, Apache, or create a LaunchDaemon for automatic startup.

## Installing Packages

### Configuration

Create `~/.offlinebrew/config.json`:

```bash
mkdir -p ~/.offlinebrew
cat > ~/.offlinebrew/config.json <<EOF
{
  "baseurl": "http://your-mirror-server:8000"
}
EOF
```

### Install Commands

```bash
# Formula (command-line tool)
brew offline install wget

# Cask (GUI app)
brew offline install --cask firefox

# Multiple packages
brew offline install jq htop tree
```

## Transferring to Offline Machines

### Via USB

```bash
# On online machine
cp -r offlinebrew /Volumes/USB/

# On offline machine
cp -r /Volumes/USB/offlinebrew ~/
cd ~/offlinebrew
# Follow installation steps above
```

### Via Network

```bash
scp -r offlinebrew user@offline-machine:/home/user/
```

## Complete Workflow Example

### Online Machine

```bash
# 1. Install offlinebrew
git clone https://github.com/withzombies/offlinebrew.git
cd offlinebrew
export PATH="$(pwd)/bin:$PATH"

# 2. Create mirror
brew offline mirror \
  -d ~/my-mirror \
  -f wget,jq,htop \
  --casks firefox \
  --with-deps \
  -s 1 \
  --verify

# 3. Serve mirror
cd ~/my-mirror
python3 -m http.server 8000
```

### Offline Machine

```bash
# 1. Copy offlinebrew (via USB/scp)
cd /path/to/offlinebrew
export PATH="$(pwd)/bin:$PATH"

# 2. Configure mirror
mkdir -p ~/.offlinebrew
echo '{"baseurl": "http://192.168.1.100:8000"}' > ~/.offlinebrew/config.json

# 3. Install packages
brew offline install wget jq htop
brew offline install --cask firefox

# 4. Verify
wget --version
which firefox
```

## Troubleshooting

**"Command not found: brew"**
Install Homebrew: https://brew.sh

**"Command not found: brew offline"**
Add `bin/` to PATH (see installation step 2) or use full path

**"Cannot find mirror"**
1. Check mirror server is running: `curl http://192.168.1.100:8000/config.json`
2. Verify firewall allows port 8000
3. Check IP in `~/.offlinebrew/config.json`

**"Package not found in mirror"**
Add it to mirror with `--update`:
```bash
brew offline mirror -d ~/mirror -f missing-package --update
```

**Mirror verification fails**
Check with verbose mode:
```bash
brew offline verify --verbose ~/mirror
```

## Debug Mode

Enable detailed logging:
```bash
export BREW_OFFLINE_DEBUG=1
brew offline mirror -d ~/mirror -f wget
```

## Updating Offlinebrew

```bash
cd offlinebrew
git pull origin main
```

## Next Steps

- **Advanced features**: See [mirror/README.md](mirror/README.md)
- **Report issues**: https://github.com/withzombies/offlinebrew/issues
