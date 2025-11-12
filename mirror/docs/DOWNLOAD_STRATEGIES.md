# Download Strategy Support

This document describes which Homebrew download strategies are supported by offlinebrew and provides guidance on adding support for new strategies.

## Overview

Homebrew uses "download strategies" to fetch formula source code and resources. Each strategy handles a different type of download (HTTP, Git, SVN, etc.). Offlinebrew supports a subset of these strategies that:

1. Can be mirrored offline (no required runtime dependencies)
2. Can be served via HTTP
3. Cover >99% of Homebrew formulae

## Supported Strategies

### ✅ CurlDownloadStrategy

**Type**: HTTP/HTTPS downloads
**Coverage**: ~85% of formulae
**Identifier**: SHA256 checksum from formula

**Description**: The most common strategy. Downloads tarballs, zip files, and other archives via HTTP/HTTPS.

**Examples**: `jq`, `wget`, `tree`, `nginx`

**Mirror Requirements**:
- Simple HTTP serving
- File renamed using checksum as identifier

---

### ✅ CurlApacheMirrorDownloadStrategy

**Type**: Apache Mirror Network downloads
**Coverage**: ~1% of formulae
**Identifier**: SHA256 checksum from formula

**Description**: Downloads from Apache mirror networks, which use special URL redirection.

**Examples**: `apr`, `httpd`, `tomcat`

**Mirror Requirements**:
- Simple HTTP serving
- File renamed using checksum as identifier

---

### ✅ NoUnzipCurlDownloadStrategy

**Type**: HTTP/HTTPS downloads without auto-extraction
**Coverage**: <1% of formulae
**Identifier**: SHA256 checksum from formula

**Description**: Like CurlDownloadStrategy but doesn't automatically extract archives.

**Examples**: Rare, used for pre-extracted or special-format archives

**Mirror Requirements**:
- Simple HTTP serving
- File renamed using checksum as identifier

---

### ✅ GitDownloadStrategy

**Type**: Git repository clones
**Coverage**: ~10% of formulae
**Identifier**: SHA256(url@revision) - deterministic

**Description**: Clones Git repositories at specific commits/tags.

**Examples**: Formulae that track HEAD or specific git commits

**Mirror Requirements**:
- Git repository served via HTTP
- `git update-server-info` for dumb HTTP protocol
- Deterministic identifier based on URL and revision (Task 3.2)

**Special Handling**:
- Requires `resolve_git_revision()` to extract commit
- Tracked in `identifier_cache.json`
- May need unshallowing if repository is shallow

---

### ✅ GitHubGitDownloadStrategy

**Type**: GitHub-specific Git clones
**Coverage**: ~5% of formulae
**Identifier**: SHA256(url@revision) - deterministic

**Description**: Specialized Git strategy for GitHub repositories.

**Examples**: GitHub-hosted projects

**Mirror Requirements**:
- Same as GitDownloadStrategy
- Deterministic identifier based on URL and revision (Task 3.2)

**Special Handling**:
- Same as GitDownloadStrategy

---

## Unsupported Strategies

### ❌ SubversionDownloadStrategy (SVN)

**Reason**: Requires `svn` command-line tool
**Coverage**: <0.1% of formulae
**Examples**: `clang-format` (historical)

**Why not supported**:
- Requires Subversion to be installed
- Complex repository structure
- Very rare in modern Homebrew

**Workaround**: Manual download or skip these formulae

---

### ❌ MercurialDownloadStrategy (Hg)

**Reason**: Requires `hg` command-line tool
**Coverage**: <0.01% of formulae
**Examples**: Rare, mostly obsolete

**Why not supported**:
- Requires Mercurial to be installed
- Extremely rare in Homebrew
- Most projects have migrated to Git

**Workaround**: Manual download or skip these formulae

---

### ❌ CVSDownloadStrategy

**Reason**: Requires `cvs` command-line tool
**Coverage**: <0.01% of formulae
**Examples**: Obsolete projects only

**Why not supported**:
- Requires CVS to be installed
- Obsolete version control system
- Almost no modern projects use CVS

**Workaround**: Manual download or skip these formulae

---

### ❌ BazaarDownloadStrategy

**Reason**: Requires `bzr` command-line tool
**Coverage**: <0.01% of formulae

**Why not supported**:
- Requires Bazaar to be installed
- Obsolete version control system

**Workaround**: Manual download or skip these formulae

---

### ❌ FossilDownloadStrategy

**Reason**: Requires `fossil` command-line tool
**Coverage**: <0.01% of formulae

**Why not supported**:
- Requires Fossil SCM to be installed
- Very rare in Homebrew

**Workaround**: Manual download or skip these formulae

---

## Strategy Discovery

To discover which strategies are available in your Homebrew installation:

```bash
brew ruby mirror/test/discover_strategies.rb
```

This script will:
- List all available download strategies
- Categorize them (Curl-based, Git-based, SCM, etc.)
- Show which are supported/unsupported in offlinebrew
- Provide recommendations

## Adding Support for New Strategies

