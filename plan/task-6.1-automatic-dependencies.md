# Task 6.1: Automatic Dependency Mirroring

## Objective

Automatically resolve and mirror all dependencies when specific formulas are requested, eliminating the need for manual dependency tracking.

## Background

Currently, when users mirror specific formulas with `-f wget,jq,htop`, only those formulas are mirrored. Their dependencies (openssl, libidn2, etc.) are **not** included, causing installation failures on offline machines.

This is the **#1 usability issue** for selective mirroring scenarios.

## User Story

**As a user**, when I run:
```bash
brew offline mirror -d ~/mirror -f wget --with-deps
```

**I want** wget AND all its dependencies (recursive) to be automatically mirrored

**So that** I can install wget on offline machines without dependency errors.

## Prerequisites

- Understanding of Homebrew's Formula API
- Familiarity with `mirror/bin/brew-mirror`
- Knowledge of dependency resolution algorithms

## Design

### New Flag: `--with-deps`

Add a new command-line flag to enable automatic dependency resolution:

```bash
brew offline mirror -d ~/mirror -f wget,jq --with-deps
```

**Behavior:**
- Without `--with-deps`: Current behavior (mirror only specified formulas)
- With `--with-deps`: Resolve and mirror all dependencies automatically

**Why optional?**
- Backward compatibility
- Performance (dependency resolution takes time)
- User control (some may want minimal mirrors)

### Dependency Types

Homebrew has several dependency types:

1. **Runtime dependencies** (required, must mirror)
   - Example: wget depends on openssl@3
   - API: `Formula#deps`

2. **Build dependencies** (optional, only needed if building from source)
   - Example: wget depends on pkg-config (build-only)
   - API: `Formula#deps(include: :build)`

3. **Optional dependencies** (user choice, skip by default)
   - Example: emacs optional: imagemagick
   - API: `Formula#optional_dependencies`

4. **Recommended dependencies** (usually included)
   - API: `Formula#recommended_dependencies`

**Decision**: Mirror runtime + recommended dependencies by default. Add `--include-build` flag for build deps.

### Algorithm

```ruby
def resolve_dependencies(formula_names, options)
  resolved = Set.new
  queue = formula_names.dup

  while !queue.empty?
    name = queue.shift
    next if resolved.include?(name)

    begin
      formula = Formula[name]
      resolved.add(name)

      # Get runtime dependencies
      deps = formula.deps.reject(&:build?)

      # Add recommended dependencies
      deps += formula.deps.select(&:recommended?)

      # Add build dependencies if requested
      if options[:include_build]
        deps += formula.deps.select(&:build?)
      end

      # Add to queue for recursive resolution
      deps.each do |dep|
        queue << dep.name unless resolved.include?(dep.name)
      end

    rescue FormulaUnavailableError
      opoo "Formula not found: #{name}"
    end
  end

  resolved.to_a
end
```

### Cask Dependencies

Casks are simpler - they rarely have dependencies. But we should handle them:

```ruby
def resolve_cask_dependencies(cask_tokens, options)
  resolved = Set.new

  cask_tokens.each do |token|
    begin
      cask = Cask::Cask.load(token)
      resolved.add(token)

      # Some casks depend on formulas (e.g., Java casks need openjdk)
      cask.depends_on.formula.each do |formula_dep|
        # Recursively resolve formula dependencies
        if options[:with_deps]
          resolved.merge(resolve_dependencies([formula_dep], options))
        else
          resolved.add(formula_dep)
        end
      end

    rescue Cask::CaskUnavailableError
      opoo "Cask not found: #{token}"
    end
  end

  resolved.to_a
end
```

## Implementation Steps

### Step 1: Add CLI Option

Edit `mirror/bin/brew-mirror`:

**Add option to options hash:**
```ruby
options = {
  directory: nil,
  sleep: 0.5,
  config_only: false,
  formulae: nil,
  casks: nil,
  taps: ["core", "cask"],
  verify: false,
  update_mode: false,
  prune_old: false,
  with_deps: false,        # NEW
  include_build: false,    # NEW
}
```

**Add CLI flags:**
```ruby
parser.on "--with-deps", "automatically include all dependencies" do
  options[:with_deps] = true
end

parser.on "--include-build", "include build dependencies (requires --with-deps)" do
  options[:include_build] = true
end
```

### Step 2: Create Dependency Resolver Module

