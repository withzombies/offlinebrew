# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**offlinebrew** creates offline mirrors of Homebrew packages for air-gapped and low-connectivity environments. It uses a mirror-based approach with URL rewriting to redirect all Homebrew downloads to a local HTTP server.

**Key capabilities:**
- Mirror both formulas (CLI tools) and casks (GUI apps)
- Automatic dependency resolution with `--with-deps`
- Incremental updates (10-100x faster than full mirrors)
- Point-in-time snapshots with commit pinning
- Mirror verification and integrity checking
- Support for multiple taps (core, cask, fonts, custom)

**Requirements:**
- macOS 12.0+ (Apple Silicon preferred)
- Homebrew 5.0+ (required - older versions not supported)
- Ruby 3.0+ (included with macOS)

## Repository Structure

```
offlinebrew/
├── bin/
│   └── brew-offline           # Main CLI entry point (bash wrapper)
├── mirror/                    # Core implementation directory
│   ├── bin/                   # Ruby implementation scripts
│   │   ├── brew-mirror        # Create/update mirrors (needs brew ruby)
│   │   ├── brew-mirror-verify # Verify mirror integrity (needs brew ruby)
│   │   └── brew-offline-install # Install from mirror (regular ruby)
│   ├── lib/                   # Ruby libraries
│   │   ├── dependency_resolver.rb   # BFS-based dependency resolution
│   │   ├── bottle_downloader.rb     # Download pre-built bottles
│   │   ├── api_generator.rb         # Generate Homebrew API files
│   │   ├── tap_manager.rb           # Manage Homebrew taps
│   │   ├── safe_shell.rb            # Shell injection protection
│   │   ├── macos_security.rb        # macOS security hardening
│   │   ├── homebrew_paths.rb        # Homebrew path utilities
│   │   ├── container_helpers.rb     # Docker/container support
│   │   ├── cask_helpers.rb          # Cask-specific utilities
│   │   ├── download_helpers.rb      # Download utilities
│   │   ├── url_helpers.rb           # URL rewriting/mapping
│   │   └── offlinebrew_config.rb    # Config file management
│   └── test/                  # Unit and integration tests
│       ├── integration/       # End-to-end workflow tests
│       └── lib/               # Library-specific tests
└── test/integration/phases/   # Tart VM integration tests
```

## Development Commands

### Running Tests

```bash
# Run Tart VM end-to-end integration tests (10-15 min)
make test

# Run individual test phases (in order)
make test-setup-vm          # Create and start Tart VM
make test-install-homebrew  # Install Homebrew in VM
make test-install-offlinebrew
make test-create-mirror     # Mirror packages (formulas, bottles, casks)
make test-verify-install    # Install from mirror and verify

# Clean up test environment
make clean                  # Delete VM and artifacts

# Run unit tests for mirror functionality
cd mirror && ruby test/security_test.rb
cd mirror && ruby test/test_dependency_resolver.rb
```

**Integration tests require:**
- Tart CLI installed (`brew install tart`)
- ~50GB disk space for VM and mirror
- macOS host (Apple Silicon or Intel)

### Manual Testing

```bash
# Create a mirror (with dependencies)
bin/brew-offline mirror -d /tmp/test-mirror -f wget,jq --with-deps --casks firefox -s 0.5

# Verify mirror integrity
bin/brew-offline verify /tmp/test-mirror

# Install from mirror (requires mirror to be served via HTTP)
cd /tmp/test-mirror && python3 -m http.server 8000 &
bin/brew-offline install wget
bin/brew-offline install --cask firefox
```

### Debug Mode

```bash
# Enable offlinebrew debug output
export BREW_OFFLINE_DEBUG=1
bin/brew-offline mirror -d /tmp/mirror -f wget

# Enable Homebrew verbose output
export HOMEBREW_VERBOSE=1
bin/brew-offline install wget
```

## Architecture

### Command Flow

1. **bin/brew-offline** (bash wrapper)
   - Entry point for all commands
   - Dispatches to appropriate Ruby scripts in mirror/bin/
   - Handles `brew ruby` vs regular `ruby` invocation

2. **mirror/bin/brew-mirror** (requires `brew ruby`)
   - Creates offline mirrors by downloading packages
   - Uses Homebrew internals (Formula, Cask, Tap APIs)
   - Generates URL mapping files and manifests
   - Calls dependency_resolver.rb for `--with-deps`

3. **mirror/bin/brew-offline-install** (regular ruby)
   - Installs packages from offline mirror
   - Reads config from `~/.offlinebrew/config.json`
   - Rewrites Homebrew download URLs to point to mirror

4. **mirror/bin/brew-mirror-verify** (requires `brew ruby`)
   - Validates mirror integrity
   - Checks for missing files, corrupt downloads
   - Verifies checksums

### Key Concepts

**brew ruby vs ruby:**
- `brew-mirror` and `brew-mirror-verify` need `brew ruby` to access Homebrew's internal APIs (Formula, Cask, Tap classes)
- `brew-offline-install` uses regular `ruby` since it only needs to rewrite URLs and call `brew install`

