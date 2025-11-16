#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "homebrew_paths"
require_relative "safe_shell"

# TapManager: Utilities for managing Homebrew taps
#
# This module provides utilities for working with Homebrew taps,
# including parsing tap names, checking installation status,
# and determining tap types.
#
# Usage:
#   require_relative 'tap_manager'
#
#   TapManager.tap_installed?("homebrew/homebrew-core")
#   TapManager.tap_commit("homebrew/homebrew-cask")
#   TapManager.tap_type("homebrew/homebrew-cask-fonts")
module TapManager
  # Expand shorthand tap names to full format
  #
  # @param tap_name [String] Tap name (full or shorthand)
  # @return [String] Expanded tap name in "user/repo" format
  #
  # @example Expand shorthand names
  #   TapManager.expand_tap_name("core")  # => "homebrew/homebrew-core"
  #   TapManager.expand_tap_name("cask")  # => "homebrew/homebrew-cask"
  #   TapManager.expand_tap_name("homebrew/homebrew-core")  # => "homebrew/homebrew-core"
  def self.expand_tap_name(tap_name)
    # Already in full format
    return tap_name if tap_name.include?("/")

    # Expand common shorthands
    case tap_name.downcase
    when "core"
      "homebrew/homebrew-core"
    when "cask", "casks"
      "homebrew/homebrew-cask"
    when "versions"
      "homebrew/homebrew-cask-versions"
    when "fonts"
      "homebrew/homebrew-cask-fonts"
    when "drivers"
      "homebrew/homebrew-cask-drivers"
    else
      # Assume it's a homebrew tap if no slash
      "homebrew/homebrew-#{tap_name}"
    end
  end

  # Parse tap name into user/repo components
  #
  # @param tap_name [String] Tap name in format "user/repo" or shorthand
  # @return [Hash] Hash with :user and :repo keys
  # @raise [SystemExit] If tap name format is invalid
  #
  # @example Parse a tap name
  #   parsed = TapManager.parse_tap_name("homebrew/homebrew-core")
  #   # => {:user => "homebrew", :repo => "homebrew-core"}
  #
  # @example Parse shorthand
  #   parsed = TapManager.parse_tap_name("core")
  #   # => {:user => "homebrew", :repo => "homebrew-core"}
  def self.parse_tap_name(tap_name)
    # Expand shorthand first
    expanded = expand_tap_name(tap_name)

    parts = expanded.split("/")
    if parts.length == 2
      { user: parts[0], repo: parts[1] }
    else
      abort "Invalid tap name: #{tap_name}. Expected format: user/repo or shorthand (core, cask, etc.)"
    end
  end

  # Get tap directory path
  #
  # @param tap_name [String] Tap name in format "user/repo"
  # @return [String] Full path to tap directory
  #
  # @example Get tap directory
  #   dir = TapManager.tap_directory("homebrew/homebrew-core")
  #   # => "/opt/homebrew/Library/Taps/homebrew/homebrew-core"
  def self.tap_directory(tap_name)
    parsed = parse_tap_name(tap_name)
    HomebrewPaths.tap_path(parsed[:user], parsed[:repo])
  end

  # Check if tap is installed
  #
  # Modern Homebrew (5.0+) bundles core and cask taps instead of installing
  # them as separate directories. This method handles both traditional tapped
  # installations and bundled taps.
  #
  # Check if tap is installed
  #
  # @param tap_name [String] Tap name in format "user/repo"
  # @return [Boolean] True if tap is available
  #
  # @example Check tap installation
  #   installed = TapManager.tap_installed?("homebrew/homebrew-core")
  #   # => true (bundled in Homebrew 5.0+)
  def self.tap_installed?(tap_name)
    # Check if tap directory exists (for non-bundled taps)
    return true if Dir.exist?(tap_directory(tap_name))

    # Core and Cask are always available (bundled in Homebrew 5.0+)
    tap_name == "homebrew/homebrew-core" || tap_name == "homebrew/homebrew-cask"
  end

  # Check if a tap is available in Homebrew (for bundled taps)
  #
  # @param tap_name [String] Tap name in format "user/repo"
  # @return [Boolean] True if tap is bundled
  #
  # @example Check if core tap is available
  #   available = TapManager.tap_available_in_homebrew?("homebrew/homebrew-core")
  #   # => true
  def self.tap_available_in_homebrew?(tap_name)
    # Core and cask are always bundled in Homebrew 5.0+
    tap_name == "homebrew/homebrew-core" || tap_name == "homebrew/homebrew-cask"
  end

  # Get current commit hash of tap
  #
  # For Homebrew 5.0+, bundled taps return a synthetic commit based on version
  #
  # @param tap_name [String] Tap name in format "user/repo"
  # @return [String, nil] Commit hash or nil if tap not installed
  #
  # @example Get tap commit
  #   commit = TapManager.tap_commit("homebrew/homebrew-core")
  #   # => "bundled-5.0.1"
  def self.tap_commit(tap_name)
    # Bundled taps use synthetic commit based on Homebrew version
    if tap_name == "homebrew/homebrew-core" || tap_name == "homebrew/homebrew-cask"
      # Use environment variable or default version
      version = ENV['HOMEBREW_VERSION'] || "5.0"
      return "bundled-#{version}"
    end

    # For non-bundled taps, check directory
    tap_dir = tap_directory(tap_name)
    if Dir.exist?(tap_dir)
      Dir.chdir tap_dir do
        begin
          return SafeShell.execute('git', 'rev-parse', 'HEAD', timeout: 10).strip
        rescue SafeShell::ExecutionError, SafeShell::TimeoutError
          nil
        end
      end
    end

    nil
  end

  # Determine tap type (formula, cask, or mixed)
  #
  # Identifies the primary content type of a tap based on its name
  # and directory structure.
  #
  # @param tap_name [String] Tap name in format "user/repo"
  # @return [String] "formula", "cask", or "mixed"
  #
  # @example Determine tap type
  #   TapManager.tap_type("homebrew/homebrew-core")  # => "formula"
  #   TapManager.tap_type("homebrew/homebrew-cask")  # => "cask"
  #   TapManager.tap_type("homebrew/homebrew-cask-fonts")  # => "cask"
  def self.tap_type(tap_name)
    # Core tap is always formula-only
    return "formula" if tap_name == "homebrew/homebrew-core"

    # Any tap with "cask" in the name is cask-based
    return "cask" if tap_name.include?("cask")

    # Check directory structure for other taps
    tap_dir = tap_directory(tap_name)
    return "mixed" unless Dir.exist?(tap_dir)

    has_formulae = Dir.exist?(File.join(tap_dir, "Formula"))
    has_casks = Dir.exist?(File.join(tap_dir, "Casks"))

    if has_formulae && has_casks
      "mixed"
    elsif has_casks
      "cask"
    elsif has_formulae
      "formula"
    else
      "mixed"  # Unknown, treat as mixed to try both
    end
  end

  # Install tap if not present (interactive)
  #
  # Prompts the user to install a tap if it's not already installed.
  #
  # @param tap_name [String] Tap name in format "user/repo"
  # @return [Boolean] True if tap is installed (was already or just installed)
  #
  # @example Ensure tap is installed
  #   TapManager.ensure_tap_installed("homebrew/homebrew-cask-fonts")
  def self.ensure_tap_installed(tap_name)
    return true if tap_installed?(tap_name)

    puts "Tap not installed: #{tap_name}"
    print "Install now? (y/n): "
    return false unless $stdin.gets.chomp.downcase == "y"

    system "brew", "tap", tap_name
  end

  # Get list of all installed taps
  #
  # Includes both traditional tapped installations and bundled taps
  # (core/cask in modern Homebrew).
  #
  # @return [Array<String>] Array of tap names in "user/repo" format
  #
  # @example List all taps
  #   taps = TapManager.all_installed_taps
  #   # => ["homebrew/homebrew-core", "homebrew/homebrew-cask", ...]
  def self.all_installed_taps
    # Bundled taps are always available
    taps = ["homebrew/homebrew-core", "homebrew/homebrew-cask"]

    # Add traditional tapped installations (non-bundled taps)
    taps_dir = HomebrewPaths.taps_path
    if Dir.exist?(taps_dir)
      Dir.glob("#{taps_dir}/*/*").each do |tap_dir|
        next unless File.directory?(tap_dir)

        parts = tap_dir.split("/")
        user = parts[-2]
        repo = parts[-1]
        tap_name = "#{user}/#{repo}"
        # Avoid duplicates (in case bundled tap also has directory)
        taps << tap_name unless taps.include?(tap_name)
      end
    end

    taps.sort
  end
end
