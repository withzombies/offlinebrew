# Edge Cases & Operational Concerns Addendum

**Status**: ⚠️ HIGH PRIORITY - Address during implementation
**Author**: SRE Fellow Review
**Date**: 2025-11-11

## Overview

This document catalogs **edge cases and operational concerns** discovered during SRE review. Junior engineers should reference this alongside each task to ensure robust implementation.

---

## Phase 1: Foundation

### Task 1.1: Dynamic Homebrew Path Detection

#### Edge Case 1.1.1: Command Timeout
**Scenario**: `brew --prefix` hangs on corrupted Homebrew installation

**Impact**: Mirror process hangs indefinitely

**Fix**: Add 5-second timeout (covered in SECURITY_ADDENDUM.md)

**Test**:
```ruby
def test_brew_prefix_timeout
  # Mock slow brew command
  allow(SafeShell).to receive(:execute).with('brew', '--prefix', anything) do
    sleep 10  # Simulate hang
  end

  # Should timeout and fall back
  prefix = HomebrewPaths.homebrew_prefix
  assert_match %r{/(usr/local|opt/homebrew)}, prefix
end
```

---

#### Edge Case 1.1.2: Multiple Homebrew Installations
**Scenario**: User has both Intel and ARM Homebrew installed

**Paths**:
- Intel: `/usr/local/Homebrew`
- ARM: `/opt/homebrew`
- Which to use?

**Current Behavior**: Uses first in PATH or ARM by default

**Better Behavior**: Detect current arch and use matching Homebrew

**Fix**:
```ruby
def self.homebrew_prefix
  # Detect actual Ruby architecture (not Rosetta)
  actual_arch = `uname -m`.chomp  # "arm64" or "x86_64"

  # If running under Rosetta, Ruby reports x86_64 but uname shows arm64
  if actual_arch == "arm64"
    # Prefer ARM Homebrew
    return "/opt/homebrew" if Dir.exist?("/opt/homebrew")
  elsif actual_arch == "x86_64"
    # Prefer Intel Homebrew
    return "/usr/local" if Dir.exist?("/usr/local/bin/brew")
  end

  # Fall back to existing logic
  # ...
end
```

---

#### Edge Case 1.1.3: Linuxbrew Differences
**Scenario**: Running on Linux with Linuxbrew/Homebrew

**Differences**:
- Different default path: `/home/linuxbrew/.linuxbrew`
- Or custom: `~/.linuxbrew`
- Tap structure may differ

**Fix**: Update homebrew_prefix

```ruby
def self.homebrew_prefix
  # ... existing macOS logic ...

  # Linux detection
  if RUBY_PLATFORM.include?('linux')
    # Try common Linuxbrew paths
    [
      "/home/linuxbrew/.linuxbrew",
      File.expand_path("~/.linuxbrew"),
      "/usr/local",  # Some Linux installs here
    ].each do |path|
      return path if Dir.exist?(File.join(path, "bin", "brew"))
    end
  end

  # ... fall back logic ...
end
```

---

#### Edge Case 1.1.4: Permission Errors
**Scenario**: Homebrew directories exist but aren't readable

**Example**:
```bash
$ ls -la /opt/homebrew/Library/Taps/
ls: cannot open directory: Permission denied
```

**Current Behavior**: `Dir.exist?` returns true, but later operations fail cryptically

**Fix**: Check readability

```ruby
def self.tap_exists?(tap_path)
  return false unless Dir.exist?(tap_path)
  return false unless Dir.exist?(File.join(tap_path, ".git"))

  # Check if readable
  begin
    Dir.entries(tap_path)
    true
  rescue Errno::EACCES
    warn "Tap exists but is not readable: #{tap_path}"
    false
  end
end
```

---

#### Edge Case 1.1.5: Symlink Loops
**Scenario**: Homebrew paths contain symlink loops (rare but possible)

**Example**:
```bash
/opt/homebrew/Library/Taps/homebrew/homebrew-core -> ../homebrew-core
/opt/homebrew/Library/Taps/homebrew-core -> homebrew/homebrew-core
# Creates loop
```

**Fix**: Detect symlink loops

```ruby
def self.tap_path(user, repo)
  path = File.join(homebrew_library, "Taps", user, repo)

  # Resolve symlinks, but detect loops
  begin
    real_path = File.realpath(path)
    real_path
  rescue Errno::ELOOP
    warn "Symlink loop detected in tap path: #{path}"
    path  # Return unresolved path, let caller handle
  rescue Errno::ENOENT
    path  # Path doesn't exist, return as-is
  end
end
```

