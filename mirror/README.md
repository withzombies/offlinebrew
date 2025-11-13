# Offlinebrew Mirror

The mirror-based approach uses URL rewriting to redirect all Homebrew downloads to a local HTTP server.

## Tools

All tools are located in the [bin/](bin/) directory and run on macOS with Homebrew installed.

### brew-mirror

Creates an offline mirror of Homebrew packages (formulas and casks).

**Usage:**
```bash
brew ruby mirror/bin/brew-mirror [options]
```

**Options:**
- `-d, --directory DIR` - Output directory (required)
- `-f, --formulae f1,f2` - Mirror specific formulae only
- `--casks c1,c2` - Mirror specific casks only
- `--taps tap1,tap2` - Taps to mirror (default: core,cask). Supports shortcuts: `core`, `cask`, `fonts`
- `-s, --sleep SECS` - Sleep between downloads (default: 0.5)
- `-c, --config-only` - Write config without downloading
- `--update` - Update existing mirror (skip unchanged packages)
- `--prune` - Report removed/updated versions when using --update
- `--verify` - Verify mirror integrity after creation

**Examples:**
```bash
# Mirror everything (requires ~100GB, takes hours)
brew ruby bin/brew-mirror -d /Volumes/USB/brew-mirror -s 1

# Mirror specific packages
brew ruby bin/brew-mirror -d ./mirror -f wget,jq --casks firefox -s 1

# Update existing mirror (much faster!)
brew ruby bin/brew-mirror -d ./mirror -f wget,jq --update --prune

# Mirror with custom taps using shortcuts
brew ruby bin/brew-mirror -d ./mirror --taps core,cask,fonts

# Mirror formulas only (fast, no casks)
brew ruby bin/brew-mirror -d ./mirror -f wget,jq --taps core
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

# Install cask (GUI application)
ruby bin/brew-offline-install --cask firefox

# Install multiple packages
ruby bin/brew-offline-install jq htop wget
```

### brew-mirror-verify

Verifies mirror integrity and completeness.

**Usage:**
```bash
brew ruby mirror/bin/brew-mirror-verify [options] <mirror-directory>
```

**Options:**
- `--verbose` - Show detailed verification output
- `--checksums` - Verify file checksums (slow)

**Examples:**
```bash
# Quick verification
brew ruby bin/brew-mirror-verify /path/to/mirror

# Detailed verification
brew ruby bin/brew-mirror-verify --verbose /path/to/mirror

# Full verification with checksums
brew ruby bin/brew-mirror-verify --checksums /path/to/mirror
```

### brew-offline-curl

The `curl` shim that rewrites HTTP(S) URLs to point to the local mirror.

**Note:** Called automatically by `brew-offline-install`. You don't need to call it directly, but it must be in your `$PATH`.

### brew-offline-git

The `git` shim that rewrites Git repository URLs to point to the local mirror.

**Note:** Called automatically by `brew-offline-install`. You don't need to call it directly, but it must be in your `$PATH`.

## Configuration

### Client Configuration

Create `~/.offlinebrew/config.json`:

```json
{
  "baseurl": "http://mirror-server:8000"
}
```

That's it! `brew-offline-install` handles the rest automatically.

### Mirror Configuration

`brew-mirror` generates these files in the mirror directory:

**config.json** - Mirror metadata (auto-generated)
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

**urlmap.json** - URL to file mapping (auto-generated)
```json
{
  "https://example.com/foobar-4.0.tar.gz": "f2c1e86ca...e07.tar.gz",
  "https://github.com/user/repo.git": "abc123def...456"
}
```

**manifest.json** - Mirror contents (auto-generated)
```json
{
  "created_at": "2025-11-13T...",
  "taps": {...},
  "statistics": {
    "total_formulae": 100,
    "total_casks": 50,
    "total_files": 500,
    "total_size_bytes": 12345678900
  },
  "formulae": [...],
  "casks": [...]
}
```

**manifest.html** - Human-readable mirror report (auto-generated)

Open this file in a browser to see what's in your mirror!

**identifier_cache.json** - Git repository cache (auto-generated)

Tracks Git repositories to prevent duplicate downloads on incremental updates.

## Serving the Mirror

Any HTTP server works. Examples:

### Python (built-in, simple)
```bash
cd /path/to/mirror
python3 -m http.server 8000
```

### Nginx (production-ready)
```nginx
server {
  listen 8000;
  root /path/to/mirror;
  autoindex on;

  # Optional: Enable gzip compression
  gzip on;
  gzip_types application/json text/plain;
}
```

### Apache (production-ready)
```apache
<VirtualHost *:8000>
    DocumentRoot /path/to/mirror
    <Directory /path/to/mirror>
        Options +Indexes
        Require all granted
    </Directory>
</VirtualHost>
```

## Incremental Updates

Use `--update` to add new packages without re-downloading:

```bash
# Create initial mirror
brew ruby bin/brew-mirror -d ./mirror -f wget -s 1

# Later, add more packages (wget is skipped!)
brew ruby bin/brew-mirror -d ./mirror -f wget,jq,htop --update -s 1

# Update after tap commits change
brew ruby bin/brew-mirror -d ./mirror -f wget,jq --update --prune
```

The `--prune` flag reports what changed but doesn't remove files (manual cleanup required).

## Point-in-Time Snapshots

Mirrors are point-in-time snapshots tied to specific tap commits:

```json
{
  "taps": {
    "homebrew/homebrew-core": {
      "commit": "abc123...",  # This exact commit
      "type": "formula"
    }
  }
}
```

This ensures reproducible installations - installing from the mirror today gives you the same package versions as installing next month.

## Troubleshooting

See [../TROUBLESHOOTING.md](../TROUBLESHOOTING.md) for common issues.

## Architecture

See [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) for technical details on how URL rewriting works.

## Testing

Run the integration tests:
```bash
cd mirror/test
./run_integration_tests.sh
```

## Migration from v1.x

See [../MIGRATION.md](../MIGRATION.md) for upgrading from older versions.