Create `mirror/lib/dependency_resolver.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "set"

# DependencyResolver: Resolve formula and cask dependencies
#
# This module resolves Homebrew formula dependencies recursively,
# building a complete dependency graph for mirroring.
#
# Usage:
#   resolver = DependencyResolver.new(include_build: false)
#   all_formulas = resolver.resolve_formulas(["wget", "jq"])
module DependencyResolver
  class << self
    # Resolve formula dependencies recursively
    #
    # @param formula_names [Array<String>] Initial formula names
    # @param include_build [Boolean] Include build dependencies
    # @param include_optional [Boolean] Include optional dependencies
    # @return [Array<String>] Complete list of formula names
    def resolve_formulas(formula_names, include_build: false, include_optional: false)
      resolved = Set.new
      queue = formula_names.dup

      ohai "Resolving dependencies for #{formula_names.count} formulas..."

      while !queue.empty?
        name = queue.shift
        next if resolved.include?(name)

        begin
          formula = Formula[name]
          resolved.add(name)

          # Get dependencies based on options
          deps = get_formula_deps(formula, include_build, include_optional)

          # Add to queue for recursive resolution
          deps.each do |dep_name|
            queue << dep_name unless resolved.include?(dep_name)
          end

        rescue FormulaUnavailableError => e
          opoo "Formula not found: #{name}"
        end
      end

      ohای "Resolved #{resolved.count} formulas (including dependencies)"

      # Show dependency tree if verbose
      if ENV["BREW_OFFLINE_DEBUG"]
        puts "Dependency resolution:"
        formula_names.each do |name|
          print_dependency_tree(name, include_build, include_optional)
        end
      end

      resolved.to_a.sort
    end

    # Resolve cask dependencies
    #
    # @param cask_tokens [Array<String>] Initial cask tokens
    # @param include_build [Boolean] Include build dependencies for formula deps
    # @return [Hash] Hash with :casks and :formulas arrays
    def resolve_casks(cask_tokens, include_build: false)
      resolved_casks = Set.new
      resolved_formulas = Set.new

      ohai "Resolving dependencies for #{cask_tokens.count} casks..."

      cask_tokens.each do |token|
        begin
          cask = Cask::Cask.load(token)
          resolved_casks.add(token)

          # Some casks depend on formulas
          if cask.depends_on
            # Formula dependencies
            if cask.depends_on.formula
              cask.depends_on.formula.each do |formula_dep|
                formula_deps = resolve_formulas([formula_dep], include_build: include_build)
                resolved_formulas.merge(formula_deps)
              end
            end

            # Cask dependencies (rare, but possible)
            if cask.depends_on.cask
              cask.depends_on.cask.each do |cask_dep|
                resolved_casks.add(cask_dep)
              end
            end
          end

        rescue Cask::CaskUnavailableError => e
          opoo "Cask not found: #{token}"
        end
      end

      ohai "Resolved #{resolved_casks.count} casks, #{resolved_formulas.count} formula dependencies"

      {
        casks: resolved_casks.to_a.sort,
        formulas: resolved_formulas.to_a.sort
      }
    end

    private

    # Get dependencies for a formula based on options
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

      # Recommended dependencies (always include)
      deps += formula.recommended_dependencies.map(&:name)

      deps.uniq
    end

    # Print dependency tree for debugging
    def print_dependency_tree(formula_name, include_build, include_optional, indent = 0)
      prefix = "  " * indent
      puts "#{prefix}#{formula_name}"

      begin
        formula = Formula[formula_name]
        deps = get_formula_deps(formula, include_build, include_optional)

        deps.each do |dep_name|
          print_dependency_tree(dep_name, include_build, include_optional, indent + 1)
        end
      rescue FormulaUnavailableError
        # Skip
      end
    end
  end
end
```

### Step 3: Integrate into brew-mirror

Edit `mirror/bin/brew-mirror`:

**Add require:**
```ruby
require_relative "../lib/dependency_resolver"
```

**Modify formula selection logic (around line 385):**

```ruby
# Determine which formulae to mirror
formulae_to_mirror = if options[:formulae]
  # User specified specific formulas
  formula_names = options[:formulae]

  # Resolve dependencies if requested
  if options[:with_deps]
    ohai "Dependency resolution enabled"
    formula_names = DependencyResolver.resolve_formulas(
      formula_names,
      include_build: options[:include_build]
    )
    ohai "Will mirror #{formula_names.count} formulas (including dependencies)"
  end

  # Filter to only formulas in configured taps
  Formula.each.select do |formula|
    formula_names.include?(formula.name) &&
      configured_taps.any? { |tap| tap[:full_name] == formula.tap&.name }
  end
else
  # Mirror all formulas from configured taps
  Formula.each.select do |formula|
    configured_taps.any? { |tap| tap[:full_name] == formula.tap&.name }
  end
end
```

