# frozen_string_literal: true

# BottleDownloader: Downloads Homebrew bottles (precompiled binaries) for formulas
#
# Bottles enable fast (<10 second) installations versus hours for source builds.
# This class handles downloading bottles for the current platform, verifying checksums,
# and updating the URL map for offline installations.
#
# Usage:
#   downloader = BottleDownloader.new(bottles_dir, urlmap, options)
#   downloader.download_all([Formula["jq"], Formula["curl"]])

require "fileutils"
require "digest"

class BottleDownloader
  attr_reader :bottles_dir, :urlmap, :options

  def initialize(bottles_dir, urlmap, options = {})
    @bottles_dir = bottles_dir
    @urlmap = urlmap
    @options = options
    FileUtils.mkdir_p(@bottles_dir)
  end

  # Download bottles for all formulas
  # Returns count of bottles downloaded
  def download_all(formulas)
    downloaded_count = 0

    formulas.each do |formula|
      # Skip if formula has no bottles
      next unless formula.bottle

      platform = current_platform
      bottle_info = extract_bottle_info(formula, platform)

      # Skip if no bottle for this platform
      next if bottle_info.nil? || bottle_info.empty?

      begin
        bottle_path = download_bottle(formula, platform)
        downloaded_count += 1 if bottle_path
      rescue => e
        opoo "Failed to download bottle for #{formula.name}: #{e.message}" if respond_to?(:opoo)
        warn "Failed to download bottle for #{formula.name}: #{e.message}" unless respond_to?(:opoo)
      end
    end

    downloaded_count
  end

  # Extract bottle information for a specific platform
  # Returns hash with :url and :sha256, or nil if unavailable
  def extract_bottle_info(formula, platform)
    return nil unless formula.bottle

    # Get bottle specification
    bottle_spec = formula.bottle_specification
    return nil unless bottle_spec

    # Find the checksum entry for this platform
    # checksums returns: [{"tag" => :arm64_sonoma, "digest" => #<Checksum...>, "cellar" => :any}, ...]
    platform_entry = bottle_spec.checksums.find { |entry| entry["tag"] == platform }
    return nil unless platform_entry

    checksum = platform_entry["digest"]
    filename = bottle_filename(formula, platform)
    bottle_url = construct_bottle_url(bottle_spec, filename, checksum)

    # Extract URL and SHA256
    {
      url: bottle_url,
      sha256: checksum.to_s
    }
  end

  # Download a single bottle for a formula and platform
  # Returns path to downloaded bottle, or nil if skipped
  def download_bottle(formula, platform)
    bottle_info = extract_bottle_info(formula, platform)
    return nil unless bottle_info

    # Compute target path
    bottle_path = compute_bottle_path(formula, platform)

    # Skip if already exists and checksum matches
    if File.exist?(bottle_path) && verify_sha256(bottle_path, bottle_info[:sha256])
      update_urlmap(bottle_info[:url], bottle_path)
      return bottle_path
    end

    # Download using Homebrew's bottle downloader
    ohai "Downloading bottle for #{formula.name} (#{platform})..." if respond_to?(:ohai)

    begin
      # Use formula's bottle download mechanism
      # This handles authentication and all the quirks of bottle downloads
      tag = Utils::Bottles::Tag.from_symbol(platform)
      bottle = formula.bottle_for_tag(tag)
      return nil unless bottle

      # Suppress downloader output
      if bottle.respond_to?(:quiet!)
        bottle.quiet!
      elsif bottle.respond_to?(:shutup!)
        bottle.shutup!
      end

      # Fetch the bottle (downloads to Homebrew cache)
      bottle.fetch

      # Get the cached location
      cached_location = bottle.cached_download

      # Move to our mirror location
      if cached_location.exist?
        FileUtils.mv cached_location.to_s, bottle_path, force: true
      else
        return nil
      end
    rescue => e
      warn "Failed to download bottle: #{e.message}"
      return nil
    end

    # Verify checksum
    unless verify_sha256(bottle_path, bottle_info[:sha256])
      File.delete(bottle_path) if File.exist?(bottle_path)
      raise "SHA256 checksum mismatch for #{formula.name} bottle"
    end

    # Update URL map
    update_urlmap(bottle_info[:url], bottle_path)

    bottle_path
  end

  # Detect current platform (e.g., :arm64_sonoma, :x86_64_monterey)
  def current_platform
    # Try to use Homebrew's platform detection if available
    if defined?(Homebrew) && Homebrew.respond_to?(:bottle_tag)
      return Homebrew.bottle_tag.to_sym
    end

    # Fallback: detect from RbConfig
    arch = RbConfig::CONFIG["host_cpu"]
    os_version = detect_macos_version

    arch_prefix = case arch
                  when /arm64|aarch64/
                    "arm64"
                  when /x86_64|amd64/
                    "x86_64"
                  else
                    arch
                  end

    "#{arch_prefix}_#{os_version}".to_sym
  end

  private

  # Compute the path where a bottle should be stored
  def compute_bottle_path(formula, platform)
    # Bottle filename pattern: formula--version.platform.bottle.tar.gz
    # We use the SHA256 of the URL as a prefix (like Homebrew does)
    bottle_info = extract_bottle_info(formula, platform)
    url_hash = Digest::SHA256.hexdigest(bottle_info[:url])[0..63]

    filename = "#{url_hash}--#{formula.name}--#{formula.version}.#{platform}.bottle.tar.gz"
    File.join(@bottles_dir, filename)
  end

  # Download a file from URL to local path
  def download_file(url, dest_path)
    # Ensure parent directory exists
    FileUtils.mkdir_p(File.dirname(dest_path))

    # Use curl for downloading (same as existing mirror code)
    system("curl", "-fL", "--progress-bar", "-o", dest_path, url, out: File::NULL, err: File::NULL)
    $?.success?
  end

  # Verify SHA256 checksum of a file
  def verify_sha256(file_path, expected_sha)
    return false unless File.exist?(file_path)

    actual_sha = Digest::SHA256.file(file_path).hexdigest
    actual_sha.downcase == expected_sha.downcase
  end

  # Update the URL map with bottle URL to filename mapping
  def update_urlmap(url, bottle_path)
    filename = File.basename(bottle_path)
    @urlmap[url.to_s] = filename

    # Also add clean URL variant (without query params) for better matching
    clean_url = url.to_s.split("?").first
    @urlmap[clean_url] = filename unless clean_url == url.to_s
  end

  # Detect macOS version name (sonoma, ventura, etc.)
  def detect_macos_version
    return "sonoma" unless RUBY_PLATFORM.include?("darwin")

    version_output = `sw_vers -productVersion 2>/dev/null`.strip
    major, minor = version_output.split(".").map(&:to_i)

    case major
    when 15
      "sequoia"
    when 14
      "sonoma"
    when 13
      "ventura"
    when 12
      "monterey"
    else
      "sonoma" # default fallback
    end
  rescue
    "sonoma" # fallback on error
  end

  # Generate bottle filename for platform
  def bottle_filename(formula, platform)
    "#{formula.name}--#{formula.version}.#{platform}.bottle.tar.gz"
  end

  # Construct full bottle URL
  def construct_bottle_url(bottle_spec, filename, checksum)
    root_url = bottle_spec.root_url || "https://ghcr.io/v2/homebrew/core"

    # GitHub Container Registry format
    if root_url.include?("ghcr.io")
      # Extract package name from filename (formula--version.platform.bottle.tar.gz)
      package = filename.split("--").first

      # Use blobs endpoint with SHA256
      "#{root_url}/#{package}/blobs/sha256:#{checksum}"
    else
      # Standard HTTP bottle URL
      "#{root_url}/#{filename}"
    end
  end

  # Helper methods that may be available from Homebrew context
  def ohai(msg)
    # Will be available when running in Homebrew context
    super if defined?(super)
  end

  def opoo(msg)
    # Will be available when running in Homebrew context
    super if defined?(super)
  end
end
