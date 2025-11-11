# Automated Testing Strategy - macOS Focused

**Status**: 🔧 REQUIRED - Must implement alongside main tasks
**Author**: SRE Fellow Review - Testing Addendum (Updated)
**Date**: 2025-11-11
**Platform**: macOS only (Intel + Apple Silicon)

## Overview

**Simplified Strategy**: Test on macOS only. Verify both scripts AND resulting formulae.

**Key Principle**: If a formula mirrors successfully, it should install and work offline.

---

## Testing Philosophy

### Two Types of Testing

1. **Script Testing** (Does the tool work?)
   - Does `brew-mirror` create valid mirrors?
   - Does `brew-offline-install` install from mirrors?
   - Do the helper modules work correctly?

2. **Formula Verification** (Does the result work?)
   - Can we mirror wget?
   - Can we install wget from the mirror?
   - **Does `wget --version` work after offline install?**

**This is the gap most testing strategies miss!**

---

## Testing Pyramid (macOS Only)

```
           ╱╲
          ╱  ╲
         ╱ E2E ╲          10% - Full workflow + verification
        ╱────────╲        - Mirror + Install + Test formula
       ╱          ╲        <10 minutes
      ╱            ╲
     ╱ Integration  ╲     30% - Mock downloads
    ╱────────────────╲    - Test workflows
   ╱                  ╲   <2 minutes
  ╱                    ╲
 ╱  Unit Tests          ╲ 60% - Fast module tests
╱────────────────────────╲ <10 seconds
```

**Target**: Full suite in <15 minutes on macOS

---

## CI/CD Strategy (GitHub Actions - macOS Only)

### Workflow: Test on Every Push

```yaml
name: Test Suite (macOS)

on:
  push:
    branches: [ main, develop, 'claude/**' ]
  pull_request:
    branches: [ main ]

jobs:
  test-macos:
    name: Test on macOS
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [macos-13, macos-14]  # Intel + Apple Silicon
        ruby: ['3.0', '3.1', '3.2']

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
          working-directory: mirror

      - name: Install test dependencies
        working-directory: mirror
        run: bundle install

      - name: Run unit tests
        working-directory: mirror
        run: bundle exec rake test:unit

      - name: Run security tests
        working-directory: mirror
        run: bundle exec rake test:security

      - name: Run integration tests
        working-directory: mirror
        run: bundle exec rake test:integration

  verify-formulae:
    name: Verify Real Formulae
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [macos-13, macos-14]

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true
          working-directory: mirror

      - name: Update Homebrew
        run: brew update

      - name: Mirror small formulae
        working-directory: mirror
        run: |
          mkdir -p /tmp/test-mirror
          brew ruby bin/brew-mirror -d /tmp/test-mirror -f jq,tree -s 1

      - name: Verify mirror created
        run: |
          test -f /tmp/test-mirror/config.json
          test -f /tmp/test-mirror/urlmap.json
          ls -lh /tmp/test-mirror/

      - name: Start HTTP server
        run: |
          cd /tmp/test-mirror
          python3 -m http.server 9876 &
          echo $! > /tmp/mirror-server.pid
          sleep 2

      - name: Install from mirror
        working-directory: mirror
        run: |
          mkdir -p ~/.offlinebrew
          echo '{"baseurl":"http://localhost:9876"}' > ~/.offlinebrew/config.json

          # Uninstall if already present
          brew uninstall jq 2>/dev/null || true

          # Install from offline mirror
          ruby bin/brew-offline-install jq

      - name: Test installed formula
        run: |
          # The critical test: Does it actually work?
          jq --version
          echo '{"test": "value"}' | jq .test | grep -q "value"

      - name: Cleanup
        if: always()
        run: |
          if [ -f /tmp/mirror-server.pid ]; then
            kill $(cat /tmp/mirror-server.pid) || true
          fi
          rm -rf /tmp/test-mirror
          rm -rf ~/.offlinebrew

  verify-casks:
    name: Verify Real Casks
    runs-on: macos-latest
    if: github.ref == 'refs/heads/main'  # Only on main branch

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true
          working-directory: mirror

      - name: Update Homebrew
        run: brew update

      - name: Mirror small cask
        working-directory: mirror
        run: |
          mkdir -p /tmp/cask-mirror
          # Use a small, fast-downloading cask
          brew ruby bin/brew-mirror -d /tmp/cask-mirror --casks hex-fiend -s 2

      - name: Verify cask mirror
        run: |
          test -f /tmp/cask-mirror/config.json
          test -f /tmp/cask-mirror/urlmap.json
          # Check that DMG was downloaded
          find /tmp/cask-mirror -name "*.dmg" | grep -q .

      - name: Start HTTP server
        run: |
          cd /tmp/cask-mirror
          python3 -m http.server 9877 &
          echo $! > /tmp/cask-server.pid
          sleep 2

      - name: Install cask from mirror
        working-directory: mirror
        run: |
          mkdir -p ~/.offlinebrew
          echo '{"baseurl":"http://localhost:9877"}' > ~/.offlinebrew/config.json

          brew uninstall --cask hex-fiend 2>/dev/null || true

          ruby bin/brew-offline-install --cask hex-fiend

      - name: Verify cask installed
        run: |
          # Check that app was installed
          test -d "/Applications/Hex Fiend.app"

      - name: Cleanup
        if: always()
        run: |
          brew uninstall --cask hex-fiend 2>/dev/null || true
          if [ -f /tmp/cask-server.pid ]; then
            kill $(cat /tmp/cask-server.pid) || true
          fi
          rm -rf /tmp/cask-mirror
          rm -rf ~/.offlinebrew

  code-coverage:
    name: Code Coverage
    runs-on: macos-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true
          working-directory: mirror

      - name: Run tests with coverage
        working-directory: mirror
        run: |
          COVERAGE=1 bundle exec rake test

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v3
        with:
          files: ./mirror/coverage/.resultset.json
          flags: unittests
          name: codecov-macos
```