**Modify cask selection logic (around line 570):**

```ruby
# Determine which casks to mirror
casks_to_mirror = if options[:casks]
  # User specified specific casks
  cask_tokens = options[:casks]

  # Resolve dependencies if requested
  if options[:with_deps]
    ohai "Dependency resolution enabled for casks"
    resolved = DependencyResolver.resolve_casks(
      cask_tokens,
      include_build: options[:include_build]
    )

    # Add formula dependencies to mirror list
    if resolved[:formulas].any?
      ohai "Found #{resolved[:formulas].count} formula dependencies for casks"
      # Add these formulas to the formula mirror list
      # (need to refactor to merge with formulae_to_mirror)
    end

    cask_tokens = resolved[:casks]
  end

  # Load casks
  CaskHelpers.load_casks(cask_tokens)
else
  # Mirror all casks from configured taps
  CaskHelpers.load_all_casks
end
```

### Step 4: Add Tests

Create `mirror/test/test_dependency_resolver.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/dependency_resolver"

class TestDependencyResolver < Minitest::Test
  def test_resolve_single_formula_with_deps
    # wget depends on several formulas
    result = DependencyResolver.resolve_formulas(["wget"])

    # Should include wget itself
    assert_includes result, "wget"

    # Should include known dependencies
    # Note: These might change, so test is somewhat fragile
    # Could mock Formula API for more stable tests
    assert result.count > 1, "Expected dependencies, got only wget"
  end

  def test_resolve_without_deps_returns_input
    # When not using --with-deps, just return input
    # (this test is for the CLI behavior, not the resolver)
    skip "Tested via integration tests"
  end

  def test_resolve_build_dependencies
    result = DependencyResolver.resolve_formulas(
      ["wget"],
      include_build: true
    )

    # Should have more formulas than runtime-only
    runtime_only = DependencyResolver.resolve_formulas(["wget"])
    assert result.count >= runtime_only.count
  end

  def test_handles_missing_formula
    # Should handle missing formulas gracefully
    result = DependencyResolver.resolve_formulas(["nonexistent-formula-xyz"])
    assert_equal [], result
  end

  def test_handles_circular_dependencies
    # Homebrew shouldn't have circular deps, but test gracefully handling
    # This is more of a robustness check
    result = DependencyResolver.resolve_formulas(["python@3.11"])
    assert result.count > 0
  end

  def test_deduplicates_dependencies
    # If two formulas share dependencies, shouldn't duplicate
    result = DependencyResolver.resolve_formulas(["wget", "curl"])

    # Both depend on openssl, should only appear once
    counts = result.group_by { |name| name }.transform_values(&:count)
    assert counts.values.all? { |count| count == 1 }
  end
end
```

Create integration test `mirror/test/integration/test_automatic_dependencies.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_runner"

class TestAutomaticDependencies < IntegrationTest
  def test_with_deps_mirrors_dependencies
    mirror_dir = create_temp_mirror

    # Mirror wget with dependencies
    run_mirror(
      directory: mirror_dir,
      formulae: ["wget"],
      with_deps: true,
      sleep: 0.1
    )

    # Check that dependencies were mirrored
    manifest = load_manifest(mirror_dir)
    formula_names = manifest[:formulae].map { |f| f[:name] }

    assert_includes formula_names, "wget"

    # wget depends on these (as of 2025)
    # Note: This test is fragile to Homebrew changes
    expected_deps = ["openssl@3", "libidn2", "libunistring"]
    expected_deps.each do |dep|
      assert_includes formula_names, dep,
        "Expected dependency #{dep} to be mirrored with wget"
    end
  end

  def test_without_deps_mirrors_only_specified
    mirror_dir = create_temp_mirror

    # Mirror wget WITHOUT dependencies
    run_mirror(
      directory: mirror_dir,
      formulae: ["wget"],
      with_deps: false,
      sleep: 0.1
    )

    # Check that only wget was mirrored
    manifest = load_manifest(mirror_dir)
    formula_names = manifest[:formulae].map { |f| f[:name] }

    assert_equal ["wget"], formula_names
  end

  def test_cask_with_formula_dependencies
    skip "Not all environments have casks with formula deps"

    # Some casks depend on formulas (e.g., java casks need openjdk)
    # This tests that formula deps of casks are resolved
  end

  def test_install_with_dependencies_works
    mirror_dir = create_temp_mirror

    # Mirror with deps
    run_mirror(
      directory: mirror_dir,
      formulae: ["jq"],  # jq has fewer deps, faster test
      with_deps: true,
      sleep: 0.1
    )

    # Serve and install
    with_mirror_server(mirror_dir) do |url|
      configure_client(url)

      # Should install successfully with all deps available
      result = run_install("jq")
      assert result[:success], "Installation should succeed with all deps"
    end
  end
end
```

