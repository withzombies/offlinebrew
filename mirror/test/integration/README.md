# Integration Test Suite

Comprehensive end-to-end integration tests for offlinebrew.

## Test Suites

### 1. Full Workflow Tests (`test_full_workflow.rb`)
End-to-end workflow testing:
- ✅ Full mirror → serve → install workflow
- ✅ Config-only mode
- ✅ REAL_HOME environment variable handling
- ✅ Config validation

**Tests**: 4 | **Runtime**: ~2 minutes

### 2. URL Shim Tests (`test_url_shims.rb`)
URL redirection and mapping:
- ✅ brew-offline-curl URL redirection
- ✅ URLmap completeness
- ✅ URL matching (query params, fragments)
- ✅ Multiple formulae mirroring
- ✅ Config-only mode validation
- ✅ Tap commit recording
- ✅ Invalid config rejection

**Tests**: 6 | **Runtime**: ~30 seconds

### 3. Error Handling Tests (`test_error_handling.rb`)
Error cases and edge conditions:
- ✅ Non-existent formula
- ✅ Non-existent directory
- ✅ Missing config
- ✅ Unreachable mirror
- ✅ Corrupted URLmap
- ✅ Backward compatible config
- ✅ HEAD-only formula
- ✅ Multi-tap configuration

**Tests**: 8 | **Runtime**: ~30 seconds

### 4. Download Strategy Tests (`test_download_strategies.rb`)
Different download strategies:
- ✅ **CurlDownloadStrategy** - HTTP/HTTPS downloads (jq, wget, tree)
- ✅ **GitDownloadStrategy** - Git repositories with deterministic identifiers
- ✅ **GitHubGitDownloadStrategy** - GitHub-specific with deterministic identifiers
- ✅ **CurlApacheMirrorDownloadStrategy** - Apache mirrors
- ✅ **NoUnzipCurlDownloadStrategy** - Pre-extracted archives
- ✅ Formulae with resources (bundled dependencies)
- ✅ Formulae with patches
- ✅ **Git deterministic identifiers** (Task 3.2 - FIXED)
- ❌ **Unsupported strategies** (SVN, Mercurial, CVS) - expected to skip

**Tests**: 8 | **Runtime**: ~1 minute

### 5. Real-World Formulae Tests (`test_real_world_formulae.rb`)
Complex real-world scenarios:
- ✅ Python formulae with resources
- ✅ Formulae with multiple patches
- ✅ Large downloads
- ✅ URL stability across mirrors
- ✅ Apache mirror formulae
- ✅ Versioned URLs

**Tests**: 6 | **Runtime**: ~1 minute (fast), ~5 minutes (with slow tests)

### 6. Mirror Verification Tests (`test_verification.rb`)
Mirror integrity and verification (Task 4.1):
- ✅ Verify valid mirror
- ✅ Verify with --verify flag
- ✅ Detect missing files
- ✅ Detect missing config
- ✅ Verbose verification output
- ✅ Git cache verification
- ✅ Help flag documentation

**Tests**: 7 | **Runtime**: ~30 seconds

## Running Tests

```bash
# Run all tests (default)
./run_integration_tests.sh

# Run specific test suite
./run_integration_tests.sh full        # Full workflow only
./run_integration_tests.sh url         # URL shims only
./run_integration_tests.sh error       # Error handling only
./run_integration_tests.sh download    # Download strategies only
./run_integration_tests.sh real-world  # Real-world formulae only
./run_integration_tests.sh verify      # Mirror verification only

# Run with slow tests included
RUN_SLOW_TESTS=1 ./run_integration_tests.sh real-world
```

## Coverage Summary

### Supported Download Strategies ✅
| Strategy | Tested | Example Formulae |
|----------|--------|------------------|
| CurlDownloadStrategy | ✅ | jq, wget, tree |
| GitDownloadStrategy | ✅ | (git repos) |
| GitHubGitDownloadStrategy | ✅ | (GitHub repos) |
| CurlApacheMirrorDownloadStrategy | ✅ | apr, httpd |
| NoUnzipCurlDownloadStrategy | ✅ | (pre-extracted) |

### Unsupported Download Strategies ❌
| Strategy | Status | Notes |
|----------|--------|-------|
| SubversionDownloadStrategy | ❌ Not supported | e.g., clang-format |
| MercurialDownloadStrategy | ❌ Not supported | Rare |
| CVSDownloadStrategy | ❌ Not supported | Very rare |
| FossilDownloadStrategy | ❌ Not supported | Very rare |