If Homebrew adds new strategies or you want to extend offlinebrew:

### Step 1: Identify the Strategy

Run the discovery script to see if it exists:
```bash
brew ruby mirror/test/discover_strategies.rb
```

### Step 2: Determine Feasibility

Can the strategy be supported offline?
- ✅ HTTP/HTTPS downloads → Easy to support
- ✅ Git clones → Already supported pattern
- ❌ Requires external tools (svn, hg, cvs) → Hard to support

### Step 3: Add to brew-mirror

Edit `mirror/bin/brew-mirror`:

```ruby
BREW_OFFLINE_DOWNLOAD_STRATEGIES = [
  CurlDownloadStrategy,
  CurlApacheMirrorDownloadStrategy,
  NoUnzipCurlDownloadStrategy,
  GitDownloadStrategy,
  GitHubGitDownloadStrategy,
  NewStrategy,  # Add here
].freeze
```

### Step 4: Update sensible_identifier if Needed

If the new strategy doesn't have checksums (like Git):

```ruby
def sensible_identifier(strategy, checksum = nil, url = nil)
  case strategy
  when GitDownloadStrategy, GitHubGitDownloadStrategy, NewGitLikeStrategy
    # Generate deterministic identifier
    require "digest"
    revision = resolve_git_revision(strategy)
    Digest::SHA256.hexdigest("#{url}@#{revision}")
  else
    checksum.to_s
  end
end
```

### Step 5: Add Special Handling if Needed

If the strategy needs prep (like `git update-server-info`):

```ruby
def prep_location!(strategy, location)
  case strategy
  when GitDownloadStrategy, GitHubGitDownloadStrategy, NewGitStrategy
    Dir.chdir location do
      # Prep work here
    end
  end
end
```

### Step 6: Test

```bash
# Find a formula that uses the new strategy
brew info <formula>

# Try mirroring it
brew ruby mirror/bin/brew-mirror -f <formula> -d /tmp/test
```

### Step 7: Add Integration Test

Add test to `mirror/test/integration/test_download_strategies.rb`:

```ruby
def test_new_strategy
  Dir.mktmpdir do |tmpdir|
    result = run_brew_mirror(
      brew_mirror_path,
      ["-f", "formula-using-new-strategy", "-d", tmpdir]
    )
    assert result[:success], "Should mirror successfully"
  end
end
```

## Coverage Statistics

Based on analysis of Homebrew formulae (as of 2024):

| Strategy | Coverage | Supported | Notes |
|----------|----------|-----------|-------|
| CurlDownloadStrategy | ~85% | ✅ Yes | Most common |
| GitDownloadStrategy | ~10% | ✅ Yes | Git repos |
| GitHubGitDownloadStrategy | ~5% | ✅ Yes | GitHub repos |
| CurlApacheMirrorDownloadStrategy | ~1% | ✅ Yes | Apache mirrors |
| NoUnzipCurlDownloadStrategy | <1% | ✅ Yes | Rare |
| SubversionDownloadStrategy | <0.1% | ❌ No | Requires svn |
| Other SCM strategies | <0.1% | ❌ No | Requires tools |

**Total Coverage**: **>99%** of Homebrew formulae can be mirrored offline

## Future Considerations

### Bottle Support

Homebrew "bottles" are pre-compiled binaries. They use:
- `CurlBottleDownloadStrategy`
- `LocalBottleDownloadStrategy`

These could be added to offlinebrew for faster installations, but would require:
- Platform-specific handling (Intel vs Apple Silicon)
- macOS version checking
- Larger mirror storage

### Downloader API Evolution

Homebrew's downloader API may change over time. The `sensible_identifier` function
uses defensive programming to handle API differences:

```ruby
# Try multiple API methods
if downloader.respond_to?(:resolved_ref) && downloader.resolved_ref
  # Modern API
elsif downloader.respond_to?(:ref) && downloader.ref
  # Older API
else
  # Fallback
end
```

## Troubleshooting

### "Unmirrorable resource" Warning

```
Warning: formula has an unmirrorable resource: https://... (SubversionDownloadStrategy)
```

**Solution**: This formula uses an unsupported strategy. Either:
1. Skip this formula
2. Manually download the resource
3. Add support for the strategy (if feasible)

### Git Repository Issues

```
Error: shallow repository detected
```

**Solution**: Offlinebrew automatically unshallows repositories. If this fails:
1. Check git connectivity
2. Verify repository URL is accessible
3. Check disk space

### Checksum Mismatches

```
Error: SHA256 mismatch
```

**Solution**: Formula checksum doesn't match downloaded file:
1. Check network connectivity
2. Verify formula hasn't been updated
3. Re-download with `--force`

## References

- [Homebrew Download Strategy Source](https://github.com/Homebrew/brew/blob/master/Library/Homebrew/download_strategy.rb)
- [Homebrew Formula Documentation](https://docs.brew.sh/Formula-Cookbook)
- [Offlinebrew Integration Tests](../test/integration/test_download_strategies.rb)
