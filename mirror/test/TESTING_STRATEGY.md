# TDD Testing Strategy for Offlinebrew Executables

## Current State: Legacy Code Situation

**Reality Check:** The executables (`brew-mirror`, `brew-offline-install`, `brew-offline-curl`) were written before tests. This violates TDD principles.

**What This Means:**
- We cannot claim these were developed with TDD
- Tests written now verify current behavior, not intended behavior
- We're adding regression tests, not driving design through tests

**Going Forward:**
- All new features: RED → GREEN → REFACTOR (no exceptions)
- All bug fixes: Write failing test first
- All refactoring: Existing tests must stay green

## Test Framework

### Ruby Test Framework: Minitest

Using Ruby's built-in **Minitest** framework:
- Lightweight, built into Ruby
- No external dependencies
- Simple assertion syntax
- Good for executable testing

### Test Organization

```
mirror/test/
├── test_helper.rb           # Shared test utilities
├── executable/              # Executable tests (NEW)
│   ├── test_brew_mirror.rb
│   ├── test_brew_offline_install.rb
│   └── test_brew_offline_curl.rb
├── lib/                     # Library tests (EXISTING)
│   ├── test_url_helpers.rb
│   ├── test_container_helpers.rb
│   └── test_download_helpers.rb
└── integration/             # Integration tests (FUTURE)
    └── test_full_workflow.rb
```

## Executable Invocation: Critical Discovery

**IMPORTANT:** The executables have different shebangs and require different invocation methods:

### brew-mirror
- Shebang: `#!/usr/bin/env brew ruby` (broken for direct execution)
- **CORRECT INVOCATION**: `brew mirror` (Homebrew external command pattern)
- Supports all options (short and long): `-f`, `--formulae`, `-d`, `--directory`, `-c`, `--config-only`

```bash
# ✓ CORRECT: Use as Homebrew external command
brew mirror -f jq -d /tmp/mirror --config-only

# ✓ CORRECT: Long options work fine
brew mirror --formulae jq --directory /tmp/mirror

# Requires brew-mirror executable in PATH
PATH=/path/to/bin:$PATH brew mirror -f jq -d /tmp
```

### brew-offline-install
- Shebang: `#!/usr/bin/env ruby` (normal Ruby script)
- Can execute directly: `./bin/brew-offline-install jq`
- Loads Homebrew libraries at runtime

**Why `brew mirror` Works:**
- Homebrew external commands follow pattern: `brew-<name>` executable → `brew <name>` command
- When you run `brew mirror`, Homebrew finds `brew-mirror` in PATH and executes it
- The shebang `#!/usr/bin/env brew ruby` is used by Homebrew to load libraries
- Arguments are passed directly to the script WITHOUT brew ruby's option parser interfering

**Why Previous Approaches Failed:**
- `./bin/brew-mirror` (direct): env can't find multi-word command "brew ruby"
- `brew ruby bin/brew-mirror -f jq`: brew ruby's OptionParser consumed `-f` before script ran
- **Solution**: Use `brew mirror` which bypasses brew ruby's CLI parser

**Key Discovery:**
The CI example `brew ruby bin/brew-mirror -d /tmp -c || true` has `|| true` because it's **allowed to fail** - not a working pattern!

## Testing Strategy by Executable

### 1. brew-offline-curl

**What It Does:**
- Intercepts curl calls from Homebrew
- Redirects URLs to local mirror using urlmap
- Handles URL variants (query params, fragments)

**Test Strategy:**

**Unit Tests (with mocks):**
```ruby
class TestBrewOfflineCurl < Minitest::Test
  # RED: Test URL lookup with exact match
  def test_finds_exact_url_match
    # Setup mock config and urlmap
    # Run brew-offline-curl with URL
    # Assert URL redirected to mirror
  end

  # RED: Test URL lookup with query parameters
  def test_finds_url_with_query_params
    # Original URL: https://example.com/file.dmg?v=1.0
    # urlmap has: https://example.com/file.dmg
    # Assert: Finds match and redirects
  end

  # RED: Test missing URL warning
  def test_warns_on_missing_url
    # URL not in urlmap
    # Assert: Returns original URL + warning
  end

  # RED: Test HEAD request detection
  def test_detects_head_requests
    # curl -I or --head flag
    # Assert: Detected correctly
  end
end
```

