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
  # Get all casks using modern Cask API (Homebrew 5.0+)
  #
  # @return [Array<Cask>] Array of cask objects
  #
  # @example Get all casks
  #   casks = CaskHelpers.all_casks
  #   puts "Found #{casks.count} casks"
  def self.all_casks
    # Use modern Cask API (Homebrew 5.0+)
    ENV['HOMEBREW_EVAL_ALL'] = '1'
    Cask::Cask.all
  end

  # Check if cask API is available
  #
  # @return [Boolean] Always true in Homebrew 5.0+
  #
  # @example Check cask API
  #   if CaskHelpers.cask_api_available?
  #     puts "Cask support enabled"
  #   end
  def self.cask_api_available?
    # Always true in Homebrew 5.0+
    true
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
  # @param cask [Cask] Cask object (Homebrew 5.0+)
  # @return [Boolean] True if cask has a URL
  def self.has_url?(cask)
    # Direct attribute access (Homebrew 5.0+)
    !cask.url.nil?
  end

  # Get cask SHA256 checksum (if available)
  #
  # @param cask [Cask] Cask object (Homebrew 5.0+)
  # @return [String, Symbol, nil] Checksum or :no_check or nil
  def self.checksum(cask)
    # Direct sha256 access (Homebrew 5.0+)
    cask.sha256
  end
end