---

## Test Directory Structure

```
mirror/
├── test/
│   ├── unit/                    # 60% - Module tests
│   │   ├── test_safe_shell.rb
│   │   ├── test_homebrew_paths.rb
│   │   ├── test_url_helpers.rb
│   │   └── test_macos_security.rb
│   │
│   ├── integration/             # 30% - Workflow tests
│   │   ├── test_mirror_workflow.rb
│   │   ├── test_install_workflow.rb
│   │   └── test_verification.rb
│   │
│   ├── verification/            # 10% - Formula tests (NEW!)
│   │   ├── test_formula_mirror_install.rb
│   │   └── test_cask_mirror_install.rb
│   │
│   ├── security/                # Critical path
│   │   ├── test_injection.rb
│   │   ├── test_traversal.rb
│   │   └── test_signature_verification.rb
│   │
│   ├── fixtures/
│   │   ├── formulae/
│   │   ├── casks/
│   │   └── tarballs/
│   │
│   └── test_helper.rb
```

---

## NEW: Formula Verification Tests

### Test: Mirror + Install + Verify Formula

Create `mirror/test/verification/test_formula_mirror_install.rb`:

```ruby
#!/usr/bin/env brew ruby
# frozen_string_literal: true

require_relative '../test_helper'

# VerifyFormula: End-to-end tests that verify formulae actually work
# after mirroring and installing
class TestFormulaMirrorInstall < Minitest::Test
  SMALL_FORMULAE = %w[jq tree hello].freeze

  def setup
    @test_dir = setup_test_dir
    @mirror_dir = File.join(@test_dir, 'mirror')
    @server_pid = nil
  end

  def teardown
    stop_http_server
    cleanup_homebrew_packages
    super
  end

  # Test: Can we mirror, install, and run jq?
  def test_mirror_and_verify_jq
    # Step 1: Mirror jq
    mirror_result = mirror_formula('jq')
    assert mirror_result[:success], "Mirroring jq should succeed"

    # Verify mirror structure
    assert File.exist?(File.join(@mirror_dir, 'config.json'))
    assert File.exist?(File.join(@mirror_dir, 'urlmap.json'))

    # Step 2: Serve mirror
    start_http_server(@mirror_dir, port: 9876)

    # Step 3: Install from mirror
    cleanup_formula('jq')  # Remove if present
    install_result = install_from_mirror('jq', 'http://localhost:9876')
    assert install_result[:success], "Installing jq should succeed"

    # Step 4: CRITICAL - Verify it actually works
    assert system('jq --version'), "jq --version should work"

    # Test actual functionality
    output = `echo '{"name":"test"}' | jq .name`.chomp
    assert_equal '"test"', output, "jq should extract JSON value"
  end

  # Test: Can we mirror and verify tree?
  def test_mirror_and_verify_tree
    mirror_result = mirror_formula('tree')
    assert mirror_result[:success], "Mirroring tree should succeed"

    start_http_server(@mirror_dir, port: 9878)

    cleanup_formula('tree')
    install_result = install_from_mirror('tree', 'http://localhost:9878')
    assert install_result[:success], "Installing tree should succeed"

    # Verify tree works
    assert system('tree --version'), "tree --version should work"
  end

  # Test: Can we mirror multiple formulae at once?
  def test_mirror_multiple_formulae
    mirror_result = mirror_formulae(['jq', 'tree'])
    assert mirror_result[:success], "Mirroring multiple formulae should succeed"

    # Verify both are in urlmap
    urlmap = JSON.parse(File.read(File.join(@mirror_dir, 'urlmap.json')))
    assert urlmap.keys.any? { |k| k.include?('jq') }, "urlmap should include jq"
    assert urlmap.keys.any? { |k| k.include?('tree') }, "urlmap should include tree"
  end

  private

  def mirror_formula(name)
    mirror_formulae([name])
  end

  def mirror_formulae(names)
    FileUtils.mkdir_p(@mirror_dir)

    result = system(
      'brew', 'ruby', File.expand_path('../../bin/brew-mirror', __dir__),
      '-d', @mirror_dir,
      '-f', names.join(','),
      '-s', '1',
      out: $stdout,
      err: $stderr
    )

    { success: result, mirror_dir: @mirror_dir }
  end

  def start_http_server(dir, port:)
    @server_pid = fork do
      Dir.chdir(dir)
      exec('python3', '-m', 'http.server', port.to_s, out: '/dev/null', err: '/dev/null')
    end

    # Wait for server to start
    sleep 2

    # Verify server is responding
    10.times do
      break if system("curl -s http://localhost:#{port}/config.json > /dev/null 2>&1")
      sleep 0.5
    end
  end

  def stop_http_server
    return unless @server_pid

    Process.kill('TERM', @server_pid)
    Process.wait(@server_pid)
  rescue StandardError
    # Ignore errors
  ensure
    @server_pid = nil
  end

  def install_from_mirror(formula, mirror_url)
    # Configure client
    config_dir = File.join(@test_dir, '.offlinebrew')
    FileUtils.mkdir_p(config_dir)

    config = { 'baseurl' => mirror_url }
    File.write(File.join(config_dir, 'config.json'), JSON.generate(config))

    # Set HOME so brew-offline-install finds config
    result = system(
      { 'HOME' => @test_dir },
      'ruby', File.expand_path('../../bin/brew-offline-install', __dir__),
      formula,
      out: $stdout,
      err: $stderr
    )

    { success: result }
  end

  def cleanup_formula(name)
    system("brew uninstall #{name} 2>/dev/null")
  end

  def cleanup_homebrew_packages
    SMALL_FORMULAE.each do |formula|
      cleanup_formula(formula)
    end
  end
end
```