**Integration Tests:**
```ruby
def test_curl_invocation_end_to_end
  # Create test config/urlmap
  # Invoke brew-offline-curl with test URL
  # Verify curl called with mirror URL
end
```

### 2. brew-offline-install

**What It Does:**
- Validates configuration and environment
- Resets taps to mirrored commits
- Sets up shim environment variables
- Invokes brew install

**Test Strategy:**

**Unit Tests:**
```ruby
class TestBrewOfflineInstall < Minitest::Test
  # RED: Test configuration validation
  def test_validates_cask_config_required
    # Config without cask tap
    # Try cask install
    # Assert: Aborts with error
  end

  # RED: Test tap reset logic
  def test_resets_core_tap_to_commit
    # Mock git operations
    # Assert: git checkout called with correct commit
  end

  # RED: Test cask detection
  def test_detects_cask_install_from_flag
    # ARGV = ["--cask", "firefox"]
    # Assert: is_cask_install = true
  end

  # RED: Test invalid flag detection
  def test_rejects_invalid_formula_flags
    # ARGV = ["--HEAD", "wget"]
    # Assert: Aborts with error
  end

  # RED: Test backward compatibility
  def test_handles_old_config_format
    # Old format: { commit: "abc123" }
    # Assert: Converts to new taps format
  end
end
```

**Integration Tests:**
```ruby
def test_full_install_workflow
  # Setup test mirror
  # Run brew-offline-install
  # Verify formula installed
  # Verify taps reset correctly
end
```

### 3. brew-mirror

**What It Does:**
- Mirrors formulae and casks
- Downloads assets with retry and verification
- Generates config.json and urlmap.json
- Supports dry-run mode

**Test Strategy:**

**Unit Tests:**
```ruby
class TestBrewMirror < Minitest::Test
  # RED: Test config generation
  def test_generates_config_with_taps
    # Run brew-mirror on test formulae
    # Assert: config.json contains taps hash
  end

  # RED: Test urlmap generation
  def test_stores_url_variants_in_urlmap
    # Mirror formula with URL
    # Assert: urlmap has both original and clean URL
  end

  # RED: Test dry-run mode
  def test_dry_run_does_not_download
    # Run with --dry-run
    # Assert: No files downloaded
    # Assert: Shows what would be mirrored
  end

  # RED: Test formula iteration
  def test_mirrors_specified_formulae
    # brew-mirror --formulae wget curl
    # Assert: Only wget and curl mirrored
  end

  # RED: Test cask iteration
  def test_mirrors_specified_casks
    # brew-mirror --casks firefox
    # Assert: Only firefox mirrored
  end

  # RED: Test checksum verification failure
  def test_aborts_on_checksum_mismatch
    # Mock downloader with wrong checksum
    # Assert: Aborts with error
  end

  # RED: Test retry logic integration
  def test_retries_failed_downloads
    # Mock downloader fails twice, succeeds third
    # Assert: Download retried and succeeds
  end
end
```

**Integration Tests:**
```ruby
def test_full_mirror_workflow
  # Create temp mirror directory
  # Run brew-mirror on test formula
  # Verify files downloaded
  # Verify config/urlmap generated
  # Verify checksums valid
end
```

## TDD Workflow for Future Changes

### Example: Adding New Feature to brew-mirror

**Feature:** Add `--skip-existing` flag to skip already-mirrored files

**Step 1: RED - Write Failing Test**

```ruby
def test_skip_existing_flag_skips_cached_files
  # Setup: Mirror wget once
  # Create marker to detect re-download
  # Run: brew-mirror --skip-existing wget
  # Assert: wget not downloaded again
end
```

**Step 2: Verify RED**
```bash
ruby mirror/test/executable/test_brew_mirror.rb -n test_skip_existing_flag
# Expected: Test fails because --skip-existing not implemented
```

**Step 3: GREEN - Minimal Implementation**

