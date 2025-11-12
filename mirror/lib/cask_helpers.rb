#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'homebrew_paths'

# CaskHelpers: Utilities for working with Homebrew casks
#
# This module provides safe methods for interacting with the Homebrew Cask API,
# handling API differences across different Homebrew versions.
#
# Usage:
#   require_relative 'cask_helpers'
#
#   if CaskHelpers.cask_api_available?
#     casks = CaskHelpers.all_casks
#     casks.each do |cask|
#       puts cask.token
#     end
#   end
module CaskHelpers
  # Safely get all casks, handling API differences
  #
  # Tries multiple methods to load all available casks:
  # 1. Modern API: Cask::Cask.all
  # 2. Alternative: Cask.to_a
  # 3. Fallback: Read cask files from tap directory
  #
  # @return [Array<Cask>] Array of cask objects
  #
  # @example Get all casks
  #   casks = CaskHelpers.all_casks
  #   puts "Found #{casks.count} casks"
  def self.all_casks
    begin
      # Try modern API first
      if defined?(Cask::Cask) && Cask::Cask.respond_to?(:all)
        # Cask::Cask.all requires HOMEBREW_EVAL_ALL to be set
        ENV['HOMEBREW_EVAL_ALL'] = '1'
        return Cask::Cask.all
      end

      # Try alternative methods
      if defined?(Cask) && Cask.respond_to?(:to_a)
        return Cask.to_a
      end

      # Last resort: iterate tap directory
      cask_dir = File.join(HomebrewPaths.cask_tap_path, "Casks")
      return [] unless Dir.exist?(cask_dir)

      warn "Using fallback: loading casks from #{cask_dir}"

      Dir.glob("#{cask_dir}/*.rb").map do |path|
        token = File.basename(path, ".rb")
        Cask::CaskLoader.load(token)
      end
    rescue StandardError => e
      warn "Error loading casks: #{e.message}"
      []
    end
  end

  # Check if cask API is available
  #
  # @return [Boolean] True if Cask classes are defined
  #
  # @example Check cask API
  #   if CaskHelpers.cask_api_available?
  #     puts "Cask support enabled"
  #   end
  def self.cask_api_available?
    defined?(Cask::Cask) && defined?(Cask::CaskLoader)
  end

  # Safely load a specific cask by token
  #
  # @param token [String] Cask token (e.g., "firefox")
  # @return [Cask, nil] Cask object or nil if not found
  #
  # @example Load a cask
  #   cask = CaskHelpers.load_cask("firefox")
  #   puts cask.name if cask
  def self.load_cask(token)
    return nil unless cask_api_available?

    begin
      Cask::CaskLoader.load(token)
    rescue StandardError => e
      warn "Failed to load cask '#{token}': #{e.message}"
      nil
    end
  end

  # Load multiple casks by token
  #
  # @param tokens [Array<String>] Array of cask tokens
  # @return [Array<Cask>] Array of successfully loaded casks
  #
  # @example Load specific casks
  #   casks = CaskHelpers.load_casks(["firefox", "chrome"])
  def self.load_casks(tokens)
    tokens.map { |token| load_cask(token) }.compact
  end

  # Check if a cask has a downloadable URL
  #
  # @param cask [Cask] Cask object
  # @return [Boolean] True if cask has a URL
  def self.has_url?(cask)
    cask.respond_to?(:url) && !cask.url.nil?
  end

  # Get cask SHA256 checksum (if available)
  #
  # @param cask [Cask] Cask object
  # @return [String, Symbol, nil] Checksum or :no_check or nil
  def self.checksum(cask)
    return nil unless cask.respond_to?(:sha256)

    cask.sha256
  end
end
