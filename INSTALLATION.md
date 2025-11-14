# Installation Guide

This guide covers how to install and set up Offlinebrew on your system.

## System Requirements

### For Creating Mirrors

- **Operating System**: macOS 12.0 or later
- **Architecture**: Apple Silicon (arm64)
- **Disk Space**:
  - Selective mirrors: 1-10GB
  - Full mirrors: 100GB+
- **Software**:
  - Homebrew (latest version recommended)
  - Ruby 2.6+ (included with macOS)
  - Git
  - Python 3 (for serving mirrors)
- **Network**: Internet connection for downloading packages

### For Installing from Mirrors

- **Operating System**: macOS 12.0 or later
- **Architecture**: Apple Silicon (arm64)
- **Disk Space**: Varies by packages installed
- **Software**:
  - Homebrew (same or older version as used to create mirror)
  - Ruby 2.6+ (included with macOS)
- **Network**: Access to mirror server (can be offline from internet)

## Installation Methods

### Method 1: Git Clone (Recommended)

Clone the repository to get the latest stable version:

```bash
# Clone from GitHub
git clone https://github.com/withzombies/offlinebrew.git
cd offlinebrew
```

#### Update to Latest Version

```bash
cd offlinebrew
git pull origin main
```

### Method 2: Download Release Archive

Download a specific release:

```bash
# Download latest release (replace X.Y.Z with version)
curl -L https://github.com/withzombies/offlinebrew/archive/refs/tags/vX.Y.Z.tar.gz -o offlinebrew.tar.gz

# Extract
tar -xzf offlinebrew.tar.gz
cd offlinebrew-X.Y.Z
```

### Method 3: Transfer to Offline Machine

For machines without internet access:

#### Option A: USB Drive

```bash
# On online machine
git clone https://github.com/withzombies/offlinebrew.git
cp -r offlinebrew /Volumes/USB/

# On offline machine (after connecting USB)
cp -r /Volumes/USB/offlinebrew ~/
cd ~/offlinebrew
```

#### Option B: Network Transfer (scp)

```bash
# On online machine
scp -r offlinebrew user@offline-machine:/home/user/
```

#### Option C: Internal Git Server

```bash
# Set up mirror on internal git server, then:
git clone http://internal-git-server/offlinebrew.git
```

## Setting Up the `brew offline` Command

After installation, you can use offlinebrew in two ways:

### Option A: Add to PATH (Recommended)

This allows you to use `brew offline` from anywhere:

#### For bash (add to `~/.bashrc` or `~/.bash_profile`):

```bash
echo 'export PATH="/path/to/offlinebrew/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

#### For zsh (add to `~/.zshrc`):

```bash
echo 'export PATH="/path/to/offlinebrew/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

#### For fish (add to `~/.config/fish/config.fish`):

```fish
set -gx PATH /path/to/offlinebrew/bin $PATH
```

Replace `/path/to/offlinebrew` with the actual path where you cloned/extracted offlinebrew.

#### Verify Installation

```bash
brew offline help
```

You should see the help message with available commands.

### Option B: Create Symlink (Alternative)

Create a system-wide symlink (requires sudo):

```bash
sudo ln -s /path/to/offlinebrew/bin/brew-offline /usr/local/bin/brew-offline
```

Verify:
```bash
brew-offline help
```

### Option C: Use Full Paths (No Setup)

You can always use full paths without any setup:

```bash
/path/to/offlinebrew/bin/brew-offline mirror -d ~/mirror -f wget
```

## Configuration

### For Mirror Creation (Online Machine)

No configuration needed! Just run the commands.

### For Installing from Mirror (Offline Machine)

Create a configuration file pointing to your mirror:

```bash
# Create config directory
mkdir -p ~/.offlinebrew

# Create config file
cat > ~/.offlinebrew/config.json <<EOF
{
  "baseurl": "http://your-mirror-server:8000"
}
EOF
```

Replace `your-mirror-server:8000` with your actual mirror URL.