### Step 5: Update Documentation

Update `mirror/README.md` to document the new feature:

```markdown
### Automatic Dependency Resolution

When mirroring specific packages, automatically include all dependencies:

```bash
# Mirror wget with all its dependencies
brew offline mirror -d ~/mirror -f wget --with-deps

# Mirror multiple packages with dependencies
brew offline mirror -d ~/mirror -f wget,jq,htop --with-deps

# Include build dependencies too (for building from source)
brew offline mirror -d ~/mirror -f wget --with-deps --include-build
```

**Why use `--with-deps`?**
- ✅ No manual dependency tracking
- ✅ Guaranteed working installations
- ✅ Smaller mirrors than mirroring everything
- ✅ Perfect for selective mirroring

**Dependency Types:**
- **Runtime dependencies**: Always included with `--with-deps`
- **Recommended dependencies**: Always included with `--with-deps`
- **Build dependencies**: Only with `--include-build`
- **Optional dependencies**: Never included (install manually if needed)

**Examples:**

```bash
# Minimal working mirror for wget
brew offline mirror -d ~/mirror -f wget --with-deps -s 1

# Developer environment with common tools
brew offline mirror -d ~/mirror \
  -f git,vim,tmux,jq,wget,curl \
  --with-deps -s 1

# Mirror for building from source
brew offline mirror -d ~/mirror \
  -f python@3.11 \
  --with-deps --include-build -s 1
```
```

Update `GETTING_STARTED.md` examples:

```markdown
### Mirror with Dependencies (Recommended)

The easiest way to mirror specific packages:

```bash
# Just add --with-deps to automatically include all dependencies
brew offline mirror \
  -d ~/mirror \
  -f wget,jq,htop \
  --casks firefox \
  --with-deps \
  -s 1
```

This ensures all dependencies are mirrored, so installations will work on offline machines.

**Without --with-deps:** Only wget, jq, and htop are mirrored (dependencies missing ❌)

**With --with-deps:** wget + openssl + libidn2 + libunistring + ... are all mirrored (works perfectly ✅)
```

### Step 6: Update Help Text

Update brew-mirror's help output:

```ruby
parser.banner = <<~BANNER
  Usage: brew offline mirror [options]

  Create an offline mirror of Homebrew packages.

  Options:
BANNER

# ... existing options ...

parser.on "--with-deps", "Automatically include all dependencies" do
  options[:with_deps] = true
end

parser.on "--include-build", "Include build dependencies (use with --with-deps)" do
  options[:include_build] = true
end
```

Update the examples in help:

```ruby
parser.on_tail "--help", "Show this help message" do
  puts parser
  puts
  puts "Examples:"
  puts "  # Mirror specific packages with dependencies (recommended)"
  puts "  brew offline mirror -d ~/mirror -f wget,jq --with-deps"
  puts
  puts "  # Mirror without dependencies (manual dependency management)"
  puts "  brew offline mirror -d ~/mirror -f wget,jq"
  puts
  puts "  # Include build dependencies for compiling from source"
  puts "  brew offline mirror -d ~/mirror -f python --with-deps --include-build"
  exit 0
end
```

## Testing

### Unit Tests

Run dependency resolver tests:
```bash
ruby mirror/test/test_dependency_resolver.rb
```

Expected output:
```
Run options: --seed 12345

# Running:

......

Finished in 2.45s
6 runs, 12 assertions, 0 failures, 0 errors, 0 skips
```

### Integration Tests

Run full workflow tests:
```bash
cd mirror/test
./run_integration_tests.sh dependencies
```

### Manual Testing

**Test 1: Mirror with dependencies**
```bash
# Create mirror with dependencies
brew offline mirror \
  -d /tmp/test-mirror \
  -f jq \
  --with-deps \
  --verify

# Check manifest
cat /tmp/test-mirror/manifest.json | jq '.formulae[].name'
# Should show: jq, oniguruma (jq's dependency)

# Try installation
# (serve mirror, configure client, install)
# Should work without errors
```

**Test 2: Compare sizes**
```bash
# Without deps
brew offline mirror -d /tmp/no-deps -f wget
du -sh /tmp/no-deps  # Small

# With deps
brew offline mirror -d /tmp/with-deps -f wget --with-deps
du -sh /tmp/with-deps  # Larger (includes deps)

# Compare
diff <(ls /tmp/no-deps) <(ls /tmp/with-deps)
```