---

### Test: Cask Verification

Create `mirror/test/verification/test_cask_mirror_install.rb`:

```ruby
#!/usr/bin/env brew ruby
# frozen_string_literal: true

require_relative '../test_helper'

class TestCaskMirrorInstall < Minitest::Test
  # Use small, fast-downloading casks
  SMALL_CASKS = %w[hex-fiend].freeze

  def setup
    @test_dir = setup_test_dir
    @mirror_dir = File.join(@test_dir, 'mirror')
    @server_pid = nil
  end

  def teardown
    stop_http_server
    cleanup_casks
    super
  end

  def test_mirror_and_verify_cask
    skip_if_fast_only  # Cask downloads are slow

    # Step 1: Mirror cask
    mirror_result = mirror_cask('hex-fiend')
    assert mirror_result[:success], "Mirroring hex-fiend should succeed"

    # Verify DMG was downloaded
    dmg_files = Dir.glob("#{@mirror_dir}/*.dmg")
    refute_empty dmg_files, "Should have downloaded DMG file"

    # Step 2: Serve mirror
    start_http_server(@mirror_dir, port: 9877)

    # Step 3: Install cask
    cleanup_cask('hex-fiend')
    install_result = install_cask_from_mirror('hex-fiend', 'http://localhost:9877')
    assert install_result[:success], "Installing hex-fiend should succeed"

    # Step 4: CRITICAL - Verify app was installed
    app_path = '/Applications/Hex Fiend.app'
    assert File.exist?(app_path), "Hex Fiend.app should be installed"

    # Verify it's a valid app bundle
    assert File.exist?(File.join(app_path, 'Contents', 'Info.plist')),
           "Should be valid app bundle"

    # Verify code signature (macOS only)
    sig_result = system("codesign --verify '#{app_path}' 2>/dev/null")
    assert sig_result, "App should have valid code signature"
  end

  def test_cask_without_checksum
    # Some casks use sha256 :no_check
    # Verify these still work

    # This would test a cask with :no_check
    # Example: google-chrome, firefox
  end

  private

  def mirror_cask(token)
    FileUtils.mkdir_p(@mirror_dir)

    result = system(
      'brew', 'ruby', File.expand_path('../../bin/brew-mirror', __dir__),
      '-d', @mirror_dir,
      '--casks', token,
      '-s', '2',
      out: $stdout,
      err: $stderr
    )

    { success: result, mirror_dir: @mirror_dir }
  end

  def start_http_server(dir, port:)
    @server_pid = fork do
      Dir.chdir(dir)
      exec('python3', '-m', 'http.server', port.to_s, out: '/dev/null', err: '/dev/null')
    end

    sleep 3  # Casks need more time

    10.times do
      break if system("curl -s http://localhost:#{port}/config.json > /dev/null 2>&1")
      sleep 0.5
    end
  end

  def stop_http_server
    return unless @server_pid

    Process.kill('TERM', @server_pid)
    Process.wait(@server_pid)
  rescue StandardError
    # Ignore
  ensure
    @server_pid = nil
  end

  def install_cask_from_mirror(token, mirror_url)
    config_dir = File.join(@test_dir, '.offlinebrew')
    FileUtils.mkdir_p(config_dir)

    config = { 'baseurl' => mirror_url }
    File.write(File.join(config_dir, 'config.json'), JSON.generate(config))

    result = system(
      { 'HOME' => @test_dir },
      'ruby', File.expand_path('../../bin/brew-offline-install', __dir__),
      '--cask', token,
      out: $stdout,
      err: $stderr
    )

    { success: result }
  end

  def cleanup_cask(token)
    system("brew uninstall --cask #{token} 2>/dev/null")
  end

  def cleanup_casks
    SMALL_CASKS.each do |cask|
      cleanup_cask(cask)
    end
  end
end
```