#### Configuration Options

The `config.json` file supports these options:

```json
{
  "baseurl": "http://192.168.1.100:8000",
  "timeout": 30,
  "verify_ssl": true
}
```

- `baseurl` (required): URL of the mirror server
- `timeout` (optional): Network timeout in seconds (default: 30)
- `verify_ssl` (optional): Verify SSL certificates (default: true)

#### Configuration File Locations

Offlinebrew looks for configuration in these locations (in order):

1. `~/.offlinebrew/config.json` (user-specific)
2. `/etc/offlinebrew/config.json` (system-wide, requires sudo to create)
3. `$OFFLINEBREW_CONFIG` environment variable

Example of using environment variable:
```bash
export OFFLINEBREW_CONFIG=/custom/path/config.json
brew offline install wget
```

## Verification

### Test Mirror Creation

Create a small test mirror:

```bash
brew offline mirror \
  -d /tmp/test-mirror \
  -f wget \
  -s 0.5 \
  --verify
```

Expected output:
```
==> Mirroring formulae...
==> Downloading wget...
==> Manifest written to: manifest.json
==> HTML report written to: manifest.html
==> Verifying mirror...
✓ Mirror is valid!
```

### Test Mirror Serving

```bash
cd /tmp/test-mirror
python3 -m http.server 8000 &
curl http://localhost:8000/config.json
kill %1  # Stop server
```

### Test Package Installation

```bash
# Configure
echo '{"baseurl": "http://localhost:8000"}' > ~/.offlinebrew/config.json

# Start server
cd /tmp/test-mirror
python3 -m http.server 8000 &

# Install (in another terminal)
brew offline install wget

# Clean up
kill %1
rm -rf /tmp/test-mirror
```

## Troubleshooting Installation

### "Command not found: brew"

Homebrew is not installed. Install it:

