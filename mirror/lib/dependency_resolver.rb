#!/usr/bin/env ruby
# frozen_string_literal: true

require "set"

# DependencyResolver: Resolve formula and cask dependencies recursively
#
# This module resolves Homebrew formula dependencies recursively,
# building a complete dependency graph for mirroring.
#
# Usage:
#   require_relative 'dependency_resolver'
#
#   # Resolve formula dependencies
#   formulas = DependencyResolver.resolve_formulas(["wget", "jq"])
#   # => ["wget", "jq", "openssl@3", "libidn2", "oniguruma", ...]
#
#   # Resolve cask dependencies
#   result = DependencyResolver.resolve_casks(["firefox"])
#   # => {casks: ["firefox"], formulas: []}
#
# Features:
#   - Recursive dependency resolution using BFS
#   - Handles runtime, build, optional, and recommended dependencies
#   - Deduplication of shared dependencies
#   - Graceful handling of missing formulas
#   - Circular dependency detection
#   - Progress reporting
#   - Debug mode with dependency tree visualization
#
module DependencyResolver
  class << self
    # Resolve formula dependencies recursively
    #
    # @param formula_names [Array<String>] Initial formula names
    # @param include_build [Boolean] Include build dependencies
    # @param include_optional [Boolean] Include optional dependencies
    # @return [Array<String>] Complete list of formula names (deduplicated)
    #
    # @example Resolve wget with runtime dependencies
    #   DependencyResolver.resolve_formulas(["wget"])
    #   # => ["wget", "gettext", "libidn2", "libunistring", "openssl@3"]
    #
    # @example Resolve with build dependencies
    #   DependencyResolver.resolve_formulas(["wget"], include_build: true)
    #   # => ["wget", ..., "pkg-config", "autoconf", ...]
    #
    def resolve_formulas(formula_names, include_build: false, include_optional: false)
      return [] if formula_names.nil? || formula_names.empty?

      resolved = Set.new
      queue = formula_names.dup
      visited = Set.new  # Track visited to prevent infinite loops

      ohai "Resolving dependencies for #{formula_names.count} formula#{'e' if formula_names.count != 1}..."

      while !queue.empty?
        name = queue.shift

        # Skip if already visited (circular dependency protection)
        next if visited.include?(name)
        visited.add(name)

        begin
          formula = Formula[name]
          resolved.add(name)

          # Get dependencies based on options
          deps = get_formula_deps(formula, include_build, include_optional)

          # Add to queue for recursive resolution
          deps.each do |dep_name|
            queue << dep_name unless visited.include?(dep_name)
          end

        rescue FormulaUnavailableError => e
          opoo "Formula not found: #{name}"
          if ENV["BREW_OFFLINE_DEBUG"]
            puts "  Error: #{e.message}"
          end
        rescue StandardError => e
          opoo "Error resolving formula #{name}: #{e.message}"
          if ENV["BREW_OFFLINE_DEBUG"]
            puts "  Backtrace: #{e.backtrace[0..2].join("\n  ")}"
          end
        end
      end

      result = resolved.to_a.sort

      ohai "Resolved #{result.count} formula#{'e' if result.count != 1} (including dependencies)"

      # Show dependency tree if in debug mode
      if ENV["BREW_OFFLINE_DEBUG"]
        puts "\n==> Dependency Tree:"
        formula_names.each do |name|
          print_dependency_tree(name, 0, include_build, include_optional, visited)
        end
        puts ""
      end

      result
    end

    # Resolve cask dependencies
    #
    # @param cask_tokens [Array<String>] Initial cask tokens
    # @param include_build [Boolean] Include build dependencies for formula deps
    # @return [Hash] Hash with :casks and :formulas arrays
    #
    # @example Resolve cask with no dependencies
    #   DependencyResolver.resolve_casks(["firefox"])
    #   # => {casks: ["firefox"], formulas: []}
    #
    # @example Resolve cask that depends on formulas
    #   DependencyResolver.resolve_casks(["java"])
    #   # => {casks: ["java"], formulas: ["openjdk"]}
    #
    def resolve_casks(cask_tokens, include_build: false)
      return { casks: [], formulas: [] } if cask_tokens.nil? || cask_tokens.empty?

      resolved_casks = Set.new
      resolved_formulas = Set.new

      ohai "Resolving dependencies for #{cask_tokens.count} cask#{'s' if cask_tokens.count != 1}..."

      cask_tokens.each do |token|
        begin
          cask = Cask::CaskLoader.load(token)
          resolved_casks.add(token)

          # Some casks depend on formulas
          if cask.depends_on
            # Formula dependencies (Homebrew 5.0+)
            if cask.depends_on.formula
              Array(cask.depends_on.formula).each do |formula_dep|
                # Recursively resolve formula dependencies
                formula_deps = resolve_formulas([formula_dep.to_s], include_build: include_build)
                resolved_formulas.merge(formula_deps)
              end
            end

            # Cask dependencies (rare, but possible) (Homebrew 5.0+)
            if cask.depends_on.cask
              Array(cask.depends_on.cask).each do |cask_dep|
                resolved_casks.add(cask_dep.to_s)
              end
            end
          end

        rescue Cask::CaskUnavailableError => e
          opoo "Cask not found: #{token}"
          if ENV["BREW_OFFLINE_DEBUG"]
            puts "  Error: #{e.message}"
          end
        rescue StandardError => e
          opoo "Error resolving cask #{token}: #{e.message}"
          if ENV["BREW_OFFLINE_DEBUG"]
            puts "  Backtrace: #{e.backtrace[0..2].join("\n  ")}"
          end
        end
      end

      result = {
        casks: resolved_casks.to_a.sort,
        formulas: resolved_formulas.to_a.sort
      }

      if result[:formulas].any?
        ohai "Resolved #{result[:casks].count} cask#{'s' if result[:casks].count != 1}, " \
             "#{result[:formulas].count} formula dependencies"
      else
        ohai "Resolved #{result[:casks].count} cask#{'s' if result[:casks].count != 1} " \
             "(no formula dependencies)"
      end

      result
    end

    private

    # Get dependencies for a formula based on options
    #
    # @param formula [Formula] The formula to get dependencies for
    # @param include_build [Boolean] Include build dependencies
    # @param include_optional [Boolean] Include optional dependencies
    # @return [Array<String>] Array of dependency names
    #
    def get_formula_deps(formula, include_build, include_optional)
      deps = []

      # Runtime dependencies (always include)
      deps += formula.deps.reject(&:build?).map(&:name)

      # Build dependencies (optional)
      if include_build
        deps += formula.deps.select(&:build?).map(&:name)
      end

      # Optional dependencies (optional)
      if include_optional
        deps += formula.optional_dependencies.map(&:name)
      end

      deps.uniq
    end

    # Print dependency tree for debugging
    #
    # @param formula_name [String] Formula name to print tree for
    # @param indent [Integer] Current indentation level
    # @param include_build [Boolean] Include build dependencies
    # @param include_optional [Boolean] Include optional dependencies
    # @param visited [Set] Set of already visited formulas (prevents infinite recursion)
    #
    def print_dependency_tree(formula_name, indent, include_build, include_optional, visited)
      prefix = "  " * indent
      marker = indent.zero? ? "└──" : "├──"

      puts "#{prefix}#{marker} #{formula_name}"

      # Prevent infinite recursion
      return if indent > 10  # Safety limit
      return unless visited.include?(formula_name)

      begin
        formula = Formula[formula_name]
        deps = get_formula_deps(formula, include_build, include_optional)

        deps.each do |dep_name|
          # Only show first level of dependencies to avoid clutter
          if indent < 2 && visited.include?(dep_name)
            print_dependency_tree(dep_name, indent + 1, include_build, include_optional, visited)
          elsif indent < 2
            puts "#{"  " * (indent + 1)}├── #{dep_name} (not resolved)"
          end
        end
      rescue FormulaUnavailableError
        # Already logged during resolution
      end
    end
  end
end
