# Troubleshooting Guide

Common issues and solutions for offlinebrew.

## Table of Contents

- [Mirror Creation Issues](#mirror-creation-issues)
- [Installation Issues](#installation-issues)
- [Server Issues](#server-issues)
- [Configuration Issues](#configuration-issues)
- [Performance Issues](#performance-issues)
- [Getting Help](#getting-help)

## Mirror Creation Issues

### Error: "homebrew-core tap not found"

**Problem:** The core tap isn't installed or is outdated.

**Solution:**
```bash
brew update
brew tap homebrew/core
```

### Error: "No cask with this name exists"

**Problem:** Cask name is incorrect or cask doesn't exist.

**Solution:** Search for the correct cask name:
```bash
brew search --cask firefox
brew info --cask firefox
```

### Mirror takes forever / runs out of disk space

**Problem:** Mirroring everything requires 100GB+ and takes hours.

**Solution 1:** Start with specific packages:
```bash
brew ruby bin/brew-mirror -d ./mirror -f wget,jq --casks firefox -s 1
```

**Solution 2:** Mirror formulas only (skip casks):
```bash
brew ruby bin/brew-mirror -d ./mirror -f wget,jq --taps core -s 1
```

**Solution 3:** Use external drive:
```bash
brew ruby bin/brew-mirror -d /Volumes/USB/mirror -f wget -s 1
```

### Error: "undefined method 'downloader' for Cask::URL"

**Problem:** Old offlinebrew version with new Homebrew.

**Solution:** Update to offlinebrew v2.0:
```bash
cd offlinebrew
git pull origin main
```

### Error: "cannot be used without --eval-all"

**Problem:** Homebrew's cask API requires HOMEBREW_EVAL_ALL.

**Solution:** This is fixed in v2.0. If still seeing it:
```bash
export HOMEBREW_EVAL_ALL=1
brew ruby bin/brew-mirror ...
```

### Download fails with "Failed to mirror"

**Problem:** Network issues or unsupported download strategy.

**Solution:**
1. Check network connection
2. Retry with sleep to avoid rate limiting:
   ```bash
   brew ruby bin/brew-mirror -d ./mirror -f wget -s 2
   ```
3. Enable verbose mode:
   ```bash
   export HOMEBREW_VERBOSE=1
   brew ruby bin/brew-mirror -d ./mirror -f wget
   ```

## Installation Issues

### Error: "Couldn't read config or urlmap"

**Problem:** Client config not set up.

**Solution:** Create config file:
```bash
mkdir -p ~/.offlinebrew
echo '{"baseurl": "http://mirror-server:8000"}' > ~/.offlinebrew/config.json
```

### Downloads still go to internet

**Problem:** Shims not in PATH or config incorrect.

**Solution 1:** Check shims are working:
```bash
export BREW_OFFLINE_DEBUG=1
ruby bin/brew-offline-install wget
# Look for "[brew-offline-curl]" messages
```

**Solution 2:** Verify PATH includes shims:
```bash
echo $PATH | grep offlinebrew
# Should see offlinebrew/mirror/bin
```

**Solution 3:** Check config:
```bash
cat ~/.offlinebrew/config.json
# Verify baseurl is correct
```

### Cask installation fails

**Problem:** Cask not in mirror or wrong cask name.

**Solution 1:** Verify cask is in mirror:
```bash
brew ruby bin/brew-mirror-verify /path/to/mirror
```

**Solution 2:** Check manifest:
```bash
open /path/to/mirror/manifest.html
# Or check JSON:
cat /path/to/mirror/manifest.json | grep -A5 '"casks"'
```

**Solution 3:** Add cask to mirror:
```bash
brew ruby bin/brew-mirror -d /path/to/mirror --casks firefox --update
```

### Error: "Formula not found in mirror"

**Problem:** Formula wasn't mirrored or has different version.

**Solution:** Check what's in the mirror:
```bash
cat /path/to/mirror/manifest.json | jq '.formulae[] | .name'
```

Then add it:
```bash
brew ruby bin/brew-mirror -d /path/to/mirror -f wget --update
```

## Server Issues

### Port 8000 already in use

**Problem:** Another service is using port 8000.

**Solution:** Use a different port:
```bash
python3 -m http.server 8080
```

Then update config:
```json
{
  "baseurl": "http://mirror-server:8080"
}
```

### Slow downloads from mirror

**Problem:** Python's http.server is slow for large files.

**Solution:** Use a production HTTP server:

**Nginx:**
```bash
# Install nginx
brew install nginx

# Configure (add to nginx.conf)
server {
  listen 8000;
  root /path/to/mirror;
  autoindex on;
  sendfile on;
  tcp_nopush on;
}

# Start nginx
nginx
```

**Apache:**
```bash
# Install apache
brew install httpd

# Configure (httpd.conf)
Listen 8000
DocumentRoot "/path/to/mirror"
<Directory "/path/to/mirror">
    Options +Indexes
    Require all granted
</Directory>

# Start apache
apachectl start
```

### Can't access mirror from other machines

**Problem:** Firewall or network configuration.

**Solution 1:** Check firewall:
```bash
# macOS
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
```

**Solution 2:** Use correct IP:
```bash
# Find your IP
ifconfig | grep "inet "
# Use that IP in baseurl
```

**Solution 3:** Test connectivity:
```bash
# From client machine
curl http://mirror-server:8000/config.json
```

## Configuration Issues

### Error: "Invalid tap name: core"

**Problem:** Old offlinebrew version doesn't support tap shortcuts.

**Solution:** Update to v2.0 or use full tap names:
```bash
# v2.0 (shortcuts work)
--taps core,cask

# v1.x (need full names)
--taps homebrew/homebrew-core,homebrew/homebrew-cask
```

### Config keeps getting overwritten

**Problem:** `brew-offline-install` updates local config from mirror.

**Solution:** This is normal behavior. The tool syncs config from mirror to ensure consistency.

### Can't find ~/.offlinebrew directory

**Problem:** Hidden directory or wrong home path.

**Solution:**
```bash
# Show hidden files in Finder
defaults write com.apple.finder AppleShowAllFiles YES
killall Finder

# Or create via terminal
mkdir -p ~/.offlinebrew
ls -la ~ | grep offlinebrew
```

## Performance Issues

### Mirror creation is very slow

**Problem:** Downloading everything takes time.

**Solutions:**
1. **Increase sleep interval** (be nice to servers):
   ```bash
   brew ruby bin/brew-mirror -d ./mirror -f wget -s 2
   ```

2. **Mirror fewer packages**:
   ```bash
   brew ruby bin/brew-mirror -d ./mirror -f wget,jq -s 1
   ```

3. **Skip casks** (formulas are much smaller):
   ```bash
   brew ruby bin/brew-mirror -d ./mirror -f wget --taps core
   ```

4. **Use incremental updates**:
   ```bash
   # First time: mirror basics
   brew ruby bin/brew-mirror -d ./mirror -f wget -s 1

   # Later: add more (skips wget)
   brew ruby bin/brew-mirror -d ./mirror -f wget,jq --update -s 1
   ```

### Verification is slow

**Problem:** Checksum verification reads all files.

**Solution:** Skip checksums for faster verification:
```bash
# Fast (no checksums)
brew ruby bin/brew-mirror-verify /path/to/mirror

# Slow but thorough (with checksums)
brew ruby bin/brew-mirror-verify --checksums /path/to/mirror
```

## Debug Mode

Enable detailed logging:

```bash
# Offlinebrew debug mode
export BREW_OFFLINE_DEBUG=1

# Homebrew verbose mode
export HOMEBREW_VERBOSE=1

# Both
export BREW_OFFLINE_DEBUG=1 HOMEBREW_VERBOSE=1

# Run command
ruby bin/brew-offline-install wget
```

## Getting Help

### Before Opening an Issue

1. **Update to latest version**:
   ```bash
   cd offlinebrew
   git pull origin main
   ```

2. **Enable debug output**:
   ```bash
   export BREW_OFFLINE_DEBUG=1
   export HOMEBREW_VERBOSE=1
   ```

3. **Run verification**:
   ```bash
   brew ruby bin/brew-mirror-verify --verbose /path/to/mirror
   ```

4. **Check system info**:
   ```bash
   brew --version
   ruby --version
   uname -a
   ```

### Opening an Issue

Include:
- Offlinebrew version (`git log -1 --oneline`)
- Homebrew version (`brew --version`)
- macOS version (`sw_vers`)
- Full command used
- Complete error output
- Debug logs (with `BREW_OFFLINE_DEBUG=1`)

### Community Support

- GitHub Issues: https://github.com/withzombies/offlinebrew/issues
- Read the docs: [README.md](README.md), [mirror/README.md](mirror/README.md)
- Check [MIGRATION.md](MIGRATION.md) if upgrading from v1.x

## Quick Reference

| Problem | Command |
|---------|---------|
| Test mirror | `brew ruby bin/brew-mirror-verify /path/to/mirror` |
| View mirror contents | `open /path/to/mirror/manifest.html` |
| Enable debug | `export BREW_OFFLINE_DEBUG=1` |
| Check config | `cat ~/.offlinebrew/config.json` |
| Test connectivity | `curl http://mirror:8000/config.json` |
| Update mirror | `brew ruby bin/brew-mirror -d /path/to/mirror --update` |