---

### Task 1.2: Cross-Platform Home Directory

#### Edge Case 1.2.1: No Home Directory
**Scenario**: Running in minimal container, user has no home

**Example**:
```bash
$ echo $HOME

$  # Empty!
```

**Fix**: Fall back to temp directory

```ruby
def self.real_home_directory
  # ... existing detection logic ...

  # Last resort: use temp directory
  if home.nil? || home.empty? || !Dir.exist?(home)
    temp_home = File.join(Dir.tmpdir, "offlinebrew-#{ENV['USER'] || 'unknown'}")
    FileUtils.mkdir_p(temp_home) rescue nil
    return temp_home if Dir.exist?(temp_home)
  end

  # Really last resort
  Dir.pwd
end
```

---

#### Edge Case 1.2.2: HOME is /dev/null
**Scenario**: Security/testing setup sets HOME to device file

**Example**:
```bash
export HOME=/dev/null
```

**Current Behavior**: Creates `.offlinebrew` in `/dev`, likely fails

**Fix**: Validate HOME is directory

```ruby
def self.real_home_directory
  # ... existing logic ...

  # Validate HOME is a directory
  if ENV["HOME"] && File.directory?(ENV["HOME"]) && File.writable?(ENV["HOME"])
    return ENV["HOME"]
  end

  # ... fallback logic ...
end
```

---

#### Edge Case 1.2.3: macOS Sandbox Restrictions
**Scenario**: Running under macOS sandbox (e.g., in test)

**Behavior**: $HOME points to sandbox container

**Fix**: Detect sandbox and warn

```ruby
def self.real_home_directory
  home = # ... detection logic ...

  # Detect macOS sandbox
  if RUBY_PLATFORM.include?('darwin') && home.include?('/Containers/')
    warn "Running in macOS sandbox, config may not persist"
  end

  home
end
```

---

### Task 1.3: API Compatibility Testing

#### Edge Case 1.3.1: Test Formulae Not Installed
**Scenario**: Test tries `Formula["wget"]` but wget not installed

**Current Behavior**: FormulaUnavailableError crashes test

**Fix**: Gracefully handle missing formulae

```ruby
def test_formula_access
  test_formulae = ["wget", "curl", "ruby", "python"]
  loaded_formula = nil

  test_formulae.each do |name|
    begin
      loaded_formula = Formula[name]
      break
    rescue FormulaUnavailableError
      # Try next formula
      next
    end
  end

  if loaded_formula
    puts "  ✓ Can load formula: #{loaded_formula.name}"
  else
    puts "  ⚠ No test formulae available"
    puts "    Try: brew install wget"
  end
end
```

---

#### Edge Case 1.3.2: `brew ruby` Itself is Broken
**Scenario**: Homebrew Ruby environment is corrupted

**Example**:
```bash
$ brew ruby --version
Error: Cannot load Homebrew environment
```

**Fix**: Test `brew ruby` before running tests

```bash
# In test script
if ! brew ruby -e 'puts "ok"' 2>/dev/null | grep -q "ok"; then
  echo "ERROR: brew ruby is not working"
  echo "Try: brew doctor"
  exit 1
fi
```

---

## Phase 2: Cask Support

### Task 2.1: Cask Tap Mirroring

#### Edge Case 2.1.1: Cask with :no_check
**Scenario**: Cask has `sha256 :no_check` (common for frequently-updated apps)

**Example**:
```ruby
cask "google-chrome" do
  url "https://dl.google.com/chrome/mac/stable/GGRO/googlechrome.dmg"
  sha256 :no_check  # Google updates frequently
end
```

**Current Behavior**: Falls back to URL-based hash (good!)

**Additional Consideration**: Document this is expected

```ruby
identifier = if checksum && checksum != :no_check
               checksum.to_s
             else
               # No checksum - use URL-based hash
               # This is EXPECTED for casks like Chrome, Firefox
               require "digest"
               Digest::SHA256.hexdigest(url_str)
             end
```

---

#### Edge Case 2.1.2: Universal Binaries
**Scenario**: Cask contains both Intel and ARM binaries

**Example**: VSCode, Docker, many others

**Current Behavior**: Downloads single file (correct)

**Additional Consideration**: File size may be 2x normal