**Test 3: Complex dependency tree**
```bash
# Python has many dependencies
brew offline mirror \
  -d /tmp/python-mirror \
  -f python@3.11 \
  --with-deps \
  --verify

# Check how many formulas were resolved
cat /tmp/python-mirror/manifest.json | jq '.formulae | length'
# Should be 20+ formulas
```

## Acceptance Criteria

- ✅ `--with-deps` flag resolves and mirrors all runtime dependencies recursively
- ✅ `--include-build` flag includes build dependencies
- ✅ Works for both formulas and casks
- ✅ Handles circular dependencies gracefully
- ✅ Deduplicates dependencies
- ✅ Backward compatible (without flag, behaves as before)
- ✅ Clear output showing dependency resolution
- ✅ Debug mode shows dependency tree
- ✅ Integration tests pass
- ✅ Documentation updated
- ✅ Help text updated

## Performance Considerations

### Dependency Resolution Speed

Dependency resolution is fast (< 1 second for most formulas):

```ruby
# Cache formula lookups
@formula_cache = {}

def get_formula(name)
  @formula_cache[name] ||= Formula[name]
end
```

### Progress Reporting

Show progress during resolution:

```ruby
ohai "Resolving dependencies..."
formula_names.each_with_index do |name, i|
  puts "  [#{i+1}/#{formula_names.count}] #{name}"
  resolve_deps(name)
end
ohai "Resolved #{total} formulas"
```

## Edge Cases

### Circular Dependencies

Homebrew shouldn't have circular deps, but handle gracefully:

```ruby
def resolve_dependencies(names, visited = Set.new)
  # visited tracks what we've seen to break cycles
  names.each do |name|
    next if visited.include?(name)
    visited.add(name)
    # ... resolve ...
  end
end
```

### Missing Dependencies

If a dependency doesn't exist (removed from Homebrew):

```ruby
begin
  formula = Formula[dep_name]
rescue FormulaUnavailableError
  opoo "Dependency not found: #{dep_name} (skipping)"
  next
end
```

### Optional Dependencies

Don't include by default, but add flag if needed:

```bash
brew offline mirror -f emacs --with-deps --include-optional
```

## Future Enhancements

### Phase 2: Intelligent Defaults

Auto-enable `--with-deps` when selective mirroring:

```ruby
if options[:formulae] && !options[:with_deps]
  opoo "Mirroring specific formulas without dependencies"
  puts "Tip: Use --with-deps to automatically include dependencies"
  puts "     brew offline mirror -f wget --with-deps"
end
```

### Phase 3: Dependency Visualization

Generate dependency graph visualization:

```bash
brew offline mirror -f wget --with-deps --show-graph
# Opens browser with interactive dependency graph
```

### Phase 4: Selective Dependency Pruning

Allow excluding specific dependencies:

```bash
brew offline mirror -f wget --with-deps --except openssl
# Mirrors wget deps but assumes openssl is already available
```

## Troubleshooting

### "Formula not found" during resolution

**Cause**: Formula doesn't exist or tap not installed

**Solution**:
```bash
brew update
brew tap homebrew/core
brew tap homebrew/cask
```

### Dependency resolution takes too long

**Cause**: Large dependency tree (e.g., Python, Node.js)

**Solution**: Add progress reporting and caching

### Build dependencies bloat mirror

**Cause**: `--include-build` adds many extra formulas

**Solution**: Only use when building from source is required

## Migration Notes

This is a new feature, no migration needed. Old commands continue to work as before.

**Before (still works):**
```bash
brew offline mirror -d ~/mirror -f wget
# Only mirrors wget
```

**After (new recommended way):**
```bash
brew offline mirror -d ~/mirror -f wget --with-deps
# Mirrors wget + dependencies
```

## References

- Homebrew Formula API: https://rubydoc.brew.sh/Formula
- Homebrew Dependency DSL: https://docs.brew.sh/Formula-Cookbook#dependencies
- Graph traversal algorithms: DFS for dependency resolution
- Similar tools: pip (requirements.txt), npm (package-lock.json)

## Summary

This feature transforms offlinebrew from "mirror everything or manually track deps" to "mirror exactly what you need, automatically."

**Impact:**
- 🚀 Much better UX for selective mirroring
- 📦 Smaller mirrors than "mirror everything" approach
- ✅ Guaranteed working installations
- 🎯 Main blocker for adoption is resolved

**Estimated Implementation Time:** 4-6 hours
- DependencyResolver module: 2 hours
- Integration into brew-mirror: 1 hour
- Tests: 2 hours
- Documentation: 1 hour