Add to `brew-mirror`:
```ruby
if options[:skip_existing] && File.exist?(new_location)
  verbose "Skipping existing file: #{new_location}"
  next
end
```

**Step 4: Verify GREEN**
```bash
ruby mirror/test/executable/test_brew_mirror.rb -n test_skip_existing_flag
# Expected: Test passes
```

**Step 5: REFACTOR**
- Extract file existence check to helper if needed
- Run all tests to ensure nothing broke

### Example: Bug Fix in brew-offline-curl

**Bug:** URLs with fragments (#anchor) not matching in urlmap

**Step 1: RED - Write Failing Test**

```ruby
def test_matches_url_with_fragment
  # Setup urlmap: {"https://example.com/file.dmg" => "abc123.dmg"}
  # Test URL: https://example.com/file.dmg#download
  # Assert: Finds match (currently fails)
end
```

**Step 2: Verify RED**
```bash
ruby mirror/test/executable/test_brew_offline_curl.rb -n test_matches_url_with_fragment
# Expected: AssertionError - no match found
```

**Step 3: GREEN - Fix**

Already implemented via URLHelpers.normalize_for_matching

**Step 4: Verify GREEN**
```bash
ruby mirror/test/executable/test_brew_offline_curl.rb -n test_matches_url_with_fragment
# Expected: Test passes
```

## Test Categories

### Unit Tests
- Test individual functions/methods
- Use mocks for external dependencies (file system, network, git)
- Fast execution (< 1 second per test)
- No side effects

### Integration Tests
- Test multiple components working together
- Use real file system (tmpdir)
- May use network (or mock HTTP server)
- Slower execution (seconds)
- Clean up after themselves

### End-to-End Tests
- Test full workflows (mirror → serve → install)
- Use real Homebrew (or mock)
- Slowest execution (minutes)
- Most comprehensive

## Mocking Strategy

### When to Mock

**DO Mock:**
- Network calls (HTTP downloads)
- Git operations (clone, fetch, checkout)
- External commands (brew, curl)
- Time-dependent operations (retries with delays)

**DON'T Mock:**
- File system operations (use tmpdir instead)
- Simple data transformations
- URL parsing
- JSON generation

### How to Mock in Ruby

**Example: Mock File.read**
```ruby
def test_reads_config_file
  # Create actual temp file
  config_file = Tmpfile.new(['config', '.json'])
  config_file.write('{"baseurl": "http://localhost"}')
  config_file.close

  # Override constant to point to temp file
  stub_const('BREW_OFFLINE_CONFIG', config_file.path)

  # Test actual code
  config = load_config()
  assert_equal 'http://localhost', config[:baseurl]
ensure
  config_file.unlink
end
```

**Example: Mock System Calls**
```ruby
def test_invokes_git_checkout
  checkout_called = false
  expected_commit = 'abc123'

  # Stub system call
  Object.stub :system, ->(cmd, *args) {
    if cmd == 'git' && args[0] == 'checkout'
      checkout_called = true
      assert_equal expected_commit, args[2]
      true
    else
      system(cmd, *args)
    end
  } do
    reset_tap_to_commit('homebrew/core', expected_commit)
  end

  assert checkout_called, "git checkout not called"
end
```

## Test Coverage Goals

### Phase 1: Critical Path Coverage (Current)
- Helper modules: ✓ 100% (url_helpers, container_helpers, download_helpers)
- Executables: ✗ 0%

### Phase 2: Executable Coverage (Target)
- brew-offline-curl: 80%+ coverage
- brew-offline-install: 80%+ coverage
- brew-mirror: 70%+ coverage

### Phase 3: Integration Coverage (Future)
- Full mirror workflow: Basic happy path
- Full install workflow: Basic happy path
- Error scenarios: Common failure modes

## Running Tests

### Run All Unit Tests
```bash
cd mirror/test

# Run helper module tests
ruby test_url_helpers.rb
ruby test_container_helpers.rb
ruby test_download_helpers.rb

# Run executable tests
ruby -I../lib:. executable/test_brew_offline_curl.rb
```

### Run Specific Test File
```bash
ruby -I../lib:. executable/test_brew_offline_curl.rb
```

### Run Specific Test
```bash
ruby -I../lib:. executable/test_brew_offline_curl.rb -n test_url_exact_match_redirects_to_mirror
```

### Run with Verbose Output
```bash
ruby -I../lib:. executable/test_brew_offline_curl.rb -v
```

### Run Integration Tests

**Requirements:** Homebrew installation, network access, ~5-10 minutes

```bash
cd mirror/test
bash run_integration_tests.sh
```

**What integration tests do:**
1. Mirror a real formula (jq) with brew-mirror
2. Start HTTP server to serve the mirror
3. Install formula using brew-offline-install
4. Verify the formula actually works (runs `jq --version`)
5. Test config validation
6. Test dry-run mode

**Integration tests verify:**
- Complete end-to-end workflow
- brew-mirror correctly mirrors bottles
- config.json and urlmap.json generated properly
- brew-offline-install resets taps correctly
- Offline installation actually works
- Formula runs after offline install

## CI/CD Integration

### Current CI/CD Configuration

The `.github/workflows/test.yml` runs three test jobs:

**1. test-unit** (Ubuntu, Ruby 3.0-3.3)
```yaml
- name: Run URL helpers tests
  run: ruby mirror/test/test_url_helpers.rb

- name: Run container helpers tests
  run: ruby mirror/test/test_container_helpers.rb

- name: Run download helpers tests
  run: ruby mirror/test/test_download_helpers.rb

- name: Run brew-offline-curl tests
  run: |
    cd mirror/test
    ruby -I../lib:. executable/test_brew_offline_curl.rb
```

**2. test-macos-features** (macOS, Ruby 3.0-3.2)
- Security tests
- Path detection tests
- Homebrew API compatibility tests
- Cask API tests

**3. test-integration** (macOS, Ruby 3.2)
```yaml
- name: Run integration tests
  run: |
    cd mirror/test
    bash run_integration_tests.sh
```

**Total:** ~200+ test assertions per workflow run across all jobs

## Acknowledgment: Existing Code

The current executables were written without TDD. **This is technical debt.**

**What we're doing now:**
- Adding regression tests for existing behavior
- Ensuring future changes follow TDD

**What we're NOT doing:**
- Claiming the existing code was developed with TDD
- Pretending tests-after is equivalent to TDD

**Going forward:**
- **Every new feature: RED → GREEN → REFACTOR**
- **Every bug fix: Failing test first**
- **No exceptions**

## TDD Verification Checklist

Before merging any PR with code changes:

- [ ] Every new function/method has a test
- [ ] Watched each test fail before implementing
- [ ] Each test failed for expected reason (feature missing, not typo)
- [ ] Wrote minimal code to pass each test
- [ ] All tests pass
- [ ] Output pristine (no errors, warnings)
- [ ] Tests use real code (mocks only where necessary)
- [ ] Edge cases and errors covered

Can't check all boxes? Return to RED step and start over.

## Test Coverage Status

### Completed ✓
1. ~~Create test_helper.rb with shared utilities~~ ✓
2. ~~Write tests for brew-offline-curl~~ ✓ (23 tests, 81 assertions)
3. ~~Add integration tests~~ ✓ (full workflow end-to-end)
4. ~~Add to CI/CD~~ ✓ (3 jobs, Ubuntu + macOS)

### In Progress
- brew-offline-install tests (pending)
- brew-mirror tests (pending)

### Future
- Cask integration tests (mirror → install cask)
- Performance benchmarking tests
- Concurrent download tests
- Error injection tests (network failures, disk full, etc.)

## Next Steps

1. **Immediate:** Write tests for brew-offline-install
   - Configuration validation
   - Tap reset logic
   - Install command generation

2. **Soon:** Write tests for brew-mirror
   - Formula/cask iteration
   - Download orchestration
   - Config/urlmap generation

3. **Eventually:** Add cask integration tests
   - Mirror cask with brew-mirror --casks
   - Install cask with brew-offline-install --cask

All future work: **TDD from the start. No exceptions.**