```ruby
# Add to download section
if new_location.exist?
  size_mb = new_location.size / (1024.0 * 1024.0)

  if size_mb > 1000  # > 1GB
    ohai "  ⚠ Large file (#{size_mb.round}MB) - likely universal binary"
  end
end
```

---

#### Edge Case 2.1.3: Language-Specific Casks
**Scenario**: Cask has multiple language variants

**Example**:
```ruby
cask "firefox" do
  language "de" do
    url "https://download.mozilla.org/.../Firefox-de.dmg"
  end
  language "ja" do
    url "https://download.mozilla.org/.../Firefox-ja.dmg"
  end
end
```

**Current Behavior**: Only mirrors default language

**Fix**: Detect language variants

```ruby
# In cask mirroring loop
if cask.respond_to?(:languages) && cask.languages.any?
  opoo "Cask #{cask.token} has language variants: #{cask.languages.join(', ')}"
  opoo "Only mirroring default language - use LANGUAGE= env var to select"

  # User can set: LANGUAGE=de brew ruby bin/brew-mirror ...
end
```

---

#### Edge Case 2.1.4: Cask Requires Authentication
**Scenario**: Cask downloads require login (commercial software)

**Example**: Some Adobe, Microsoft products

**Current Behavior**: Download fails with 401/403

**Fix**: Detect and skip with clear message

```ruby
begin
  downloader.fetch unless new_location.exist?
rescue StandardError => e
  if e.message.include?("401") || e.message.include?("403")
    opoo "#{cask.token} requires authentication - skipping"
    opoo "  Error: #{e.message}"
    opoo "  You may need to download manually"
    next
  else
    raise e
  end
end
```

---

#### Edge Case 2.1.5: Cask Tap in Weird Git State
**Scenario**: homebrew-cask has detached HEAD, merge conflict, etc.

**Detection**:
```bash
$ git status
HEAD detached at abc123
```

**Fix**: Check git status before getting commit

```ruby
def self.tap_commit(tap_path)
  abort "Tap not found: #{tap_path}" unless tap_exists?(tap_path)

  Dir.chdir tap_path do
    # Check if in detached HEAD
    branch = `git symbolic-ref --short HEAD 2>/dev/null`.chomp
    if branch.empty?
      warn "Tap is in detached HEAD state: #{tap_path}"
      warn "Consider: cd #{tap_path} && git checkout master"
    end

    # Check for uncommitted changes
    unless `git status --porcelain`.empty?
      warn "Tap has uncommitted changes: #{tap_path}"
      warn "Mirroring may not be reproducible"
    end

    `git rev-parse HEAD`.chomp
  end
end
```

---

### Task 2.2: Cask Download Logic

#### Edge Case 2.2.1: Download Interrupted Mid-Stream
**Scenario**: Network drops during 500MB DMG download

**Current Behavior**: Partial file left in Homebrew cache

**Fix**: Verify file size matches expected

```ruby
# After download
if new_location.exist?
  actual_size = new_location.size

  # Check if download was partial
  if actual_size < 1000  # Less than 1KB = likely failed
    opoo "Download appears incomplete (#{actual_size} bytes)"
    File.delete(new_location)
    raise "Download failed - file too small"
  end

  # If checksum available, verify
  if checksum && checksum != :no_check
    actual_hash = Digest::SHA256.file(new_location).hexdigest
    if actual_hash != checksum.to_s
      opoo "Checksum mismatch! Downloaded file may be corrupted"
      opoo "  Expected: #{checksum}"
      opoo "  Got:      #{actual_hash}"
      File.delete(new_location)
      raise "Checksum mismatch"
    end
  end
end
```

---

#### Edge Case 2.2.2: CDN Rate Limiting
**Scenario**: CDN blocks after N downloads

**Example**: GitHub releases, SourceForge

**Behavior**: HTTP 429 (Too Many Requests) or 503

**Fix**: Detect and implement exponential backoff

```ruby
MAX_RETRIES = 5
retry_count = 0

begin
  downloader.fetch unless new_location.exist?
rescue StandardError => e
  if e.message.include?("429") || e.message.include?("rate limit")
    retry_count += 1
    if retry_count < MAX_RETRIES
      wait_time = 2 ** retry_count  # Exponential: 2, 4, 8, 16, 32 seconds
      opoo "Rate limited, waiting #{wait_time}s before retry..."
      sleep wait_time
      retry
    else
      raise "Rate limit exceeded after #{MAX_RETRIES} retries"
    end
  else
    raise e
  end
end
```

---