### Formula Characteristics Tested ✅
- ✅ Simple formulae (single tarball)
- ✅ Formulae with resources (Python packages, etc.)
- ✅ Formulae with patches
- ✅ Git repositories
- ✅ Apache mirror downloads
- ✅ Multiple download strategies in one mirror
- ✅ Large downloads
- ✅ Versioned URLs

### Edge Cases Tested ✅
- ✅ Empty urlmap detection
- ✅ Missing configuration
- ✅ Corrupted JSON
- ✅ Unreachable servers
- ✅ Non-existent formulae
- ✅ Non-existent directories
- ✅ Case-sensitive tap names
- ✅ Backward compatible configs
- ✅ REAL_HOME environment override
- ✅ Config-only mode
- ✅ Multi-tap configuration

## Known Limitations

### ~~Git Repository UUID Collision~~ ✅ FIXED (Task 3.2)
**Previous Issue**: Git repositories used random UUID identifiers. If the same
repository was mirrored twice, it got a different UUID each time, causing duplicates.

**Fix**: Git repositories now use deterministic SHA256 identifiers based on
`url@revision`. The same repository at the same commit always gets the same
identifier. An `identifier_cache.json` file tracks all Git repositories for
transparency and debugging.

**Status**: ✅ Complete - Task 3.2 implemented

**Test**: `test_git_repository_deterministic_identifiers` validates the fix

### Unsupported Download Strategies
Some formulae use download strategies we don't support:
- **SVN** (SubversionDownloadStrategy) - e.g., clang-format
- **Mercurial** (MercurialDownloadStrategy)
- **CVS** (CVSDownloadStrategy)

**Behavior**: These formulae are skipped with a warning

**Test**: `test_unsupported_download_strategy` validates graceful skipping

## Test Statistics

| Metric | Count |
|--------|-------|
| **Total Test Files** | 6 |
| **Total Test Cases** | 39+ |
| **Test Lines of Code** | ~2,100 |
| **Coverage Areas** | 25+ |
| **Download Strategies Tested** | 5 |
| **Formula Types Tested** | 10+ |
| **Edge Cases Tested** | 15+ |
| **Verification Checks** | 7 |

## CI/CD Integration

Integration tests run on:
- ✅ macOS (Apple Silicon)
- ✅ Real Homebrew installation
- ✅ Every push to `claude/*` branches
- ✅ All pull requests

**Runtime**: ~5-10 minutes total

## Requirements

- Homebrew installed
- Network access (for downloading)
- ~100MB free disk space
- Ruby 3.0+
- WEBrick gem (auto-installed)

## Debugging

Enable verbose output:
```bash
HOMEBREW_VERBOSE=1 ./run_integration_tests.sh
```

Enable debug output in brew-offline-install:
```bash
BREW_OFFLINE_DEBUG=1 brew-offline-install jq
```

## Adding New Tests

1. Create test file in `mirror/test/integration/test_*.rb`
2. Inherit from `Minitest::Test`
3. Use `TestHelper` methods (run_brew_mirror, run_command, etc.)
4. Add to `run_integration_tests.sh`
5. Document in this README

Example:
```ruby
class TestNewFeature < Minitest::Test
  def test_something
    Dir.mktmpdir do |tmpdir|
      result = run_brew_mirror(brew_mirror_path, ["-f", "jq", "-d", tmpdir])
      assert result[:success], "Should succeed"
    end
  end
end
```

## Download Strategy Documentation

For comprehensive information about supported and unsupported download strategies, see:
- [`mirror/docs/DOWNLOAD_STRATEGIES.md`](../../docs/DOWNLOAD_STRATEGIES.md)
- Strategy discovery script: `mirror/test/discover_strategies.rb`

**Quick Reference**:
- ✅ Supported: CurlDownloadStrategy, GitDownloadStrategy, GitHubGitDownloadStrategy, Apache mirrors
- ❌ Unsupported: SVN, Mercurial, CVS, Bazaar, Fossil (require external tools)
- 📊 Coverage: >99% of Homebrew formulae

## Future Test Additions

Potential areas for expansion:
- [ ] Cask-specific tests (once Phase 2 is deployed)
- [ ] Multi-tap font tests
- [ ] Version-specific mirroring
- [ ] Incremental mirror updates (Phase 4)
- [ ] Manifest generation (Phase 4)
- [ ] Performance benchmarks
- [ ] Stress tests (hundreds of formulae)
- [ ] Bottle (binary package) support testing
