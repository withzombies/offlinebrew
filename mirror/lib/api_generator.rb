# frozen_string_literal: true

# ApiGenerator: Generate Homebrew-compatible API JSON files
#
# This module generates API JSON endpoints that match Homebrew's schema:
# - /api/formula.json - List of all formulas
# - /api/formula/<name>.json - Individual formula details with bottle metadata
#
# Usage:
#   formulas = [Formula["jq"], Formula["curl"]]
#   ApiGenerator.generate_all(formulas, "/path/to/mirror/api")
#
# Schema Reference: HOMEBREW_API_SCHEMA.md

require "json"
require "fileutils"

module ApiGenerator
  # Generate all API files for given formulas
  #
  # @param formulas [Array<Formula>] Array of Homebrew Formula objects
  # @param output_dir [String] Directory to write API files to
  # @return [void]
  def self.generate_all(formulas, output_dir)
    # Create directory structure
    FileUtils.mkdir_p(output_dir)
    formula_dir = File.join(output_dir, "formula")
    FileUtils.mkdir_p(formula_dir)

    # Generate formula list (formula.json)
    formula_list = generate_formula_list(formulas)
    formula_list_file = File.join(output_dir, "formula.json")
    File.write(formula_list_file, JSON.pretty_generate(formula_list))

    # Generate individual formula JSON files
    formulas.each do |formula|
      formula_json = generate_formula_json(formula)
      formula_file = File.join(formula_dir, "#{formula.name}.json")
      File.write(formula_file, JSON.pretty_generate(formula_json))
    end
  end

  # Generate formula list array
  #
  # @param formulas [Array<Formula>] Array of Formula objects
  # @return [Array<String>] Array of formula names
  def self.generate_formula_list(formulas)
    formulas.map(&:name).sort
  end

  # Generate complete formula JSON object
  #
  # @param formula [Formula] Homebrew Formula object
  # @return [Hash] Formula data matching Homebrew API schema
  def self.generate_formula_json(formula)
    data = {
      name: formula.name,
      full_name: formula.full_name,
      tap: formula.tap&.name || "homebrew/core",
      desc: formula.desc || "",
      license: extract_license(formula),
      homepage: formula.homepage || "",
      versions: extract_versions(formula),
      urls: extract_urls(formula),
      revision: formula.revision || 0,
      version_scheme: formula.version_scheme || 0,
    }

    # Add optional fields
    data[:build_dependencies] = formula.deps.select(&:build?).map(&:name).sort
    data[:dependencies] = formula.deps.reject(&:build?).map(&:name).sort
    data[:test_dependencies] = []

    # Add bottle metadata if available
    if formula.bottle
      data[:bottle] = extract_bottle_metadata(formula)
    end

    data
  end

  # Extract license information from formula
  #
  # @param formula [Formula] Homebrew Formula object
  # @return [String, nil] License identifier or nil
  def self.extract_license(formula)
    return nil unless formula.respond_to?(:license)

    license = formula.license
    return nil if license.nil?

    # Handle different license formats
    case license
    when String
      license
    when Symbol
      license.to_s
    when Array
      license.first.to_s
    else
      license.to_s
    end
  rescue
    nil
  end

  # Extract version information from formula
  #
  # @param formula [Formula] Homebrew Formula object
  # @return [Hash] Versions hash with stable, head, and bottle keys
  def self.extract_versions(formula)
    versions = {
      stable: formula.version.to_s,
    }

    # Add head version if available
    if formula.head
      versions[:head] = "HEAD"
    end

    # Add bottle availability flag
    versions[:bottle] = !formula.bottle.nil?

    versions
  end

  # Extract URL information from formula
  #
  # @param formula [Formula] Homebrew Formula object
  # @return [Hash] URLs hash with stable and optionally head keys
  def self.extract_urls(formula)
    urls = {}

    # Stable URL (required)
    if formula.stable
      urls[:stable] = {
        url: formula.stable.url,
        checksum: formula.stable.checksum&.to_s,
      }
    end

    # Head URL (optional)
    if formula.head
      urls[:head] = {
        url: formula.head.url,
      }

      # Add branch if it's a git URL
      if formula.head.respond_to?(:specs) && formula.head.specs[:branch]
        urls[:head][:branch] = formula.head.specs[:branch]
      end
    end

    urls
  end

  # Extract bottle metadata from formula
  #
  # @param formula [Formula] Homebrew Formula object
  # @return [Hash] Bottle metadata matching Homebrew API schema
  def self.extract_bottle_metadata(formula)
    return {} unless formula.bottle

    bottle_spec = formula.bottle_specification
    bottle_data = {
      stable: {
        rebuild: bottle_spec.rebuild || 0,
        root_url: bottle_spec.root_url || "https://ghcr.io/v2/homebrew/core",
        files: {},
      },
    }

    # Extract platform-specific bottle files from checksums array
    # checksums returns: [{"tag" => :arm64_sonoma, "digest" => #<Checksum...>, "cellar" => :any}, ...]
    bottle_spec.checksums.each do |entry|
      platform = entry["tag"]
      checksum = entry["digest"]
      cellar = entry["cellar"]

      # Generate bottle filename
      filename = bottle_filename(formula, platform)

      # Construct bottle URL
      bottle_url = construct_bottle_url(bottle_spec, filename, checksum)

      bottle_data[:stable][:files][platform] = {
        cellar: cellar,
        url: bottle_url,
        sha256: checksum.to_s,
      }
    end

    bottle_data
  end

  # Generate bottle filename for platform
  #
  # @param formula [Formula] Homebrew Formula object
  # @param platform [Symbol] Platform identifier (e.g., :arm64_sonoma)
  # @return [String] Bottle filename
  def self.bottle_filename(formula, platform)
    "#{formula.name}--#{formula.version}.#{platform}.bottle.tar.gz"
  end

  # Construct full bottle URL
  #
  # @param bottle_spec [BottleSpecification] Bottle specification object
  # @param filename [String] Bottle filename
  # @param checksum [Checksum] Checksum object
  # @return [String] Full bottle URL
  def self.construct_bottle_url(bottle_spec, filename, checksum)
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

  # Validate formula JSON against schema
  #
  # @param json_hash [Hash] Formula JSON data
  # @return [Boolean] True if valid, false otherwise
  def self.validate_formula_json(json_hash)
    required_fields = [
      :name,
      :full_name,
      :tap,
      :desc,
      :homepage,
      :versions,
      :urls,
      :revision,
      :version_scheme,
    ]

    # Check all required fields are present
    required_fields.all? { |field| json_hash.key?(field) }
  end
end
