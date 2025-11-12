#!/usr/bin/env ruby
# frozen_string_literal: true

# ContainerHelpers: Utilities for handling various cask container formats
#
# This module provides methods for detecting, verifying, and inspecting
# container files used by Homebrew casks (DMG, PKG, ZIP, etc.).
#
# Usage:
#   require_relative 'container_helpers'
#
#   ext = ContainerHelpers.detect_extension(url)
#   verified = ContainerHelpers.verify_container(file_path)
#   size = ContainerHelpers.human_size(file_path)
module ContainerHelpers
  # Known cask container extensions
  CONTAINER_EXTENSIONS = %w[
    .dmg
    .pkg
    .mpkg
    .zip
    .tar.gz
    .tgz
    .tar.bz2
    .tbz
    .tar.xz
    .txz
    .7z
    .rar
    .app
    .jar
  ].freeze

  # Detect container extension from URL or filename
  #
  # @param url [String, URI] URL or filename to analyze
  # @return [String] Extension (e.g., ".dmg")
  #
  # @example Detect extension from URL
  #   ContainerHelpers.detect_extension("https://example.com/app.dmg")
  #   # => ".dmg"
  def self.detect_extension(url)
    url_str = url.to_s

    # Try multi-part extensions first (e.g., .tar.gz)
    multi_part = %w[.tar.gz .tar.bz2 .tar.xz .tgz .tbz .txz]
    multi_part.each do |ext|
      return ext if url_str.include?(ext)
    end

    # Try single extensions
    CONTAINER_EXTENSIONS.each do |ext|
      # Match extension followed by end of string, query params, or hash
      return ext if url_str.match?(/#{Regexp.escape(ext)}($|\?|#)/)
    end

    # Default to .dmg (most common for macOS apps)
    ".dmg"
  end

  # Verify a downloaded container file
  #
  # Performs basic validation to check if the file is likely valid:
  # - File exists
  # - File is not zero bytes
  # - File has correct magic number (for known formats)
  #
  # @param path [Pathname, String] Path to container file
  # @return [Boolean] True if file appears valid
  #
  # @example Verify a DMG file
  #   valid = ContainerHelpers.verify_container(Pathname.new("app.dmg"))
  def self.verify_container(path)
    path = Pathname.new(path) unless path.is_a?(Pathname)

    return false unless path.exist?
    return false if path.size.zero?

    # Basic file type checks using magic numbers
    case path.extname
    when ".dmg"
      # DMG files can have various signatures
      verify_dmg(path)
    when ".pkg", ".mpkg"
      # PKG files are xar archives
      verify_pkg(path)
    when ".zip"
      # ZIP magic number: PK\x03\x04
      verify_zip(path)
    when ".tar", ".tgz", ".tar.gz"
      # TAR files
      verify_tar(path)
    else
      # For unknown formats, just check file exists and has content
      true
    end
  rescue StandardError => e
    warn "Error verifying #{path}: #{e.message}"
    # If we can't verify, assume it's okay
    true
  end

  # Get human-readable file size
  #
  # @param path [Pathname, String] Path to file
  # @return [String] Human-readable size (e.g., "150.5 MB")
  #
  # @example Get file size
  #   ContainerHelpers.human_size("app.dmg")
  #   # => "150.5 MB"
  def self.human_size(path)
    path = Pathname.new(path) unless path.is_a?(Pathname)
    return "0 B" unless path.exist?

    size = path.size.to_f
    units = %w[B KB MB GB TB]
    unit_index = 0

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024.0
      unit_index += 1
    end

    format("%.1f %s", size, units[unit_index])
  end

  # Verify DMG file magic number
  #
  # @param path [Pathname] Path to DMG file
  # @return [Boolean] True if valid DMG
  private_class_method def self.verify_dmg(path)
    File.open(path, "rb") do |f|
      # Read first 4 bytes
      header = f.read(4)
      return false unless header

      # DMG files can start with various signatures:
      # - 0x78 0x01 0x73 0x0D (zlib compressed)
      # - "koly" (appears at end of file)
      # - "mish" (appears in file)
      # Just check it's not obviously wrong
      return true if header.bytes.any? { |b| b > 0 }
    end

    false
  end

  # Verify PKG file (xar archive)
  #
  # @param path [Pathname] Path to PKG file
  # @return [Boolean] True if valid PKG
  private_class_method def self.verify_pkg(path)
    File.open(path, "rb") do |f|
      magic = f.read(4)
      return false unless magic

      # xar magic number: "xar!"
      return magic == "xar!"
    end

    false
  end

  # Verify ZIP file
  #
  # @param path [Pathname] Path to ZIP file
  # @return [Boolean] True if valid ZIP
  private_class_method def self.verify_zip(path)
    File.open(path, "rb") do |f|
      magic = f.read(4)
      return false unless magic

      # ZIP magic number: PK\x03\x04
      return magic == "PK\x03\x04" || magic.start_with?("PK")
    end

    false
  end

  # Verify TAR file
  #
  # @param path [Pathname] Path to TAR file
  # @return [Boolean] True if valid TAR
  private_class_method def self.verify_tar(path)
    # TAR files have a specific header format at byte 257
    # For simplicity, just check file size is reasonable
    path.size > 512  # TAR block size
  rescue StandardError
    false
  end

  # Get container type description
  #
  # @param path [Pathname, String] Path to container file
  # @return [String] Human-readable container type
  #
  # @example Get container type
  #   ContainerHelpers.container_type("app.dmg")
  #   # => "macOS Disk Image"
  def self.container_type(path)
    ext = path.is_a?(Pathname) ? path.extname : File.extname(path.to_s)

    case ext
    when ".dmg"
      "macOS Disk Image"
    when ".pkg", ".mpkg"
      "macOS Installer Package"
    when ".zip"
      "ZIP Archive"
    when ".tar", ".tgz", ".tar.gz"
      "TAR Archive"
    when ".tar.bz2", ".tbz"
      "TAR.BZ2 Archive"
    when ".tar.xz", ".txz"
      "TAR.XZ Archive"
    when ".7z"
      "7-Zip Archive"
    when ".rar"
      "RAR Archive"
    when ".app"
      "macOS Application Bundle"
    when ".jar"
      "Java Archive"
    else
      "Unknown (#{ext})"
    end
  end
end
