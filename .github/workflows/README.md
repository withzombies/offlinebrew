# GitHub Actions Test Suite

This directory contains the CI/CD workflows for offlinebrew.

## Current Workflows

### test.yml - Main Test Suite

Tests the codebase across multiple Ruby versions on macOS (Apple Silicon).

#### Active Jobs

**1. test-macos-features** (Ruby 3.0, 3.1, 3.2)
- **Purpose**: Comprehensive testing of Phase 0 (Security) and Task 1.1 (Path Detection)
- **What it tests**:
  - Homebrew installation detection
  - Security test suite (40 tests, full coverage on macOS)
  - Path detection with real Homebrew installation
  - SafeShell module (shell escaping, timeouts, path safety)
  - MacOSSecurity module (code signatures, checksums)
  - brew-mirror and brew-offline-install path validation
- **Why**: Validates all security features and dynamic path detection work correctly on actual macOS with Homebrew
- **Time**: ~2-3 minutes per Ruby version

**2. test-fast** (Ruby 3.0, 3.1, 3.2)
- **Purpose**: Quick security test run
- **What it tests**: Security test suite only
- **Why**: Fast feedback on security regression
- **Time**: ~1 minute per Ruby version

#### Commented Out Jobs (Future Implementation)

**test-integration** - Disabled until Phase 2-5
- Will test formula/cask mirroring integration
- Requires complete implementation

**verify-formulae** - Disabled until Phase 2+
- Will test end-to-end formula mirroring and installation
- Requires: Mirror small formula → Serve via HTTP → Install from mirror → Verify it works

**verify-casks** - Disabled until Phase 2
- Will test end-to-end cask mirroring and installation
- Requires: Mirror cask → Serve via HTTP → Install from mirror → Verify signature & functionality

## Testing Philosophy

### Security-First Approach
All security tests run on macOS to ensure:
- Code signature verification works (macOS only)
- Notarization checking works (macOS only)
- Shell injection protection is validated
- Path traversal protection is validated

### Progressive Enhancement
Tests are added as features are implemented:
- ✅ Phase 0: Security tests active
- ✅ Task 1.1: Path detection tests active
- ⏳ Phase 2: Integration tests will be enabled
- ⏳ Phase 3-5: End-to-end tests will be enabled

### Platform Coverage
- **macOS (Apple Silicon)**: All tests
  - Native platform for Homebrew
  - Can test code signatures, notarization
  - Real Homebrew installation available

## Running Tests Locally

### Security Tests
```bash
# Full security test suite
ruby mirror/test/security_test.rb --verbose

# Specific test
ruby mirror/test/security_test.rb -n test_shell_injection_protection_with_semicolon
```

### Path Detection Tests
```bash
ruby mirror/test/test_paths.rb
```

### Module Tests
```bash
# Test SafeShell
ruby -r ./mirror/lib/safe_shell -e 'puts SafeShell.execute("echo", "test", timeout: 5)'

# Test HomebrewPaths
ruby -r ./mirror/lib/homebrew_paths -e 'puts HomebrewPaths.homebrew_prefix'

# Test MacOSSecurity (macOS only)
ruby -r ./mirror/lib/macos_security -e 'puts MacOSSecurity.verify_signature("/Applications/Safari.app")'
```

## Test Results

### Current Status
- ✅ 40 security tests pass on macOS
- ✅ 0 failures, 0 errors
- ✅ Path detection works across architectures
- ✅ All modules load successfully

### Coverage Metrics
- Security tests: 40 tests, 63 assertions
- Platform tests: macOS ✓, Linux ✗ (by design)
- Ruby versions: 3.0, 3.1, 3.2 ✓

## Adding New Tests

When implementing new phases/tasks:

1. **Add tests first** (TDD approach)
2. **Update this README** with new test descriptions
3. **Enable commented jobs** as features are completed
4. **Add new jobs** for new feature areas

Example:
```yaml
test-new-feature:
  name: Test New Feature
  runs-on: macos-latest
  steps:
    - uses: actions/checkout@v4
    - name: Test the feature
      run: ruby mirror/test/new_feature_test.rb
```

## Troubleshooting CI Failures

### "Homebrew not found"
- Should not happen on macos-latest runners
- Check if Homebrew installation step completed

### "Security tests failing"
- Check if code signature tests are finding system apps
- Verify SafeShell timeouts are appropriate for CI environment

### "Path detection tests failing"
- Verify homebrew-core tap was installed
- Check brew --prefix output in logs

### "Timeout errors"
- Increase timeout values in SafeShell calls
- CI may be slower than local machines
