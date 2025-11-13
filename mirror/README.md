# Offlinebrew Mirror - Advanced Guide

The mirror-based approach uses URL rewriting to redirect all Homebrew downloads to a local HTTP server.

**For getting started**, see [GETTING_STARTED.md](../GETTING_STARTED.md).

This document covers advanced usage, configuration, and troubleshooting.

## Quick Reference

```bash
# Create mirror with specific packages
brew offline mirror -d ~/mirror -f wget,jq --casks firefox -s 1

# Update existing mirror
brew offline mirror -d ~/mirror --update --prune

# Verify mirror integrity
brew offline verify ~/mirror

# Install from mirror
brew offline install wget
brew offline install --cask firefox
```

## Commands

All commands are available through the `brew offline` interface.

### brew offline mirror

Creates an offline mirror of Homebrew packages (formulas and casks).

**Usage:**
```bash
brew offline mirror [options]
```

**Required Options:**
- `-d, --directory DIR` - Output directory for mirror

**Package Selection:**
- `-f, --formulae f1,f2,...` - Mirror specific formulae (comma-separated)
- `--casks c1,c2,...` - Mirror specific casks (comma-separated)
- `--taps tap1,tap2,...` - Taps to mirror (default: core,cask)
  - Shortcuts: `core`, `cask`, `fonts`, `versions`, `drivers`
  - Full names: `homebrew/homebrew-core`, `mycompany/homebrew-private`

**Behavior Options:**
- `-s, --sleep SECS` - Sleep between downloads (default: 0.5, recommended: 1.0)
- `-c, --config-only` - Write config files without downloading packages
- `--update` - Incremental update (skip unchanged packages, 10-100x faster!)
- `--prune` - Report removed/updated packages when using --update
- `--verify` - Verify mirror integrity after creation

**Examples:**

```bash
# Mirror everything (requires ~100GB, takes hours)
brew offline mirror -d /Volumes/USB/brew-mirror -s 1

# Mirror specific packages (recommended for getting started)
brew offline mirror -d ~/mirror -f wget,jq,htop --casks firefox -s 1

# Update existing mirror (much faster!)
brew offline mirror -d ~/mirror --update --prune

# Mirror with custom taps
brew offline mirror -d ~/mirror --taps core,cask,fonts -f wget

# Mirror formulas only (no casks, faster)
brew offline mirror -d ~/mirror -f wget,jq,curl --taps core

# Mirror with automatic verification
brew offline mirror -d ~/mirror -f wget --verify

# Config-only mode (for testing)
brew offline mirror -d ~/mirror -f wget -c
```

**Performance Tips:**
- Use `-s 1` to be polite to Homebrew servers (1 second between downloads)
- Use `--update` for incremental updates (10-100x faster!)
- Use `-f` to mirror only what you need
- Use `--taps core` to skip casks (50% faster)

### brew offline install

Installs packages from the offline mirror.

**Usage:**
```bash
brew offline install [--cask] <package> [package2 ...]
```

**Flags:**
- `--cask` - Install a cask (GUI application) instead of formula

**Examples:**

```bash
# Install a formula (command-line tool)
brew offline install wget

# Install a cask (GUI application)
brew offline install --cask firefox

# Install multiple packages at once
brew offline install jq htop wget tree

# Install multiple casks
brew offline install --cask firefox visual-studio-code slack
```

**Prerequisites:**
1. Mirror must be accessible via HTTP
2. Configuration file at `~/.offlinebrew/config.json`
3. Configuration must specify `baseurl` pointing to mirror

**Configuration Example:**
```json
{
  "baseurl": "http://192.168.1.100:8000"
}
```

