#!/usr/bin/env ruby
# frozen_string_literal: true

# DownloadHelpers: Utilities for reliable downloading
#
# This module provides robust download methods with retry logic,
# timeout handling, and cleanup of failed downloads.
#
# Usage:
#   require_relative 'download_helpers'
#
#   success = DownloadHelpers.fetch_with_retry(downloader, max_retries: 3)
#   DownloadHelpers.cleanup_partial(file_path)
module DownloadHelpers
  # Download with retries and exponential backoff
  #
  # Attempts to fetch a resource multiple times with increasing delays
  # between attempts. This helps handle transient network errors.
  #
  # @param downloader [Object] Homebrew download strategy instance
  # @param max_retries [Integer] Maximum number of retry attempts
  # @return [Boolean] True if download succeeded
  #
  # @example Download with retries
  #   success = DownloadHelpers.fetch_with_retry(downloader, max_retries: 3)
  #   if success
  #     puts "Download completed"
  #   else
  #     puts "Download failed after retries"
  #   end
  def self.fetch_with_retry(downloader, max_retries: 3)
    attempts = 0

    loop do
      attempts += 1

      begin
        downloader.fetch
        return true
      rescue StandardError => e
        if attempts >= max_retries
          warn "Download failed after #{attempts} attempt(s): #{e.message}"
          return false
        end

        # Exponential backoff: 2s, 4s, 8s, etc.
        delay = attempts * 2
        warn "Download attempt #{attempts} failed: #{e.message}"
        warn "Retrying in #{delay} seconds..."
        sleep delay
      end
    end
  end

  # Clean up partial or corrupted downloads
  #
  # Removes zero-byte files or files below a minimum size threshold.
  # This helps clean up after failed downloads.
  #
  # @param path [Pathname, String] Path to check and potentially remove
  # @param min_size [Integer] Minimum file size in bytes (default: 1)
  # @return [Boolean] True if file was removed
  #
  # @example Clean up zero-byte files
  #   DownloadHelpers.cleanup_partial(download_path)
  def self.cleanup_partial(path, min_size: 1)
    path = Pathname.new(path) unless path.is_a?(Pathname)

    return false unless path.exist?

    if path.size < min_size
      warn "Removing partial download (#{path.size} bytes): #{path}"
      path.delete
      return true
    end

    false
  end

  # Verify download integrity using checksum
  #
  # @param path [Pathname, String] Path to downloaded file
  # @param expected_checksum [String, Symbol] Expected SHA256 checksum or :no_check
  # @return [Boolean] True if checksum matches or :no_check
  #
  # @example Verify checksum
  #   valid = DownloadHelpers.verify_checksum(path, "abc123...")
  def self.verify_checksum(path, expected_checksum)
    path = Pathname.new(path) unless path.is_a?(Pathname)

    return true if expected_checksum == :no_check
    return false unless path.exist?
    return false unless expected_checksum

    require "digest"
    actual = Digest::SHA256.file(path).hexdigest

    if actual == expected_checksum.to_s
      true
    else
      warn "Checksum mismatch!"
      warn "  Expected: #{expected_checksum}"
      warn "  Actual:   #{actual}"
      false
    end
  rescue StandardError => e
    warn "Error verifying checksum: #{e.message}"
    false
  end

  # Estimate download progress (if possible)
  #
  # @param downloader [Object] Download strategy instance
  # @return [Hash, nil] Hash with :current and :total bytes, or nil
  def self.download_progress(downloader)
    return nil unless downloader.respond_to?(:cached_location)

    cached = downloader.cached_location
    return nil unless cached && cached.exist?

    {
      current: cached.size,
      total: nil,  # Homebrew downloaders don't expose total size
    }
  rescue StandardError
    nil
  end

  # Check if download is already cached
  #
  # @param downloader [Object] Download strategy instance
  # @return [Boolean] True if file is already in cache
  #
  # @example Check if cached
  #   if DownloadHelpers.cached?(downloader)
  #     puts "Already downloaded"
  #   end
  def self.cached?(downloader)
    return false unless downloader.respond_to?(:cached_location)

    location = downloader.cached_location
    location && location.exist? && location.size.positive?
  rescue StandardError
    false
  end

  # Get cached file size
  #
  # @param downloader [Object] Download strategy instance
  # @return [Integer, nil] File size in bytes, or nil if not cached
  def self.cached_size(downloader)
    return nil unless downloader.respond_to?(:cached_location)

    location = downloader.cached_location
    return nil unless location && location.exist?

    location.size
  rescue StandardError
    nil
  end

  # Format download speed
  #
  # @param bytes [Integer] Number of bytes
  # @param seconds [Float] Time in seconds
  # @return [String] Human-readable speed (e.g., "5.2 MB/s")
  #
  # @example Calculate speed
  #   speed = DownloadHelpers.format_speed(5242880, 1.0)
  #   # => "5.0 MB/s"
  def self.format_speed(bytes, seconds)
    return "0 B/s" if seconds.zero?

    bytes_per_sec = bytes / seconds
    units = %w[B/s KB/s MB/s GB/s]
    unit_index = 0

    while bytes_per_sec >= 1024 && unit_index < units.length - 1
      bytes_per_sec /= 1024.0
      unit_index += 1
    end

    format("%.1f %s", bytes_per_sec, units[unit_index])
  end
end
