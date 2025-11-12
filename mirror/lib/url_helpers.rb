#!/usr/bin/env ruby
# frozen_string_literal: true

require "uri"

# URLHelpers: Utilities for URL manipulation and matching
#
# This module provides methods for normalizing URLs and matching them
# against a urlmap, handling common variations like query parameters,
# fragments, trailing slashes, and URL encoding.
#
# Usage:
#   require_relative 'url_helpers'
#
#   variants = URLHelpers.normalize_for_matching(url)
#   mapped = URLHelpers.find_in_urlmap(url, urlmap)
module URLHelpers
  # Normalize a URL for matching against urlmap
  #
  # Generates multiple variants of a URL to try matching,
  # handling common URL variations that should be considered equivalent.
  #
  # @param url [String] The URL to normalize
  # @return [Array<String>] Array of URL variants to try matching
  #
  # @example Normalize a URL with query parameters
  #   URLHelpers.normalize_for_matching("https://example.com/file.dmg?version=1.0")
  #   # => ["https://example.com/file.dmg?version=1.0", "https://example.com/file.dmg", ...]
  def self.normalize_for_matching(url)
    variants = []

    # Original URL (try exact match first)
    variants << url

    # Without query string (most common cask URL issue)
    if url.include?("?")
      variants << url.split("?").first
    end

    # Without fragment
    if url.include?("#")
      variants << url.split("#").first
    end

    # Without both query and fragment
    if url.include?("?") || url.include?("#")
      base_url = url.split("?").first.split("#").first
      variants << base_url unless variants.include?(base_url)
    end

    # With/without trailing slash
    if url.end_with?("/")
      variants << url.chomp("/")
    else
      variants << "#{url}/" unless url.include?("?") || url.include?("#")
    end

    # URL decoded version (some URLs have %20 for spaces, etc.)
    begin
      decoded = URI.decode_www_form_component(url)
      variants << decoded if decoded != url
    rescue StandardError
      # Ignore decode errors
    end

    variants.compact.uniq
  end

  # Find a URL in urlmap, trying multiple variants
  #
  # Tries to find the URL in the urlmap by checking multiple normalized
  # variants. This handles cases where the URL being looked up differs
  # slightly from the URL stored in the urlmap.
  #
  # @param url [String] URL to find
  # @param urlmap [Hash] Hash mapping URLs to local filenames
  # @return [String, nil] Mapped filename or nil if not found
  #
  # @example Find URL with query parameters
  #   urlmap = {"https://example.com/file.dmg" => "abc123.dmg"}
  #   URLHelpers.find_in_urlmap("https://example.com/file.dmg?ver=1.0", urlmap)
  #   # => "abc123.dmg"
  def self.find_in_urlmap(url, urlmap)
    normalize_for_matching(url).each do |variant|
      return urlmap[variant] if urlmap[variant]
    end

    nil
  end

  # Extract base URL without query or fragment
  #
  # @param url [String] URL to clean
  # @return [String] URL without query or fragment
  #
  # @example Clean URL
  #   URLHelpers.clean_url("https://example.com/file.dmg?ver=1.0#download")
  #   # => "https://example.com/file.dmg"
  def self.clean_url(url)
    url.split("?").first.split("#").first
  end

  # Check if two URLs are equivalent (ignoring query/fragment)
  #
  # @param url1 [String] First URL
  # @param url2 [String] Second URL
  # @return [Boolean] True if URLs are equivalent
  #
  # @example Compare URLs
  #   URLHelpers.equivalent?("https://example.com/file.dmg?v=1", "https://example.com/file.dmg")
  #   # => true
  def self.equivalent?(url1, url2)
    clean_url(url1) == clean_url(url2)
  end
end