See [Configuration](#client-configuration) for details.

### brew offline verify

Verifies mirror integrity and completeness.

**Usage:**
```bash
brew offline verify [options] <mirror-directory>
```

**Options:**
- `--verbose` - Show detailed verification output
- `--checksums` - Verify file checksums (slow, requires re-downloading)

**Examples:**

```bash
# Quick verification (checks structure and files)
brew offline verify ~/mirror

# Detailed verification (shows all checks)
brew offline verify --verbose ~/mirror

# Full verification with checksums (slow but thorough)
brew offline verify --checksums ~/mirror
```

**What Gets Verified:**
- ✅ Configuration file exists and is valid JSON
- ✅ URL mapping file exists and is parseable
- ✅ All mapped files are present in mirror
- ✅ No orphaned files (files not referenced in URL map)
- ✅ Git repository cache consistency
- ✅ Manifest file structure (if present)
- ✅ File checksums match (with `--checksums` flag)

**Exit Codes:**
- `0` - Mirror is valid, no issues found
- `1` - Errors or warnings detected
- `2` - Usage error (missing arguments)

**Verification Output Example:**
```
==> Verifying mirror: /Users/you/mirror
✓ Configuration file valid
✓ URL mapping file valid
✓ All 523 mapped files present
✓ No orphaned files found
✓ Git cache consistent (15 repositories)

Mirror Statistics:
  Formulae: 10
  Casks: 5
  Total Files: 523
  Total Size: 2.4 GB

Mirror is valid!
```

### Internal Shims

These commands are called automatically by `brew offline install`. You don't need to use them directly.

#### brew-offline-curl (Internal)

Intercepts `curl` requests and redirects to the local mirror.

**How It Works:**
1. Receives curl request from Homebrew
2. Looks up URL in mirror's `urlmap.json`
3. Returns local mirror file if found
4. Falls back to normal curl if not in mirror

**Debug Mode:**
```bash
export BREW_OFFLINE_DEBUG=1
brew offline install wget
# Shows: [brew-offline-curl] Looking up URL: https://...
```

#### brew-offline-git (Internal)

Intercepts `git clone` requests and redirects to the local mirror.

**How It Works:**
1. Receives git clone request from Homebrew
2. Looks up repository in mirror's `urlmap.json`
3. Returns local mirror repository if found
4. Falls back to normal git if not in mirror

**Debug Mode:**
```bash
export BREW_OFFLINE_DEBUG=1
brew offline install formula-with-git-dependency
# Shows: [brew-offline-git] Redirecting: https://github.com/...
```

## Configuration

### Client Configuration

On machines that will install from the mirror, create:

**File:** `~/.offlinebrew/config.json`

**Basic Configuration:**
```json
{
  "baseurl": "http://192.168.1.100:8000"
}
```

**Advanced Configuration:**
```json
{
  "baseurl": "http://mirror-server:8000",
  "timeout": 30,
  "verify_ssl": true
}
```

**Options:**
- `baseurl` (required) - URL of the mirror server
- `timeout` (optional) - Network timeout in seconds (default: 30)
- `verify_ssl` (optional) - Verify SSL certificates (default: true)

**Alternative Locations:**

Offlinebrew searches for config in this order:
1. `~/.offlinebrew/config.json` (user-specific)
2. `/etc/offlinebrew/config.json` (system-wide)
3. `$OFFLINEBREW_CONFIG` environment variable

Example using environment variable:
```bash
export OFFLINEBREW_CONFIG=/custom/path/config.json
brew offline install wget
```

### Mirror Configuration

`brew offline mirror` auto-generates these files:

#### config.json

**Mirror metadata and tap commits:**

```json
{
  "taps": {
    "homebrew/homebrew-core": {
      "commit": "abc123def456...",
      "type": "formula"
    },
    "homebrew/homebrew-cask": {
      "commit": "789ghi012jkl...",
      "type": "cask"
    }
  },
  "stamp": "1699999999",
  "cache": "/path/to/mirror",
  "baseurl": "http://localhost:8000"
}
```

This file pins package versions to specific tap commits for reproducibility.

#### urlmap.json

**Maps URLs to local files:**

```json
{
  "https://example.com/package-1.0.tar.gz": "f2c1e86ca0...e07.tar.gz",
  "https://github.com/user/repo.git": "abc123def...456",
  "https://app.dmg?v=1.0": "app-1.0.dmg"
}
```

Used by shims to redirect downloads to local mirror files.

#### manifest.json

**Detailed mirror inventory:**

```json
{
  "created_at": "2025-11-13T12:34:56Z",
  "taps": {
    "homebrew/homebrew-core": {
      "commit": "abc123...",
      "type": "formula"
    }
  },
  "statistics": {
    "total_formulae": 100,
    "total_casks": 50,
    "total_files": 523,
    "total_size_bytes": 12345678900
  },
  "formulae": [
    {"name": "wget", "version": "1.21.3", "url": "https://..."}
  ],
  "casks": [
    {"token": "firefox", "version": "120.0", "url": "https://..."}
  ]
}
```

#### manifest.html

**Human-readable mirror report**

Open in browser to see:
- Mirror statistics (formulae, casks, total size)
- Complete package list
- Tap information
- Creation timestamp

```bash
open ~/mirror/manifest.html
```

#### identifier_cache.json

**Git repository tracking:**

```json
{
  "https://github.com/user/repo.git@abc123": "deterministic-id-456"
}
```

Prevents duplicate Git repository downloads during incremental updates.

## Serving the Mirror

Any HTTP server can serve the mirror. Choose based on your needs:

### Python (Built-in, Simple)

**Best for:** Development, testing, small teams

```bash
cd /path/to/mirror
python3 -m http.server 8000
```

**Pros:** Already installed, zero configuration
**Cons:** Single-threaded, no authentication, stops when terminal closes

**Run as background service:**
```bash
nohup python3 -m http.server 8000 > server.log 2>&1 &
```

### Nginx (Production-Ready)

**Best for:** Production, many clients, high performance

**Install:**
```bash
brew install nginx  # or: sudo apt install nginx
```

**Configure:** `/usr/local/etc/nginx/nginx.conf` (or `/etc/nginx/nginx.conf`)

```nginx
http {
    server {
        listen 8000;
        root /path/to/mirror;
        autoindex on;

        # Enable gzip compression
        gzip on;
        gzip_types application/json text/plain;

        # Large file support
        client_max_body_size 2G;

        # Optional: Basic authentication
        # auth_basic "Offlinebrew Mirror";
        # auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
```

**Start:**
```bash
nginx
# or: sudo systemctl start nginx
```

**Pros:** Fast, robust, authentication, HTTPS support
**Cons:** Requires installation and configuration

### Apache (Production-Ready)

**Best for:** Production, existing Apache infrastructure

**Install:**
```bash
brew install httpd  # or: sudo apt install apache2
```

**Configure:** `/usr/local/etc/httpd/httpd.conf` (or `/etc/apache2/sites-available/offlinebrew.conf`)

```apache
<VirtualHost *:8000>
    DocumentRoot /path/to/mirror
    <Directory /path/to/mirror>
        Options +Indexes
        Require all granted

        # Optional: Basic authentication
        # AuthType Basic
        # AuthName "Offlinebrew Mirror"
        # AuthUserFile /etc/apache2/.htpasswd
        # Require valid-user
    </Directory>
</VirtualHost>
```

**Start:**
```bash
apachectl start
# or: sudo systemctl start apache2
```

**Pros:** Mature, robust, widely used
**Cons:** Heavier than nginx, more complex configuration

### Docker (Containerized)

**Best for:** Cloud deployment, Kubernetes, portable setups

**Dockerfile:**
```dockerfile
FROM python:3-alpine
WORKDIR /mirror
COPY mirror-contents/ /mirror/
EXPOSE 8000
CMD ["python", "-m", "http.server", "8000"]
```

**Build and run:**
```bash
docker build -t offlinebrew-mirror .
docker run -d -p 8000:8000 --name mirror offlinebrew-mirror
```

**Pros:** Portable, isolated, easy to deploy
**Cons:** Requires Docker

## Incremental Updates

**The `--update` flag makes mirror updates 10-100x faster** by skipping unchanged packages.

### Initial Mirror

```bash
brew offline mirror -d ~/mirror -f wget,jq -s 1
```

### Add New Packages

```bash
# wget and jq are skipped (already mirrored)
brew offline mirror -d ~/mirror -f wget,jq,htop,tree --update -s 1
```

### Update After Tap Changes

When Homebrew taps update (new package versions):

```bash
brew update  # Update Homebrew itself
brew offline mirror -d ~/mirror -f wget,jq --update --prune -s 1
```

The `--prune` flag reports what changed:
```
==> The following formulae were removed or updated:
  wget: 1.21.3 -> 1.21.4 (updated)
  jq: removed (no longer in tap)

Note: --prune currently only reports changes. Actual file removal
requires manual cleanup. Old files remain in the mirror.
```

### How It Works

1. Loads existing `manifest.json`
2. Compares package names and versions
3. Skips packages with same name+version
4. Downloads only new or changed packages
5. Updates manifest with combined results

**Speed Improvement:**
- Full mirror update: ~2 hours (downloads everything)
- Incremental update: ~5 minutes (downloads only changes)

## Point-in-Time Snapshots

**Mirrors are immutable snapshots** tied to specific tap commits:

```json
{
  "taps": {
    "homebrew/homebrew-core": {
      "commit": "abc123...",  ← This exact commit
      "type": "formula"
    }
  }
}
```

**Benefits:**
- ✅ **Reproducible builds** - Same versions every time
- ✅ **No surprises** - Updates only when you choose
- ✅ **Auditable** - Know exactly what versions are available
- ✅ **Disaster recovery** - Restore to known-good state

**Creating Snapshots:**

```bash
# Update Homebrew to latest
brew update

# Create snapshot with today's date
brew offline mirror -d ~/mirror-$(date +%Y-%m-%d) -f wget,jq

# Result: mirror-2025-11-13/
```

**Using Old Snapshots:**

Just point `baseurl` to the old mirror - installations will use those old versions.

## Advanced Features

### Multi-Tap Support

Include packages from multiple taps:

```bash
# Include fonts
brew offline mirror -d ~/mirror \
  --taps core,cask,fonts \
  --casks font-fira-code,font-jetbrains-mono

# Include version casks (older app versions)
brew offline mirror -d ~/mirror \
  --taps core,cask,versions \
  --casks firefox,firefox@esr

# Include custom/private taps
brew offline mirror -d ~/mirror \
  --taps homebrew/homebrew-core,mycompany/homebrew-private
```

**Available Shortcuts:**
- `core` → `homebrew/homebrew-core` (CLI tools)
- `cask` → `homebrew/homebrew-cask` (GUI apps)
- `fonts` → `homebrew/homebrew-cask-fonts` (fonts)
- `versions` → `homebrew/homebrew-cask-versions` (old versions)
- `drivers` → `homebrew/homebrew-cask-drivers` (hardware drivers)

### Selective Mirroring

**Formulae only (faster, smaller):**
```bash
brew offline mirror -d ~/mirror-formulas \
  --taps core \
  -f wget,jq,curl,git,vim
```

**Casks only:**
```bash
brew offline mirror -d ~/mirror-casks \
  --taps cask \
  --casks firefox,visual-studio-code,slack
```

**Fonts only:**
```bash
brew offline mirror -d ~/mirror-fonts \
  --taps fonts \
  --casks font-fira-code,font-jetbrains-mono,font-hack
```

### Debug Mode

Enable detailed logging:

```bash
export BREW_OFFLINE_DEBUG=1

# Shows URL lookups, redirections, file operations
brew offline mirror -d ~/mirror -f wget
brew offline install wget
```

Output example:
```
[brew-offline-curl] Looking up URL: https://ftp.gnu.org/gnu/wget/wget-1.21.3.tar.gz
[brew-offline-curl] ✓ Found mapping: wget-1.21.3.tar.gz -> f2c1e86ca.tar.gz
[brew-offline-curl] Serving from mirror: http://localhost:8000/f2c1e86ca.tar.gz
```

### Statistics and Reporting

Every mirror includes detailed statistics:

```bash
# View JSON manifest
cat ~/mirror/manifest.json | jq '.statistics'

# View HTML report
open ~/mirror/manifest.html

# Quick stats with verification
brew offline verify ~/mirror
```

## Troubleshooting

### Common Issues

#### "Mirror verification failed"

**Cause:** Missing or corrupted files

**Solution:**
```bash
# See what's wrong
brew offline verify --verbose ~/mirror

# Re-create mirror
brew offline mirror -d ~/mirror -f wget,jq --update
```

#### "Cannot find mirror at http://..."

**Causes:**
1. Mirror server not running
2. Wrong IP/port in config
3. Firewall blocking connection

**Solutions:**
```bash
# Check server is running
curl http://192.168.1.100:8000/config.json

# Check config
cat ~/.offlinebrew/config.json

# Test from server machine first
curl http://localhost:8000/config.json
```

#### "Package not found in mirror"

**Cause:** Package wasn't included when creating mirror

**Solution:**
```bash
# Add the package
brew offline mirror -d ~/mirror -f missing-package --update
```

#### Installation fails with "checksum mismatch"

**Cause:** Package version in mirror doesn't match Homebrew's expectations

**Solution:**
```bash
# Update mirror
brew offline mirror -d ~/mirror --update

# Verify integrity
brew offline verify ~/mirror
```

### Debug Checklist

When things aren't working:

1. **Verify mirror structure:**
   ```bash
   brew offline verify ~/mirror
   ```

2. **Check server is accessible:**
   ```bash
   curl http://mirror-server:8000/config.json
   ```

3. **Verify client config:**
   ```bash
   cat ~/.offlinebrew/config.json
   ```

4. **Enable debug mode:**
   ```bash
   export BREW_OFFLINE_DEBUG=1
   export HOMEBREW_VERBOSE=1
   brew offline install wget
   ```

5. **Check Homebrew itself:**
   ```bash
   brew doctor
   brew update
   ```

For more solutions, see [TROUBLESHOOTING.md](../TROUBLESHOOTING.md).

## Testing

Run the comprehensive integration test suite:

```bash
cd mirror/test
./run_integration_tests.sh

# Run specific test suites
./run_integration_tests.sh full        # Full workflow
./run_integration_tests.sh verify      # Verification
./run_integration_tests.sh download    # Download strategies
```

See [test/integration/README.md](test/integration/README.md) for details.

## Architecture

### How URL Rewriting Works

1. **brew offline install** sets up environment:
   - Adds shims to PATH before Homebrew directories
   - Sets `REAL_HOME` for config access in sandbox
   - Resets taps to mirror commits

2. **Homebrew** runs normally but calls shims:
   - `curl` calls → `brew-offline-curl`
   - `git clone` calls → `brew-offline-git`

3. **Shims** redirect to mirror:
   - Look up URL in `urlmap.json`
   - Return local mirror file
   - Fall back to normal curl/git if not in mirror

4. **Installation** proceeds normally:
   - Homebrew thinks it downloaded from internet
   - Actually got files from local mirror
   - Same installation process, different source

**Result:** Seamless offline installation!

## Migration from v1.x

See [MIGRATION.md](../MIGRATION.md) for upgrading from older versions.

**Summary:** v2.0 is backward compatible!
- Old mirrors work with new tools
- Old configs are auto-upgraded
- Use `--update` to add v2.0 features to old mirrors

## Performance Tips

1. **Use incremental updates:** `--update` is 10-100x faster
2. **Be polite to servers:** `-s 1` (1 second delay)
3. **Mirror only what you need:** Use `-f` and `--casks`
4. **Skip casks for speed:** `--taps core` (formulas only)
5. **Use fast networks:** USB 3.0, Gigabit Ethernet, or better
6. **Serve locally:** Put mirror on same machine or fast NAS

## Security Considerations

### Mirror Creation

- Downloads verified with SHA256 checksums
- Git repositories cloned over HTTPS
- No credentials stored in mirrors
- Safe from shell injection (SafeShell module)

### Mirror Serving

For production:

```bash
# Use HTTPS with nginx
server {
    listen 443 ssl;
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    root /path/to/mirror;
}

# Add authentication
auth_basic "Offlinebrew Mirror";
auth_basic_user_file /etc/nginx/.htpasswd;
```

Update client config:
```json
{
  "baseurl": "https://mirror-server:443",
  "username": "user",
  "password": "pass",
  "verify_ssl": true
}
```

### Regular Updates

- Update mirrors regularly for security patches
- Verify mirror integrity: `brew offline verify`
- Monitor for Homebrew security advisories
- Keep offlinebrew up to date: `git pull`

## Support

- **Documentation:** [GETTING_STARTED.md](../GETTING_STARTED.md)
- **Issues:** [GitHub Issues](https://github.com/withzombies/offlinebrew/issues)
- **Changelog:** [CHANGELOG.md](../CHANGELOG.md)
- **Migration:** [MIGRATION.md](../MIGRATION.md)

## License

MIT License - see [../LICENSE](../LICENSE) for details.