#### Edge Case 2.2.3: Disk Full During Download
**Scenario**: Download fills disk mid-stream

**Behavior**: Errno::ENOSPC (No space left on device)

**Fix**: Check disk space before download

```ruby
require 'sys/filesystem'

def check_disk_space(directory, required_mb)
  stat = Sys::Filesystem.stat(directory)
  available_mb = stat.bytes_available / (1024.0 * 1024.0)

  if available_mb < required_mb
    raise "Insufficient disk space: #{available_mb.round}MB available, #{required_mb}MB required"
  end
end

# Before downloading
if estimated_size = url_obj.specs[:size]
  estimated_mb = estimated_size / (1024.0 * 1024.0)
  check_disk_space(options[:directory], estimated_mb * 1.2)  # 20% buffer
end
```

---

#### Edge Case 2.2.4: File Move Fails (Cross-Device Link)
**Scenario**: Homebrew cache is on different filesystem than mirror

**Example**:
```ruby
# Homebrew cache: /tmp (tmpfs)
# Mirror: /Volumes/External (USB drive)
FileUtils.mv old_location, new_location  # Fails!
```

**Error**: `Errno::EXDEV: Invalid cross-device link`

**Fix**: Use copy + delete for cross-device moves

```ruby
begin
  FileUtils.mv old_location.to_s, new_location.to_s, force: true
rescue Errno::EXDEV
  # Cross-device link - use copy instead
  FileUtils.cp old_location.to_s, new_location.to_s
  File.delete(old_location)
rescue StandardError => e
  opoo "Failed to move file: #{e.message}"
  raise e
end
```

---

### Task 2.3: Cask Installation

#### Edge Case 2.3.1: Cask Requires User Interaction
**Scenario**: Some cask installers show GUI prompts

**Example**: "Do you want to install XYZ?"

**Behavior**: Install hangs waiting for user input

**Fix**: Use `--force` and document limitation

```ruby
# In brew-offline-install
if is_cask_install
  ohai "Installing cask(s): #{args.join(", ")}"

  # NOTE: Some casks may require user interaction
  # This is a limitation of offline cask installs
  success = system "brew", "install", "--cask", "--force", *args
end
```

**Documentation**: Add to Task 2.3

"⚠️ **Limitation**: Some casks require user interaction during install (license agreements, location selection). These may fail or hang in offline mode. Install such casks manually."

---

#### Edge Case 2.3.2: Quarantine Attributes
**Scenario**: macOS adds quarantine attribute to downloaded files

**Behavior**: Installer refuses to run due to quarantine

**Fix**: Remove quarantine attribute (with user consent)

```ruby
# After downloading cask, before install
if RUBY_PLATFORM.include?('darwin')
  cask_files = Dir.glob("#{options[:directory]}/*.{dmg,pkg,zip}")

  cask_files.each do |file|
    quarantine = MacOSSecurity.check_quarantine(file)

    if quarantine[:quarantined]
      # Remove quarantine attribute
      system "xattr", "-d", "com.apple.quarantine", file
      ohai "  Removed quarantine attribute from: #{File.basename(file)}"
    end
  end
end
```

---

## Phase 3: Enhanced Features

### Task 3.2: Git Repository UUID Collision

#### Edge Case 3.2.1: Git Repo Has No Commits
**Scenario**: Formula points to brand-new empty Git repo

**Behavior**: `git rev-parse HEAD` fails

**Fix**: Handle empty repos

```ruby
def resolve_git_revision(downloader)
  return "HEAD" unless downloader.is_a?(GitDownloadStrategy) ||
                       downloader.is_a?(GitHubGitDownloadStrategy)

  begin
    if downloader.respond_to?(:resolved_ref) && downloader.resolved_ref
      return downloader.resolved_ref
    end

    # Try to get actual commit
    if downloader.cached_location && Dir.exist?(downloader.cached_location)
      Dir.chdir(downloader.cached_location) do
        output = `git rev-parse HEAD 2>&1`.chomp
        return output if $?.success?
      end
    end
  rescue StandardError => e
    warn "Could not resolve git revision: #{e.message}"
  end

  # Fallback
  "HEAD"
end
```

---

#### Edge Case 3.2.2: Detached HEAD State
**Scenario**: Git repo is in detached HEAD state

**Behavior**: `git rev-parse HEAD` works, but warning messages

**Fix**: Suppress warnings, use SHA