---

## Updated Test Helper (macOS-focused)

Update `mirror/test/test_helper.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/reporters'
require 'webmock/minitest'
require 'vcr'
require 'mocha/minitest'
require 'simplecov'
require 'fileutils'
require 'tmpdir'

# Only run on macOS
unless RUBY_PLATFORM.include?('darwin')
  puts "ERROR: Tests must run on macOS"
  exit 1
end

# Start code coverage
SimpleCov.start do
  add_filter '/test/'
  add_filter '/vendor/'
end

Minitest::Reporters.use! [
  Minitest::Reporters::SpecReporter.new(color: true)
]

# VCR configuration
VCR.configure do |config|
  config.cassette_library_dir = File.expand_path('fixtures/vcr_cassettes', __dir__)
  config.hook_into :webmock
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [:method, :uri]
  }
end

module TestHelpers
  # (Keep existing helpers...)

  # Skip if not running full test suite
  def skip_if_fast_only
    skip "Slow test (set TEST_ALL=1 to run)" if ENV['FAST_TESTS_ONLY']
  end

  # macOS is always available, no skip needed
  def skip_unless_macos
    # No-op on macOS
  end
end

class Minitest::Test
  include TestHelpers

  def teardown
    teardown_test_dirs
  end
end
```

---

## Updated Rakefile

Update `mirror/Rakefile`:

```ruby
# frozen_string_literal: true

require 'rake/testtask'

# Fast tests (unit + security only)
Rake::TestTask.new(:unit) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/unit/**/*_test.rb']
  t.verbose = true
end

Rake::TestTask.new(:security) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/security/**/*_test.rb']
  t.verbose = true
end

# Integration tests (mocked workflows)
Rake::TestTask.new(:integration) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/integration/**/*_test.rb']
  t.verbose = true
end

# Verification tests (real formulae)
Rake::TestTask.new(:verification) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/verification/**/*_test.rb']
  t.verbose = true
end

# Fast: unit + security (no real downloads)
task :fast => [:unit, :security]

# Full: everything
task :test => [:unit, :security, :integration, :verification]

task default: :fast
```

---

## Running Tests Locally

### Fast Tests (No Downloads)
```bash
cd mirror
export FAST_TESTS_ONLY=1
bundle exec rake fast
```
**Output**: ~50 tests, <10 seconds

### Integration Tests (Mocked Downloads)
```bash
cd mirror
bundle exec rake integration
```
**Output**: ~20 tests, <2 minutes

### Verification Tests (Real Formulae)
```bash
cd mirror
export TEST_ALL=1
bundle exec rake verification
```
**Output**: ~5 tests, <10 minutes (downloads real packages)

### Full Suite
```bash
cd mirror
export TEST_ALL=1
bundle exec rake test
```
**Output**: ~75 tests, <15 minutes

---

## Test Matrix (macOS Only)

