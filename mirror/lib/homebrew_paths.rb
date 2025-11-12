#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'safe_shell'

# HomebrewPaths: Utility module for detecting Homebrew installation paths
# across different platforms and architectures.
#
# This module dynamically detects where Homebrew is installed on the system,
# supporting both Intel Macs (/usr/local) and Apple Silicon Macs (/opt/homebrew).
#
# Usage:
#   require_relative 'homebrew_paths'
#
#   prefix = HomebrewPaths.homebrew_prefix
#   core_tap = HomebrewPaths.core_tap_path
#   all = HomebrewPaths.all_paths
module HomebrewPaths
  # Detect the Homebrew prefix (installation root)
  #
  # Tries in order:
  # 1. HOMEBREW_PREFIX environment variable
  # 2. `brew --prefix` command
  # 3. Architecture-specific defaults
  #
  # @return [String] Path to Homebrew prefix
  #
  # @example Get Homebrew prefix
  #   HomebrewPaths.homebrew_prefix
  #   # => "/opt/homebrew" (on Apple Silicon)
  #   # => "/usr/local" (on Intel Mac)
  def self.homebrew_prefix
    # First, try to use Homebrew's own environment variable
    return ENV["HOMEBREW_PREFIX"] if ENV["HOMEBREW_PREFIX"] && !ENV["HOMEBREW_PREFIX"].empty?

    # Next, try running `brew --prefix` command
    begin
      prefix = SafeShell.execute('brew', '--prefix', timeout: 5).chomp
      return prefix if !prefix.empty?
    rescue SafeShell::ExecutionError, SafeShell::TimeoutError
      # Fall through to defaults
    end

    # Fall back to architecture-specific defaults
    if RUBY_PLATFORM.include?("arm64") || RUBY_PLATFORM.include?("aarch64")
      # Apple Silicon or ARM64 Linux
      "/opt/homebrew"
    else
      # Intel Mac or x86_64 Linux
      "/usr/local"
    end
  end

  # Get the Homebrew repository path (where Homebrew itself is installed)
  #
  # @return [String] Path to Homebrew repository
  #
  # @example Get repository path
  #   HomebrewPaths.homebrew_repository
  #   # => "/opt/homebrew/Homebrew"
  def self.homebrew_repository
    return ENV["HOMEBREW_REPOSITORY"] if ENV["HOMEBREW_REPOSITORY"] && !ENV["HOMEBREW_REPOSITORY"].empty?

    begin
      repo = SafeShell.execute('brew', '--repository', timeout: 5).chomp
      return repo if !repo.empty?
    rescue SafeShell::ExecutionError, SafeShell::TimeoutError
      # Fall through to default
    end

    # Default: Homebrew directory under prefix
    File.join(homebrew_prefix, "Homebrew")
  end

  # Get the Homebrew library path (where taps and formulae are stored)
  #
  # @return [String] Path to Homebrew library
  #
  # @example Get library path
  #   HomebrewPaths.homebrew_library
  #   # => "/opt/homebrew/Homebrew/Library"
  def self.homebrew_library
    return ENV["HOMEBREW_LIBRARY"] if ENV["HOMEBREW_LIBRARY"] && !ENV["HOMEBREW_LIBRARY"].empty?

    File.join(homebrew_repository, "Library")
  end

  # Get the path to the Taps directory
  #
  # @return [String] Path to Taps directory
  #
  # @example Get taps directory
  #   HomebrewPaths.taps_path
  #   # => "/opt/homebrew/Homebrew/Library/Taps"
  def self.taps_path
    File.join(homebrew_library, "Taps")
  end

  # Get the path to a specific tap
  #
  # @param user [String] Tap user (e.g., "homebrew")
  # @param repo [String] Tap repository (e.g., "homebrew-core")
  # @return [String] Path to tap directory
  #
  # @example Get custom tap path
  #   HomebrewPaths.tap_path("homebrew", "homebrew-cask")
  #   # => "/opt/homebrew/Homebrew/Library/Taps/homebrew/homebrew-cask"
  def self.tap_path(user, repo)
    File.join(taps_path, user, repo)
  end

  # Convenience method for homebrew-core tap
  #
  # @return [String] Path to homebrew-core tap
  #
  # @example Get core tap path
  #   HomebrewPaths.core_tap_path
  #   # => "/opt/homebrew/Homebrew/Library/Taps/homebrew/homebrew-core"
  def self.core_tap_path
    tap_path("homebrew", "homebrew-core")
  end

  # Convenience method for homebrew-cask tap
  #
  # @return [String] Path to homebrew-cask tap
  #
  # @example Get cask tap path
  #   HomebrewPaths.cask_tap_path
  #   # => "/opt/homebrew/Homebrew/Library/Taps/homebrew/homebrew-cask"
  def self.cask_tap_path
    tap_path("homebrew", "homebrew-cask")
  end

  # Verify that Homebrew is actually installed and in PATH
  #
  # @return [Boolean] True if brew command is available
  #
  # @example Check if Homebrew is installed
  #   if HomebrewPaths.homebrew_installed?
  #     puts "Homebrew is ready"
  #   end
  def self.homebrew_installed?
    SafeShell.execute?('which', 'brew', timeout: 5)
  end

  # Get Homebrew version
  #
  # @return [String, nil] Version string or nil if not available
  #
  # @example Get Homebrew version
  #   HomebrewPaths.homebrew_version
  #   # => "4.0.0"
  def self.homebrew_version
    return nil unless homebrew_installed?

    begin
      output = SafeShell.execute('brew', '--version', timeout: 5)
      # Output format: "Homebrew 4.0.0\n..."
      if output =~ /Homebrew\s+([\d.]+)/
        $1
      end
    rescue SafeShell::ExecutionError, SafeShell::TimeoutError
      nil
    end
  end

  # Get all paths as a hash (useful for debugging)
  #
  # @return [Hash] Hash of path names to paths
  #
  # @example Get all paths
  #   HomebrewPaths.all_paths.each do |name, path|
  #     puts "#{name}: #{path}"
  #   end
  def self.all_paths
    {
      prefix: homebrew_prefix,
      repository: homebrew_repository,
      library: homebrew_library,
      core_tap: core_tap_path,
      cask_tap: cask_tap_path,
    }
  end

  # Verify that a tap exists at the expected location
  #
  # @param user [String] Tap user
  # @param repo [String] Tap repository
  # @return [Boolean] True if tap directory exists
  #
  # @example Check if core tap exists
  #   if HomebrewPaths.tap_exists?("homebrew", "homebrew-core")
  #     puts "Core tap is installed"
  #   end
  def self.tap_exists?(user, repo)
    Dir.exist?(tap_path(user, repo))
  end

  # Verify that core tap exists
  #
  # @return [Boolean] True if core tap exists
  def self.core_tap_exists?
    tap_exists?("homebrew", "homebrew-core")
  end

  # Verify that cask tap exists
  #
  # @return [Boolean] True if cask tap exists
  def self.cask_tap_exists?
    tap_exists?("homebrew", "homebrew-cask")
  end

  # Get current commit SHA for a tap
  #
  # @param user [String] Tap user
  # @param repo [String] Tap repository
  # @return [String, nil] Commit SHA or nil if not a git repository
  #
  # @example Get core tap commit
  #   commit = HomebrewPaths.tap_commit("homebrew", "homebrew-core")
  #   puts "Core tap is at: #{commit[0..7]}"
  def self.tap_commit(user, repo)
    tap_dir = tap_path(user, repo)
    return nil unless Dir.exist?(tap_dir)

    begin
      Dir.chdir(tap_dir) do
        SafeShell.execute('git', 'rev-parse', 'HEAD', timeout: 5).chomp
      end
    rescue SafeShell::ExecutionError, SafeShell::TimeoutError
      nil
    end
  end

  # Get current commit SHA for core tap
  #
  # @return [String, nil] Commit SHA or nil
  def self.core_tap_commit
    tap_commit("homebrew", "homebrew-core")
  end

  # Get current commit SHA for cask tap
  #
  # @return [String, nil] Commit SHA or nil
  def self.cask_tap_commit
    tap_commit("homebrew", "homebrew-cask")
  end
end
