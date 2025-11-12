#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'safe_shell'

# OfflinebrewConfig: Shared utilities for finding configuration files
#
# This module helps locate offlinebrew configuration even when Homebrew
# runs commands in a sandboxed environment with a fake $HOME.
#
# Usage:
#   require_relative 'offlinebrew_config'
#
#   dir = OfflinebrewConfig.config_dir
#   config = OfflinebrewConfig.load_config
module OfflinebrewConfig
  # Find the real home directory, even when called from sandbox
  #
  # Homebrew sometimes runs scripts in a sandboxed environment with a fake
  # $HOME directory. This method tries multiple strategies to find the user's
  # real home directory.
  #
  # @return [String] Path to user's home directory
  #
  # @example Get real home
  #   home = OfflinebrewConfig.real_home_directory
  #   # => "/Users/username" (on macOS)
  def self.real_home_directory
    # Method 1: Use REAL_HOME if set (set by brew-offline-install)
    # This is the most reliable when we're in a sandboxed environment
    return ENV["REAL_HOME"] if ENV["REAL_HOME"] && !ENV["REAL_HOME"].empty?

    # Method 2: Use SUDO_USER if running under sudo
    # Common when installing system-wide packages
    if ENV["SUDO_USER"] && !ENV["SUDO_USER"].empty?
      user = ENV["SUDO_USER"]

      # Try getent (Linux)
      begin
        home = SafeShell.execute('getent', 'passwd', user, timeout: 5, allowed_failures: true)
        if $?.success? && !home.empty?
          # Format: username:password:uid:gid:comment:home:shell
          home_dir = home.split(':')[5]
          return home_dir if home_dir && Dir.exist?(home_dir)
        end
      rescue SafeShell::ExecutionError, SafeShell::TimeoutError
        # getent not available, try next method
      end

      # Try dscl (macOS)
      begin
        output = SafeShell.execute('dscl', '.', '-read', "/Users/#{user}", 'NFSHomeDirectory',
                                   timeout: 5, allowed_failures: true)
        if $?.success? && !output.empty?
          # Format: "NFSHomeDirectory: /Users/username"
          if output =~ /NFSHomeDirectory:\s*(.+)/
            home_dir = $1.strip
            return home_dir if Dir.exist?(home_dir)
          end
        end
      rescue SafeShell::ExecutionError, SafeShell::TimeoutError
        # dscl not available or failed
      end
    end

    # Method 3: Use original HOME if it looks reasonable
    # Skip obviously wrong values like /var/root
    if ENV["HOME"] && !ENV["HOME"].empty? && ENV["HOME"] != "/var/root"
      return ENV["HOME"]
    end

    # Method 4: Build from USER variable
    # Detect OS and construct appropriate path
    if ENV["USER"] && !ENV["USER"].empty?
      if File.exist?("/Users")
        # macOS
        return File.join("/Users", ENV["USER"])
      elsif File.exist?("/home")
        # Linux and other Unix
        return File.join("/home", ENV["USER"])
      end
    end

    # Method 5: Use Dir.home if available
    # This is Ruby's built-in method
    begin
      home = Dir.home
      return home if home && Dir.exist?(home)
    rescue ArgumentError
      # Dir.home can raise if HOME is not set
    end

    # Last resort: current directory
    # This will likely fail, but at least we tried
    Dir.pwd
  end

  # Get the offlinebrew config directory
  #
  # @return [String] Path to ~/.offlinebrew directory
  #
  # @example Get config dir
  #   dir = OfflinebrewConfig.config_dir
  #   # => "/Users/username/.offlinebrew"
  def self.config_dir
    File.join(real_home_directory, ".offlinebrew")
  end

  # Get the config file path
  #
  # @return [String] Path to config.json
  #
  # @example Get config path
  #   path = OfflinebrewConfig.config_path
  #   # => "/Users/username/.offlinebrew/config.json"
  def self.config_path
    File.join(config_dir, "config.json")
  end

  # Get the urlmap file path
  #
  # @return [String] Path to urlmap.json
  #
  # @example Get urlmap path
  #   path = OfflinebrewConfig.urlmap_path
  #   # => "/Users/username/.offlinebrew/urlmap.json"
  def self.urlmap_path
    File.join(config_dir, "urlmap.json")
  end

  # Load the config file
  #
  # @return [Hash] Parsed configuration
  # @raise [RuntimeError] If config file doesn't exist or is invalid
  #
  # @example Load config
  #   config = OfflinebrewConfig.load_config
  #   puts config[:baseurl]
  def self.load_config
    path = config_path
    raise "Config file not found: #{path}" unless File.exist?(path)

    require 'json'
    JSON.parse(File.read(path), symbolize_names: true)
  end

  # Load the urlmap file
  #
  # @return [Hash] Parsed URL mapping
  # @raise [RuntimeError] If urlmap file doesn't exist or is invalid
  #
  # @example Load urlmap
  #   urlmap = OfflinebrewConfig.load_urlmap
  #   mirror_url = urlmap["https://example.com/file.tar.gz"]
  def self.load_urlmap
    path = urlmap_path
    raise "Urlmap file not found: #{path}" unless File.exist?(path)

    require 'json'
    JSON.parse(File.read(path))
  end

  # Check if offlinebrew is configured
  #
  # @return [Boolean] True if config files exist
  #
  # @example Check if configured
  #   if OfflinebrewConfig.configured?
  #     puts "Offlinebrew is ready"
  #   end
  def self.configured?
    File.exist?(config_path) && File.exist?(urlmap_path)
  end

  # Create config directory if it doesn't exist
  #
  # @return [Boolean] True if successful
  #
  # @example Ensure directory exists
  #   OfflinebrewConfig.ensure_config_dir
  def self.ensure_config_dir
    SafeShell.mkdir_p(config_dir)
  end
end
