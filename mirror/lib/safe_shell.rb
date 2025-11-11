#!/usr/bin/env ruby
# frozen_string_literal: true

require 'shellwords'
require 'timeout'
require 'fileutils'

# SafeShell: Safe shell command execution with timeouts and escaping
#
# This module provides secure wrappers around shell commands to prevent:
# - Shell injection attacks
# - Path traversal vulnerabilities
# - Command timeouts/hangs
# - Unsafe file operations
#
# Usage:
#   SafeShell.execute('du', '-sh', directory, timeout: 30)
#   SafeShell.safe_join('/base/dir', 'subdir', 'file.txt')
#   SafeShell.sanitize_filename(user_input)
module SafeShell
  class ExecutionError < StandardError; end
  class TimeoutError < StandardError; end

  # Execute a shell command safely with timeout and argument escaping
  #
  # @param cmd [String] Command to execute
  # @param args [Array<String>] Arguments to pass (will be escaped)
  # @param timeout [Integer] Timeout in seconds (default 30)
  # @param allowed_failures [Boolean] If true, don't raise on non-zero exit
  # @return [String] Command output (stdout + stderr)
  # @raise [ExecutionError] If command fails and allowed_failures is false
  # @raise [TimeoutError] If command exceeds timeout
  #
  # @example Execute with arguments
  #   output = SafeShell.execute('du', '-sh', '/path/to/dir', timeout: 60)
  #
  # @example Execute with allowed failures
  #   output = SafeShell.execute('test', '-f', 'missing.txt', allowed_failures: true)
  def self.execute(cmd, *args, timeout: 30, allowed_failures: false)
    # Escape all arguments
    escaped_args = args.map { |arg| Shellwords.escape(arg.to_s) }

    # Build command
    full_cmd = if escaped_args.empty?
                 cmd.to_s
               else
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

  # Execute command and return success boolean (never raises)
  #
  # @param cmd [String] Command to execute
  # @param args [Array<String>] Arguments to pass
  # @param timeout [Integer] Timeout in seconds
  # @return [Boolean] True if command succeeded, false otherwise
  #
  # @example Check if file exists
  #   if SafeShell.execute?('test', '-f', '/path/to/file')
  #     puts "File exists"
  #   end
  def self.execute?(cmd, *args, timeout: 30)
    execute(cmd, *args, timeout: timeout)
    true
  rescue StandardError
    false
  end

  # Execute command with exponential backoff retry
  #
  # @param cmd [String] Command to execute
  # @param args [Array<String>] Arguments to pass
  # @param timeout [Integer] Timeout in seconds per attempt
  # @param retries [Integer] Number of retry attempts
  # @return [String] Command output
  # @raise [ExecutionError, TimeoutError] If all retries exhausted
  #
  # @example Retry network command
  #   output = SafeShell.execute_with_retry('curl', url, timeout: 10, retries: 3)
  def self.execute_with_retry(cmd, *args, timeout: 30, retries: 3)
    attempts = 0
    begin
      attempts += 1
      execute(cmd, *args, timeout: timeout)
    rescue ExecutionError, TimeoutError => e
      if attempts < retries
        sleep(attempts * 2)  # Exponential backoff: 2s, 4s, 6s
        retry
      end
      raise e
    end
  end

  # Safe path joining that prevents directory traversal attacks
  #
  # This method ensures that the resulting path stays within the base directory.
  # It prevents attacks like "../../../etc/passwd"
  #
  # @param base [String] Base directory (must exist)
  # @param parts [Array<String>] Path components to join
  # @return [String] Safe absolute path within base directory
  # @raise [ArgumentError] If base directory doesn't exist
  # @raise [SecurityError] If path traversal detected
  #
  # @example Join paths safely
  #   safe_path = SafeShell.safe_join('/mirror', 'formulae', 'wget.rb')
  #   # => "/mirror/formulae/wget.rb"
  #
  # @example Detect traversal attack
  #   SafeShell.safe_join('/mirror', '../../etc/passwd')
  #   # => raises SecurityError
  def self.safe_join(base, *parts)
    # Expand base to absolute path
    base_path = File.expand_path(base)

    unless Dir.exist?(base_path)
      raise ArgumentError, "Base directory does not exist: #{base}"
    end

    # Check for absolute paths in parts (security risk)
    parts.each do |part|
      if part.to_s.start_with?('/') || part.to_s.match?(/^[A-Za-z]:/)
        raise SecurityError, "Absolute path not allowed in parts: #{part}"
      end
    end

    # Join and expand the full path
    full_path = File.expand_path(File.join(base, *parts))

    # CRITICAL: Ensure result is within base
    # Must check for base_path + separator to prevent "/base" matching "/base-evil"
    unless full_path.start_with?(base_path + File::SEPARATOR) || full_path == base_path
      raise SecurityError, "Path traversal attempt detected: #{parts.join('/')}"
    end

    full_path
  end

  # Validate that a filename is safe (no path components)
  #
  # @param filename [String] Filename to validate
  # @return [Boolean] True if filename is safe
  #
  # @example Check safe filename
  #   SafeShell.safe_filename?("document.pdf")  # => true
  #   SafeShell.safe_filename?("../etc/passwd") # => false
  #   SafeShell.safe_filename?("sub/dir/file")  # => false
  def self.safe_filename?(filename)
    return false if filename.nil?

    # No path separators
    return false if filename.include?('/') || filename.include?('\\')

    # No parent directory reference
    return false if filename.include?('..')

    # No null bytes
    return false if filename.include?("\0")

    # Not empty
    return false if filename.empty?

    # No leading/trailing spaces (can cause issues)
    return false if filename != filename.strip

    true
  end

  # Sanitize a filename by removing dangerous characters
  #
  # @param filename [String] Filename to sanitize (possibly unsafe)
  # @return [String] Safe filename
  #
  # @example Sanitize malicious filename
  #   SafeShell.sanitize_filename("../etc/passwd")
  #   # => "___etc_passwd"
  #
  # @example Sanitize path in filename
  #   SafeShell.sanitize_filename("sub/dir/file.txt")
  #   # => "sub_dir_file.txt"
  def self.sanitize_filename(filename)
    return 'unnamed' if filename.nil? || filename.empty?

    # Remove path separators
    safe = filename.gsub(%r{[/\\]}, '_')

    # Remove parent refs
    safe = safe.gsub(/\.\./, '__')

    # Remove null bytes
    safe = safe.gsub(/\0/, '')

    # Remove leading/trailing spaces
    safe = safe.strip

    # Replace other dangerous characters
    safe = safe.gsub(/[<>:"|?*]/, '_')

    # Limit length (255 is typical filesystem limit)
    safe = safe[0..254] if safe.length > 255

    # Ensure not empty after sanitization
    safe = 'unnamed' if safe.empty?

    safe
  end

  # Create a directory safely with error handling
  #
  # @param path [String] Directory path to create
  # @return [Boolean] True if successful
  # @raise [ArgumentError] If path is invalid
  #
  # @example Create directory
  #   SafeShell.mkdir_p('/tmp/mirror/formulae')
  def self.mkdir_p(path)
    raise ArgumentError, "Path cannot be empty" if path.nil? || path.empty?

    FileUtils.mkdir_p(path)
    true
  rescue Errno::EACCES => e
    raise ExecutionError, "Permission denied creating directory: #{path}"
  rescue Errno::ENOSPC => e
    raise ExecutionError, "No space left on device: #{path}"
  end

  # Remove a file or directory safely
  #
  # @param path [String] Path to remove
  # @param force [Boolean] If true, ignore errors
  # @return [Boolean] True if successful
  #
  # @example Remove directory
  #   SafeShell.rm_rf('/tmp/old-mirror')
  def self.rm_rf(path, force: false)
    return false if path.nil? || path.empty?
    return false unless File.exist?(path)

    FileUtils.rm_rf(path)
    true
  rescue StandardError => e
    raise ExecutionError, "Failed to remove #{path}: #{e.message}" unless force
    false
  end
end