```ruby
Dir.chdir(downloader.cached_location) do
  # Suppress detached HEAD warning
  sha = `git rev-parse --quiet HEAD 2>/dev/null`.chomp
  return sha if !sha.empty? && sha.match?(/^[0-9a-f]{40}$/)
end
```

---

## Phase 4: Point-in-Time

### Task 4.1: Verification System

#### Edge Case 4.1.1: urlmap.json is Malformed
**Scenario**: urlmap.json is corrupted or contains invalid JSON

**Current Behavior**: JSON.parse raises exception, crash

**Fix**: Handle parse errors

```ruby
def load_urlmap
  urlmap_file = File.join(mirror_dir, "urlmap.json")

  unless File.exist?(urlmap_file)
    @errors << "urlmap.json not found"
    @urlmap = {}
    return
  end

  begin
    @urlmap = JSON.parse(File.read(urlmap_file))
  rescue JSON::ParserError => e
    @errors << "urlmap.json is malformed: #{e.message}"
    @urlmap = {}
  rescue StandardError => e
    @errors << "Could not read urlmap.json: #{e.message}"
    @urlmap = {}
  end
end
```

---

#### Edge Case 4.1.2: Mirror on Network Filesystem
**Scenario**: Mirror directory is NFS mount, `du -sh` takes 10 minutes

**Fix**: Add timeout and show progress

```ruby
def verify_files
  # ... existing checks ...

  # Check file sizes with timeout
  begin
    puts "  Calculating mirror size (may take a while for large mirrors)..."

    output = SafeShell.execute('du', '-sh', mirror_dir, timeout: 300)  # 5 minute timeout
    total_size = output.split.first
  rescue SafeShell::TimeoutError
    warnings << "Could not calculate mirror size (timeout after 5 minutes)"
    total_size = "timeout"
  rescue StandardError => e
    warnings << "Could not calculate mirror size: #{e.message}"
    total_size = "error"
  end

  puts "  ✓ Total mirror size: #{total_size}"
end
```

---

#### Edge Case 4.1.3: Verification Interrupted
**Scenario**: User hits Ctrl-C during verification

**Behavior**: Incomplete verification, unclear state

**Fix**: Catch interrupt and report progress

```ruby
def verify!
  puts "Verifying mirror at: #{mirror_dir}"
  puts "=" * 60

  begin
    verify_config
    verify_files
    verify_checksums if ENV["VERIFY_CHECKSUMS"]
  rescue Interrupt
    puts "\n\nVerification interrupted!"
    puts "Progress so far:"
    print_summary
    exit 130  # Standard Ctrl-C exit code
  end

  print_summary
  errors.empty?
end
```

---

### Task 4.3: Incremental Updates

#### Edge Case 4.3.1: Formula Version Went Backwards
**Scenario**: Tap was rewound to earlier commit

**Example**:
```
Old mirror: wget 1.21
Update: wget 1.20 (tap was rewound)
```

**Current Behavior**: Skips wget (thinks already mirrored)

**Fix**: Check version, not just name

```ruby
already_mirrored = existing_manifest["formulae"].any? do |f|
  f["name"] == formula.name &&
  Version.new(f["version"]) >= Version.new(formula.version.to_s)
end

if already_mirrored
  ohai "#{formula.name} #{formula.version} already in mirror, skipping"
else
  ohai "Updating #{formula.name} (#{existing_version} -> #{formula.version})"
end
```

---

## Summary: Top 10 Most Critical Edge Cases

1. **Shell Injection** (Task 4.1) - 🔴 CRITICAL
2. **Path Traversal** (Task 2.1, 2.2) - 🔴 CRITICAL
3. **Command Timeouts** (All tasks) - 🔴 CRITICAL
4. **Disk Full** (Task 2.2) - 🔴 HIGH
5. **Cask :no_check** (Task 2.1) - 🟡 MEDIUM (common)
6. **Cross-Device File Move** (Task 2.2) - 🟡 MEDIUM
7. **Rate Limiting** (Task 2.2) - 🟡 MEDIUM
8. **Malformed JSON** (Task 4.1) - 🟡 MEDIUM
9. **Multiple Homebrew Installs** (Task 1.1) - 🟢 LOW
10. **Quarantine Attributes** (Task 2.3) - 🟢 LOW (macOS only)

---

## Implementation Guidance

For each task:
1. Read main task file
2. Read relevant section in this addendum
3. Implement main task logic
4. Add edge case handling
5. Write tests for edge cases
6. Document known limitations

Good luck! 🎯