```bash
# macOS or Linux
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### "Command not found: brew offline"

The `bin/` directory is not in your PATH. Either:
1. Add to PATH (see "Setting Up the brew offline Command" above)
2. Use full path: `/path/to/offlinebrew/bin/brew-offline`

### "Permission denied"

Scripts are not executable:

```bash
cd offlinebrew
chmod +x bin/brew-offline
chmod +x mirror/bin/*
```

### "Ruby version too old"

Check Ruby version:
```bash
ruby --version
```

If < 2.6, update Ruby:
```bash
# macOS (via Homebrew)
brew install ruby

# Or use rbenv/rvm for version management
```

### "Make sure to run me via `brew ruby`!"

This error means a script that requires Homebrew internals was run incorrectly. Use:
```bash
brew offline mirror ...  # Correct (handles this automatically)
```

Not:
```bash
ruby mirror/bin/brew-mirror ...  # Wrong for brew-mirror
```

### Git clone fails

If GitHub is blocked:
1. Download release archive instead (Method 2)
2. Use a VPN or proxy
3. Ask someone to clone it and transfer via USB

## Uninstallation

### Remove Offlinebrew

```bash
# Remove directory
rm -rf /path/to/offlinebrew

# Remove from PATH (edit ~/.bashrc, ~/.zshrc, etc.)
# Remove the line: export PATH="/path/to/offlinebrew/bin:$PATH"

# Remove configuration
rm -rf ~/.offlinebrew

# Remove symlink (if created)
sudo rm /usr/local/bin/brew-offline
```

### Remove Mirrors

```bash
# Remove specific mirror
rm -rf /path/to/mirror

# Find all mirrors (if you forgot where they are)
find ~ -name "config.json" -path "*/.offlinebrew/*" -o -name "manifest.json" -path "*/brew-mirror/*"
```

## Staying Up to Date

```bash
# Update offlinebrew
cd offlinebrew
git pull origin main
```

## Next Steps

After installation:

1. **Read the Getting Started guide**: [GETTING_STARTED.md](GETTING_STARTED.md)
2. **Create your first mirror**: `brew offline mirror -d ~/test-mirror -f wget,jq`
3. **Explore advanced features**: [mirror/README.md](mirror/README.md)
4. **Set up production deployment**: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## Support

- **Documentation**: See [README.md](README.md)
- **Issues**: Report at https://github.com/withzombies/offlinebrew/issues
- **Debug mode**: Set `export BREW_OFFLINE_DEBUG=1` for detailed logs
- **Verbose mode**: Set `export HOMEBREW_VERBOSE=1` for Homebrew internals

## Platform-Specific Notes

### macOS on Apple Silicon

- Homebrew installs to `/opt/homebrew`
- Offlinebrew automatically detects this
- No special configuration needed
- Uses cache pre-population for offline installation

### How Offline Installation Works on macOS

Offlinebrew uses a **cache pre-population** approach for macOS:

1. Before installation, all required files are downloaded from your mirror
2. Files are placed in Homebrew's cache directory (`~/Library/Caches/Homebrew/downloads/`)
3. Each file is named using the format: `sha256hash--filename.tar.gz`
4. When `brew install` runs, it finds files in cache and uses them instead of downloading

This approach is necessary because macOS Homebrew doesn't support the `HOMEBREW_CURL_PATH` or `HOMEBREW_GIT_PATH` environment variables that would allow URL interception.

**What this means for you:**
- Installation is fully automatic - no special configuration needed
- You'll see a message: "Pre-populated X files from mirror into Homebrew cache"
- If you don't see this message, check your mirror server is running and accessible

## Security Considerations

### When Creating Mirrors

- Mirror creation requires internet access
- Downloads are verified with checksums
- Git repositories are cloned securely
- No credentials are stored in mirrors

### When Using Mirrors

- Mirrors are point-in-time snapshots
- No automatic updates (by design)
- Verify mirror integrity: `brew offline verify /path/to/mirror`
- Use HTTPS for mirror servers when possible

### Access Control

For production deployments:

```bash
# Restrict mirror server access
# Use nginx/Apache with authentication
# Example nginx config:
location / {
    auth_basic "Offlinebrew Mirror";
    auth_basic_user_file /etc/nginx/.htpasswd;
}
```

Update config.json:
```json
{
  "baseurl": "http://mirror-server:8000",
  "username": "user",
  "password": "pass"
}
```

## Advanced Installation

### Installing as System Service (macOS)

Create a LaunchDaemon to serve mirror automatically:

```bash
# Create service plist
sudo tee /Library/LaunchDaemons/com.offlinebrew.mirror.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.offlinebrew.mirror</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>-m</string>
        <string>http.server</string>
        <string>8000</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/path/to/mirror</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

# Load service
sudo launchctl load /Library/LaunchDaemons/com.offlinebrew.mirror.plist
```

### Installing with Docker

Create a Dockerfile to serve mirrors:

```dockerfile
FROM python:3-alpine
WORKDIR /mirror
COPY mirror-contents/ /mirror/
EXPOSE 8000
CMD ["python", "-m", "http.server", "8000"]
```

```bash
# Build
docker build -t offlinebrew-mirror .

# Run
docker run -d -p 8000:8000 --name mirror offlinebrew-mirror
```

### Installing on Network Attached Storage (NAS)

Many NAS systems support Python and web servers:

1. Copy mirror to NAS shared folder
2. Enable Python/web server on NAS
3. Configure to serve mirror directory
4. Point clients to NAS URL

Consult your NAS documentation for specific instructions (Synology, QNAP, etc.).

## Useful Aliases

Add these to your shell config for convenience:

```bash
# Create mirror alias
alias brew-mirror='brew offline mirror'

# Install alias
alias brew-install='brew offline install'

# Quick verify
alias brew-verify='brew offline verify'

# Update mirror shortcut
alias brew-update-mirror='brew offline mirror --update --prune'
```

With these aliases:
```bash
brew-mirror -d ~/mirror -f wget
brew-install wget
brew-verify ~/mirror
```