| OS | Ruby | Tests | Notes |
|----|------|-------|-------|
| macOS 13 (Intel) | 3.0 | unit, security, integration | Fast CI |
| macOS 13 (Intel) | 3.1 | unit, security, integration | Fast CI |
| macOS 13 (Intel) | 3.2 | unit, security, integration | Fast CI |
| macOS 14 (Apple Silicon) | 3.0 | unit, security, integration | Fast CI |
| macOS 14 (Apple Silicon) | 3.1 | unit, security, integration | Fast CI |
| macOS 14 (Apple Silicon) | 3.2 | unit, security, integration | Fast CI |
| macOS latest | 3.2 | verification (main only) | Slow, real downloads |

---

## What Gets Tested

### ✅ Unit Tests (60%)
- SafeShell: injection, timeouts, escaping
- HomebrewPaths: detection, validation
- URL helpers: normalization, matching
- Container helpers: format detection
- macOS security: signature verification

### ✅ Integration Tests (30%)
- Mirror workflow with mocked downloads
- Install workflow with mock mirrors
- Verification system
- Manifest generation

### ✅ Verification Tests (10%) - **THE KEY TESTS**
- Mirror jq → Install jq → `jq --version` works
- Mirror tree → Install tree → `tree --version` works
- Mirror hex-fiend → Install hex-fiend → App launches
- **These prove the whole system works end-to-end**

### ✅ Security Tests (Always)
- Shell injection protection
- Path traversal protection
- XSS protection
- Code signature verification

---

## CI/CD Flow

```
┌─────────────┐
│  git push   │
└──────┬──────┘
       │
       ├──▶ Unit Tests (macOS 13/14, Ruby 3.0/3.1/3.2)      10s
       │    ✓ All helper modules
       │
       ├──▶ Security Tests (macOS)                           1m
       │    ✓ Injection, traversal, XSS, signatures
       │
       ├──▶ Integration Tests (macOS 13/14)                  2m
       │    ✓ Mock mirror/install workflows
       │
       └──▶ Verification Tests (macOS latest, main only)    10m
            ✓ Real jq mirror + install + test
            ✓ Real hex-fiend mirror + install + test
            │
            ▼
       ✅ All pass → Merge allowed
       ❌ Any fail → PR blocked
```

---

## Example CI Output

```
Test Suite (macOS)
==================

Unit Tests (macOS-13, Ruby 3.0)                  ✓ 45 tests, 8.2s
Unit Tests (macOS-14, Ruby 3.0)                  ✓ 45 tests, 8.5s
Security Tests (macOS-13)                        ✓ 10 tests, 1.2s
Integration Tests (macOS-13)                     ✓ 18 tests, 1.8m

Verification Tests (macOS-latest, main branch)
  Mirroring jq...                                ✓ 2.3m
  Installing jq from mirror...                   ✓ 1.1m
  Testing jq --version...                        ✓ PASS
  Testing jq JSON parsing...                     ✓ PASS

Total: 78 tests, 12.4 minutes
Coverage: 87%
```

---

## Key Differences from Generic Strategy

### Removed ❌
- Linux support (no longer needed)
- Cross-platform path handling tests
- Linuxbrew-specific logic
- Platform-agnostic abstractions

### Added ✅
- Formula verification tests (THE CRITICAL TESTS)
- Real package installation and testing
- Code signature verification (macOS-specific)
- Apple Silicon + Intel matrix testing
- Actual functionality testing (does wget work?)

### Simplified ✅
- Only test on macOS in CI
- No need for complex platform detection
- Can use macOS-specific tools (codesign, etc.)
- Can test real Homebrew behavior

---

## Acceptance Criteria

Testing strategy complete when:

1. ✅ Test infrastructure created (Gemfile, helpers, fixtures)
2. ✅ 45+ unit tests written (macOS-focused)
3. ✅ 18+ integration tests with mocked downloads
4. ✅ 5+ verification tests **that test real formulae work**
5. ✅ 10+ security tests including signature verification
6. ✅ CI/CD runs on macOS 13 (Intel) and macOS 14 (Apple Silicon)
7. ✅ Verification tests install and test real packages
8. ✅ Full suite runs in <15 minutes
9. ✅ Code coverage >85%
10. ✅ **Critical: Mirrored formulae actually work when installed**

---

## Summary of Changes

**From Original Strategy**:
- ❌ Removed: Linux support, cross-platform abstractions
- ✅ Added: Formula verification tests (install + test)
- ✅ Added: macOS-only focus (Intel + Apple Silicon)
- ✅ Added: Real package functionality testing
- ✅ Simplified: No platform detection complexity

**Key Insight**: Testing scripts alone isn't enough. We must verify that:
1. Scripts work (unit/integration tests)
2. **Mirrored packages actually work** (verification tests)

This ensures the whole system is production-ready! 🎯
