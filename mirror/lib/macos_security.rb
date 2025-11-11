#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'safe_shell'

# MacOSSecurity: Verify code signatures and notarization for macOS applications
#
# This module provides security verification for downloaded casks to prevent:
# - Malware distribution
# - Tampered applications
# - Unsigned code execution
#
# Usage:
#   result = MacOSSecurity.verify_signature('/path/to/app.dmg')
#   if result[:valid]
#     puts "Signature valid!"
#   end
module MacOSSecurity
  # Verify code signature of a file or application bundle
  #
  # Uses codesign --verify to check if the code signature is valid.
  # This helps ensure the application hasn't been tampered with.
  #
  # @param path [String] Path to file or .app bundle
  # @return [Hash] Result with :valid, :message, :details keys
  #
  # @example Verify an app
  #   result = MacOSSecurity.verify_signature('/Applications/Safari.app')
  #   puts result[:message] if result[:valid]
  #
  # @example Handle verification failure
  #   result = MacOSSecurity.verify_signature('unsigned.app')
  #   unless result[:valid]
  #     warn "Signature invalid: #{result[:message]}"
  #   end
  def self.verify_signature(path)
    return { valid: false, message: "Not on macOS" } unless RUBY_PLATFORM.include?('darwin')
    return { valid: false, message: "File not found: #{path}" } unless File.exist?(path)

    begin
      # --verify: Check if signature is valid
      # --verbose: Show details
      # --deep: Check nested code (for app bundles)
      output = SafeShell.execute('codesign', '--verify', '--verbose', '--deep', path,
                                 timeout: 30, allowed_failures: true)

      # codesign --verify outputs to stderr, returns 0 on success
      if $?.success?
        {
          valid: true,
          message: "Code signature valid",
          details: output
        }
      else
        {
          valid: false,
          message: "Code signature invalid or missing",
          details: output
        }
      end
    rescue SafeShell::TimeoutError => e
      {
        valid: false,
        message: "Signature verification timed out",
        details: e.message
      }
    rescue SafeShell::ExecutionError => e
      {
        valid: false,
        message: "Signature verification failed",
        details: e.message
      }
    end
  end

  # Get detailed signature information
  #
  # @param path [String] Path to file or .app bundle
  # @return [Hash] Information about the signature
  #
  # @example Get signature info
  #   info = MacOSSecurity.signature_info('/Applications/Safari.app')
  #   puts "Signed by: #{info[:authority]}"
  #   puts "Team ID: #{info[:team_id]}"
  def self.signature_info(path)
    return { error: "Not on macOS" } unless RUBY_PLATFORM.include?('darwin')
    return { error: "File not found" } unless File.exist?(path)

    begin
      output = SafeShell.execute('codesign', '-dvv', path, timeout: 30, allowed_failures: true)

      info = {}
      output.each_line do |line|
        if line =~ /Authority=(.+)/
          info[:authority] ||= []
          info[:authority] << $1.strip
        elsif line =~ /TeamIdentifier=(.+)/
          info[:team_id] = $1.strip
        elsif line =~ /Identifier=(.+)/
          info[:identifier] = $1.strip
        elsif line =~ /Format=(.+)/
          info[:format] = $1.strip
        end
      end

      info
    rescue StandardError => e
      { error: e.message }
    end
  end

  # Check if file is notarized by Apple
  #
  # Notarization is Apple's automated malware scanning service.
  # Apps distributed outside the Mac App Store should be notarized.
  #
  # @param path [String] Path to file or .app bundle
  # @return [Hash] Result with :notarized, :message keys
  #
  # @example Check notarization
  #   result = MacOSSecurity.check_notarization('/Applications/App.app')
  #   if result[:notarized]
  #     puts "App is notarized"
  #   else
  #     warn "App is not notarized: #{result[:message]}"
  #   end
  def self.check_notarization(path)
    return { notarized: false, message: "Not on macOS" } unless RUBY_PLATFORM.include?('darwin')
    return { notarized: false, message: "File not found" } unless File.exist?(path)

    begin
      # spctl: Security Assessment Policy
      # -a: assess
      # -vv: very verbose
      # -t install: assess as installer
      output = SafeShell.execute('spctl', '-a', '-vv', '-t', 'install', path,
                                 timeout: 30, allowed_failures: true)

      # Look for "accepted" in output
      # Example: "/path/to/app: accepted"
      if output.include?("accepted")
        {
          notarized: true,
          message: "File is notarized and accepted",
          details: output
        }
      else
        {
          notarized: false,
          message: "File is not notarized or rejected",
          details: output
        }
      end
    rescue SafeShell::TimeoutError => e
      {
        notarized: false,
        message: "Notarization check timed out",
        details: e.message
      }
    rescue SafeShell::ExecutionError => e
      {
        notarized: false,
        message: "Notarization check failed",
        details: e.message
      }
    end
  end

  # Check if file has quarantine attribute
  #
  # macOS sets com.apple.quarantine on files downloaded from the internet.
  # This triggers Gatekeeper checks on first open.
  #
  # @param path [String] Path to file
  # @return [Hash] Result with :quarantined, :details keys
  #
  # @example Check quarantine
  #   result = MacOSSecurity.check_quarantine('downloaded.dmg')
  #   if result[:quarantined]
  #     puts "File is quarantined (downloaded from internet)"
  #   end
  def self.check_quarantine(path)
    return { quarantined: false, message: "Not on macOS" } unless RUBY_PLATFORM.include?('darwin')
    return { quarantined: false, message: "File not found" } unless File.exist?(path)

    begin
      output = SafeShell.execute('xattr', '-p', 'com.apple.quarantine', path,
                                 timeout: 5, allowed_failures: true)

      if $?.success? && !output.strip.empty?
        {
          quarantined: true,
          message: "File has quarantine attribute",
          details: output.strip
        }
      else
        {
          quarantined: false,
          message: "File does not have quarantine attribute"
        }
      end
    rescue StandardError => e
      {
        quarantined: false,
        message: "Could not check quarantine attribute",
        error: e.message
      }
    end
  end

  # Remove quarantine attribute from a file
  #
  # Useful when mirroring files to avoid unnecessary Gatekeeper prompts.
  #
  # @param path [String] Path to file
  # @return [Boolean] True if successful
  #
  # @example Remove quarantine
  #   if MacOSSecurity.remove_quarantine('/path/to/file.dmg')
  #     puts "Quarantine removed"
  #   end
  def self.remove_quarantine(path)
    return false unless RUBY_PLATFORM.include?('darwin')
    return false unless File.exist?(path)

    begin
      SafeShell.execute('xattr', '-d', 'com.apple.quarantine', path,
                       timeout: 5, allowed_failures: true)
      $?.success?
    rescue StandardError
      false
    end
  end

  # Comprehensive security check for a cask file
  #
  # Performs signature verification and notarization check.
  # Returns structured results for decision making.
  #
  # @param path [String] Path to cask file (.dmg, .pkg, .app)
  # @param options [Hash] Options hash
  # @option options [Boolean] :strict If true, fail on missing notarization
  # @return [Hash] Results with :safe, :warnings, :errors keys
  #
  # @example Check cask security
  #   result = MacOSSecurity.check_cask_security('app.dmg', strict: true)
  #   if result[:safe]
  #     puts "Safe to install"
  #   else
  #     warn "Security issues: #{result[:errors].join(', ')}"
  #   end
  def self.check_cask_security(path, options = {})
    strict = options.fetch(:strict, false)

    result = {
      safe: true,
      warnings: [],
      errors: [],
      details: {}
    }

    # Check signature
    sig_result = verify_signature(path)
    result[:details][:signature] = sig_result

    unless sig_result[:valid]
      result[:safe] = false
      result[:errors] << "Invalid or missing code signature"
    end

    # Check notarization
    notary_result = check_notarization(path)
    result[:details][:notarization] = notary_result

    if notary_result[:notarized]
      # Good - file is notarized
    elsif strict
      result[:safe] = false
      result[:errors] << "File is not notarized (strict mode)"
    else
      result[:warnings] << "File is not notarized (may be old or from non-App Store source)"
    end

    # Check quarantine
    quar_result = check_quarantine(path)
    result[:details][:quarantine] = quar_result

    if quar_result[:quarantined]
      result[:warnings] << "File has quarantine attribute (will trigger Gatekeeper on first use)"
    end

    result
  end

  # Verify SHA256 checksum of a file
  #
  # @param path [String] Path to file
  # @param expected_sha256 [String] Expected SHA256 hash (64 hex chars)
  # @return [Hash] Result with :valid, :message, :actual keys
  #
  # @example Verify checksum
  #   result = MacOSSecurity.verify_checksum('file.dmg', 'abc123...')
  #   unless result[:valid]
  #     warn "Checksum mismatch! Got: #{result[:actual]}"
  #   end
  def self.verify_checksum(path, expected_sha256)
    return { valid: false, message: "File not found" } unless File.exist?(path)
    return { valid: false, message: "Expected checksum is empty" } if expected_sha256.nil? || expected_sha256.empty?

    begin
      if RUBY_PLATFORM.include?('darwin')
        output = SafeShell.execute('shasum', '-a', '256', path, timeout: 300)
      else
        output = SafeShell.execute('sha256sum', path, timeout: 300)
      end

      # Output format: "hash  filename"
      actual_sha256 = output.split.first

      if actual_sha256.downcase == expected_sha256.downcase
        {
          valid: true,
          message: "Checksum matches",
          actual: actual_sha256
        }
      else
        {
          valid: false,
          message: "Checksum mismatch",
          expected: expected_sha256,
          actual: actual_sha256
        }
      end
    rescue SafeShell::TimeoutError => e
      {
        valid: false,
        message: "Checksum calculation timed out (large file?)",
        error: e.message
      }
    rescue SafeShell::ExecutionError => e
      {
        valid: false,
        message: "Checksum calculation failed",
        error: e.message
      }
    end
  end
end