**URL Rewriting:**
- Mirror creates `url_map.json` mapping original URLs to local paths
- Install command sets up HTTP server redirects
- All Homebrew downloads transparently fetch from local mirror

**Dependency Resolution:**
- Uses breadth-first search (BFS) to resolve dependencies
- Handles runtime, build, optional, and recommended dependencies
- Detects circular dependencies
- Returns deduplicated list of all required packages

**Download Strategies:**
- Supports `CurlDownloadStrategy`, `GitDownloadStrategy`, `CurlBottleDownloadStrategy`
- Covers >99% of Homebrew packages
- Falls back gracefully for unsupported strategies

**Security Hardening:**
- All shell commands use `SafeShell` module (prevents injection)
- Path traversal protection in file operations
- XSS protection in HTML manifest generation
- Code signature verification for macOS apps

## Testing

**Test framework:** Minitest

**Test structure:**
- Unit tests: `mirror/test/test_*.rb` (22 files)
- Integration tests: `mirror/test/integration/test_*.rb`
- E2E tests: `test/integration/phases/*.sh` (Tart VM-based)

**Test naming convention:**
```ruby
class SecurityTest < Minitest::Test
  def test_shell_injection_protection_with_semicolon
    # Test implementation
  end
end
```

**Running individual tests:**
```bash
cd mirror
ruby test/security_test.rb
ruby test/test_dependency_resolver.rb
ruby -Itest test/integration/test_full_workflow.rb
```

## Important Implementation Notes

### When to use `brew ruby`

- **Use `brew ruby`** for scripts that access Homebrew internals (Formula, Cask, Tap classes)
  - Example: `brew ruby -- mirror/bin/brew-mirror`
  - Files: `brew-mirror`, `brew-mirror-verify`

- **Use regular `ruby`** for standalone scripts
  - Example: `ruby mirror/bin/brew-offline-install`
  - Files: `brew-offline-install`, test files

### Security Requirements

All shell commands MUST use `SafeShell` module to prevent injection:

```ruby
# WRONG - vulnerable to shell injection
system("mkdir -p #{user_input}")

# CORRECT - uses SafeShell wrapper
SafeShell.mkdir_p(user_input)
```

See `mirror/lib/safe_shell.rb` and `mirror/test/security_test.rb` for examples.

### Dependency Resolution

When implementing features that involve dependencies, use `DependencyResolver`:

```ruby
require_relative '../lib/dependency_resolver'

# Resolve formulas with runtime dependencies only
formulas = DependencyResolver.resolve_formulas(["wget", "jq"])

# Resolve with build dependencies
formulas = DependencyResolver.resolve_formulas(["wget"], include_build: true)

# Resolve casks (returns {casks: [...], formulas: [...]})
result = DependencyResolver.resolve_casks(["firefox"])
```

See `mirror/lib/dependency_resolver.rb:1-60` for implementation details.

### Error Handling Patterns

The codebase uses Homebrew's output methods:

```ruby
ohai "Starting mirror creation..."  # Info messages
opoo "Warning: missing dependency"   # Warnings
onoe "Error: failed to download"     # Non-fatal errors
odie "Fatal error: aborting"         # Fatal errors (aborts)
odebug "Debug info"                  # Debug output (if HOMEBREW_DEBUG=1)
```

These are defined in `mirror/bin/brew-mirror:24-44` for compatibility.

### Path Handling

Use `HomebrewPaths` module for all Homebrew-related paths:

```ruby
require_relative '../lib/homebrew_paths'

HomebrewPaths.homebrew_prefix      # /opt/homebrew or /usr/local
HomebrewPaths.homebrew_cache_dir   # ~/Library/Caches/Homebrew
HomebrewPaths.homebrew_cellar      # /opt/homebrew/Cellar
```

## Common Workflows

### Adding a new mirror option

1. Add option to OptionParser in `mirror/bin/brew-mirror`
2. Update help text in `bin/brew-offline`
3. Implement feature in appropriate `mirror/lib/*.rb` module
4. Add test in `mirror/test/test_*.rb`
5. Update `mirror/README.md` documentation

### Adding a new security check

1. Implement check in `mirror/lib/safe_shell.rb` or `mirror/lib/macos_security.rb`
2. Add test cases in `mirror/test/security_test.rb`
3. Ensure all existing tests still pass

### Debugging integration tests

Integration tests run in Tart VMs and can take 10-15 minutes:

```bash
# Run with logging
make test 2>&1 | tee /tmp/test-run.log

# Check individual phases
make test-setup-vm
tart run offlinebrew-test  # Connect to VM
make test-create-mirror

# Clean up stuck VMs
make clean
ps aux | grep tart  # Check for stuck processes
```

## Homebrew 5.0+ Compatibility

This project requires Homebrew 5.0+. Key changes from 4.x:

- API-based formula/cask loading (not Git-based)
- Bottle format changes
- New download strategy classes
- Updated tap structure

When implementing new features, verify compatibility with Homebrew 5.0+ APIs.
