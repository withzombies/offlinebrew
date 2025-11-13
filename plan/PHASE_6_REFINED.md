# Phase 6: Automatic Dependency Resolution - Refined Plan

**Status**: 📋 Planned
**Priority**: ⭐ CRITICAL (blocks selective mirroring usability)
**Total Estimated Time**: 6-8 hours
**Owner**: TBD
**Reviewers**: TBD

---

## Executive Summary

Phase 6 solves the **#1 user pain point**: missing dependencies when mirroring specific packages. Currently, users must manually track all dependencies with `brew deps`, which is error-prone and frustrating.

**Impact**: Without this, selective mirroring is practically unusable.

**Solution**: Add `--with-deps` flag to automatically resolve and mirror all dependencies recursively.

---

## Problem Statement

### Current State (Broken UX)
```bash
# User mirrors wget
brew offline mirror -d ~/mirror -f wget

# Installation FAILS on offline machine
brew offline install wget
# Error: wget depends on openssl@3 which is not installed ❌
```

### Target State (Fixed UX)
```bash
# User mirrors wget with dependencies
brew offline mirror -d ~/mirror -f wget --with-deps
# Automatically includes: wget, openssl@3, libidn2, libunistring, gettext

# Installation SUCCEEDS on offline machine
brew offline install wget  # ✅
```

### Workarounds (All Bad)
1. **Mirror everything** - Wastes 50-100GB and hours of time
2. **Manual `brew deps`** - Tedious, error-prone, misses transitive deps
3. **Trial and error** - Discover missing deps on offline machine (too late!)

---

## Goals & Non-Goals

### Goals
- ✅ Automatically resolve runtime dependencies recursively
- ✅ Support both formulas and casks
- ✅ Maintain backward compatibility (opt-in with `--with-deps`)
- ✅ Performance < 1 second for typical formulas
- ✅ Clear progress reporting
- ✅ Handle edge cases gracefully

### Non-Goals
- ❌ Not solving bottle (pre-compiled binary) optimization (separate effort)
- ❌ Not implementing dependency locking (defer to Phase 7)
- ❌ Not changing default behavior (must opt-in with flag)

---

## Tasks Breakdown

### Task 6.1.1: Create DependencyResolver Module
**Priority**: ⭐ CRITICAL
**Estimated Time**: 2-3 hours
**Status**: 📋 Planned

**Objective**: Implement recursive dependency resolution algorithm.

**Implementation Checklist**:
1. Create `mirror/lib/dependency_resolver.rb` with module structure
2. Implement `resolve_formulas(names, options)` method
   - Use breadth-first search (BFS) for dependency traversal
   - Track visited nodes to prevent infinite loops
   - Handle FormulaUnavailableError gracefully
3. Implement `resolve_casks(tokens, options)` method
   - Handle cask → formula dependencies
   - Handle cask → cask dependencies (rare)
4. Implement `get_formula_deps(formula, options)` helper
   - Filter by dependency type (runtime, build, optional, recommended)
   - Return array of dependency names
5. Add progress reporting with ohai/puts
6. Add debug mode for dependency tree visualization

**Success Criteria** (Measurable):
- [ ] `DependencyResolver.resolve_formulas(["wget"])` returns array containing "wget" and ≥3 dependencies
- [ ] Resolution time < 500ms for wget (5 deps), < 1s for python (20+ deps)
- [ ] Handles circular dependency without infinite loop (tested with mock)
- [ ] Handles missing formula gracefully (logs warning, continues)
- [ ] Deduplicates correctly: `resolve_formulas(["wget", "curl"])` has zero duplicates
- [ ] Debug mode outputs tree with correct indentation (verified by test)

**Anti-Patterns** (Prohibited):
- ❌ NO `unwrap()` or `expect()` - Use proper error handling
- ❌ NO hardcoded formula names in logic - Use Formula API
- ❌ NO unbounded recursion - Track visited nodes
- ❌ NO silent failures - Log all warnings/errors
- ❌ NO TODO comments without GitHub issue number

**Edge Cases**:
1. **Missing formula**: Log warning, continue with other deps
2. **Circular dependency**: Track visited, detect cycle, break
3. **Empty input**: Return empty array
4. **Formula with no deps**: Return just the formula itself
5. **Large dep tree (100+ packages)**: Show progress every 10 items

**Code Structure**:
```ruby
module DependencyResolver
  class << self
    def resolve_formulas(formula_names, include_build: false, include_optional: false)
      # BFS implementation with visited tracking
    end

    def resolve_casks(cask_tokens, include_build: false)
      # Returns {casks: [], formulas: []}
    end

    private

    def get_formula_deps(formula, include_build, include_optional)
      # Return filtered dependency list
    end

    def print_dependency_tree(name, indent, include_build, include_optional)
      # Debug visualization
    end
  end
end
```

**Files Created**:
- `mirror/lib/dependency_resolver.rb` (~250 lines)

**Files Modified**:
- None (standalone module)

---

### Task 6.1.2: Add CLI Flags to brew-mirror
**Priority**: ⭐ CRITICAL
**Estimated Time**: 1 hour
**Status**: 📋 Planned
**Depends On**: Task 6.1.1

**Objective**: Add `--with-deps` and `--include-build` CLI options.

**Implementation Checklist**:
1. Add `with_deps: false` and `include_build: false` to options hash (line ~129)
2. Add `parser.on "--with-deps"` flag (after line ~169)
3. Add `parser.on "--include-build"` flag (after --with-deps)
4. Add validation: `--include-build` requires `--with-deps`
5. Update help text examples to show new flags
6. Add warning if `--include-build` without `--with-deps`

**Success Criteria** (Measurable):
- [ ] `brew offline mirror --help` shows both new flags
- [ ] `--with-deps` sets `options[:with_deps] = true`
- [ ] `--include-build` requires `--with-deps` (exits with error if not)
- [ ] Help examples include `--with-deps` usage
- [ ] Running with `--include-build` alone shows clear error message

**Anti-Patterns** (Prohibited):
- ❌ NO silent flag ignored - Validate and error if misused
- ❌ NO unclear help text - Examples must be copy-pasteable

**Edge Cases**:
1. **`--include-build` without `--with-deps`**: Error with helpful message
2. **Both flags together**: Works correctly
3. **No flags**: Default behavior unchanged

**Files Modified**:
- `mirror/bin/brew-mirror` (lines ~129, ~169-175, ~950-960 help text)

---

### Task 6.1.3: Integrate DependencyResolver into brew-mirror
**Priority**: ⭐ CRITICAL
**Estimated Time**: 2 hours
**Status**: 📋 Planned
**Depends On**: Task 6.1.1, Task 6.1.2

**Objective**: Use DependencyResolver to expand formula/cask lists before mirroring.

**Implementation Checklist**:
1. Add `require_relative "../lib/dependency_resolver"` at top of brew-mirror
2. Locate formula selection logic (around line 385)
3. Add dependency resolution block BEFORE formula iteration:
   ```ruby
   if options[:formulae] && options[:with_deps]
     ohai "Resolving dependencies for #{options[:formulae].count} formulas..."
     formula_names = DependencyResolver.resolve_formulas(
       options[:formulae],
       include_build: options[:include_build]
     )
     ohai "Will mirror #{formula_names.count} formulas (including dependencies)"
     options[:formulae] = formula_names  # Update with expanded list
   end
   ```
4. Locate cask selection logic (around line 570)
5. Add cask dependency resolution block:
   ```ruby
   if options[:casks] && options[:with_deps]
     ohai "Resolving cask dependencies..."
     resolved = DependencyResolver.resolve_casks(
       options[:casks],
       include_build: options[:include_build]
     )
     # Handle formula deps of casks - need to merge with formula list
     # Handle expanded cask list
   end
   ```
6. Handle merging cask formula dependencies with main formula list
7. Update manifest to note dependency resolution was used

**Success Criteria** (Measurable):
- [ ] `brew offline mirror -f wget --with-deps` mirrors ≥4 formulas (wget + deps)
- [ ] `manifest.json` lists all dependencies that were auto-resolved
- [ ] Progress output shows "Resolving dependencies..." and count
- [ ] Without `--with-deps`, behavior unchanged (only wget mirrored)
- [ ] Cask formula dependencies merged correctly (no duplicates)

**Anti-Patterns** (Prohibited):
- ❌ NO modifying original formula list - Create new expanded list
- ❌ NO losing user's original formula list - Log what was requested
- ❌ NO silent dependency addition - Always show what's being added

**Edge Cases**:
1. **Formula with no dependencies**: Just mirrors the formula
2. **Cask depends on formula**: Formula added to formula mirror list
3. **Two formulas share dependency**: Dependency listed once (deduplicated)
4. **Large dependency tree**: Show progress during resolution

**Files Modified**:
- `mirror/bin/brew-mirror` (lines ~17 require, ~385-400 formula deps, ~570-590 cask deps)

---

### Task 6.1.4: Add Unit Tests for DependencyResolver
**Priority**: 🔥 CRITICAL (must be done before integration testing)
**Estimated Time**: 1.5 hours
**Status**: 📋 Planned
**Depends On**: Task 6.1.1

**Objective**: Test DependencyResolver in isolation with real Homebrew formulas.

**Implementation Checklist**:
1. Create `mirror/test/test_dependency_resolver.rb`
2. Write test: `test_resolve_single_formula_returns_self_and_deps`
   - Resolve wget
   - Assert wget in result
   - Assert result.count > 1
3. Write test: `test_resolve_formula_without_deps`
   - Find a formula with no deps (or mock one)
   - Assert only formula in result
4. Write test: `test_deduplication_works`
   - Resolve wget and curl (both depend on openssl)
   - Assert openssl appears exactly once
5. Write test: `test_handles_missing_formula`
   - Resolve ["nonexistent-formula-12345"]
   - Assert empty result, no exception
6. Write test: `test_include_build_adds_more_deps`
   - Resolve wget without build deps
   - Resolve wget with build deps
   - Assert build version has >= runtime version
7. Write test: `test_circular_dependency_handled`
   - Mock circular dependency (a→b→c→a)
   - Assert finishes without infinite loop
   - Assert all three in result
8. Write test: `test_cask_resolution_includes_formula_deps`
   - Resolve cask with formula dependency
   - Assert formula in :formulas key

**Success Criteria** (Measurable):
- [ ] All 7+ tests pass on macOS with Homebrew installed
- [ ] Test runtime < 5 seconds total
- [ ] Code coverage ≥90% for DependencyResolver module
- [ ] Tests pass in CI/CD environment
- [ ] No test uses hardcoded formula versions (test structure, not specifics)

**Anti-Patterns** (Prohibited):
- ❌ NO tests that depend on specific formula versions (they change!)
- ❌ NO tests that require internet (mock if needed)
- ❌ NO tests without assertions
- ❌ NO tests that can fail intermittently

**Edge Cases Tested**:
1. Missing formula
2. Circular dependencies
3. Empty input
4. Formula with no deps
5. Shared dependencies (deduplication)
6. Build vs runtime dependencies

**Files Created**:
- `mirror/test/test_dependency_resolver.rb` (~200 lines, 7+ tests)

---

### Task 6.1.5: Add Integration Tests
**Priority**: 🔥 CRITICAL
**Estimated Time**: 1.5 hours
**Status**: 📋 Planned
**Depends On**: Task 6.1.3, Task 6.1.4

**Objective**: Test full workflow: mirror with deps → serve → install.

**Implementation Checklist**:
1. Create `mirror/test/integration/test_automatic_dependencies.rb`
2. Write test: `test_mirror_with_deps_includes_dependencies`
   - Mirror jq (small, fast) with --with-deps
   - Read manifest.json
   - Assert jq in manifest
   - Assert oniguruma (jq's dependency) in manifest
3. Write test: `test_mirror_without_deps_excludes_dependencies`
   - Mirror jq without --with-deps
   - Assert only jq in manifest (no oniguruma)
4. Write test: `test_install_with_deps_succeeds`
   - Mirror jq with --with-deps
   - Serve mirror with HTTP server
   - Configure client
   - Install jq
   - Assert installation succeeds
5. Write test: `test_install_without_deps_fails`
   - Mirror jq without --with-deps
   - Try to install
   - Assert installation fails with dependency error
6. Write test: `test_include_build_adds_build_dependencies`
   - Mirror formula with --with-deps --include-build
   - Assert build deps present in manifest

**Success Criteria** (Measurable):
- [ ] All 5+ integration tests pass
- [ ] Test with --with-deps actually installs successfully
- [ ] Test without --with-deps fails as expected
- [ ] Tests clean up temp directories
- [ ] Tests run in < 2 minutes total
- [ ] Tests added to `run_integration_tests.sh`

**Anti-Patterns** (Prohibited):
- ❌ NO tests that leave temp files/directories
- ❌ NO tests that require specific formulas being installed
- ❌ NO tests that can interfere with each other (use unique temp dirs)

**Edge Cases Tested**:
1. With vs without --with-deps flag
2. Build dependencies
3. Installation success/failure
4. Manifest correctness

**Files Created**:
- `mirror/test/integration/test_automatic_dependencies.rb` (~250 lines, 5+ tests)

**Files Modified**:
- `mirror/test/run_integration_tests.sh` (add new test suite)

---

### Task 6.1.6: Update Documentation
**Priority**: 🔥 CRITICAL (users can't use it without docs)
**Estimated Time**: 1 hour
**Status**: 📋 Planned
**Depends On**: Task 6.1.3

**Objective**: Document --with-deps in all user-facing documentation.

**Implementation Checklist**:
1. Update `README.md`:
   - Change Quick Start example to use --with-deps
   - Add note: "💡 Tip: Always use --with-deps for selective mirroring"
2. Update `GETTING_STARTED.md`:
   - Update all selective mirroring examples to use --with-deps
   - Add section: "Why --with-deps?"
   - Add FAQ: "Do I always need --with-deps?"
3. Update `mirror/README.md`:
   - Add new section: "Automatic Dependency Resolution"
   - Document --with-deps and --include-build flags
   - Show examples with different scenarios
4. Update `bin/brew-offline` help output:
   - Update examples to use --with-deps
5. Update `mirror/bin/brew-mirror` help text:
   - Add examples with --with-deps
6. Update `CHANGELOG.md`:
   - Add entry for v2.1.0 with --with-deps feature

**Success Criteria** (Measurable):
- [ ] All selective mirroring examples use --with-deps
- [ ] "Why" section explains the problem and solution
- [ ] Help text shows --with-deps in examples
- [ ] CHANGELOG has accurate feature description
- [ ] No old examples without --with-deps remain (except backward compat notes)

**Anti-Patterns** (Prohibited):
- ❌ NO examples without explanation
- ❌ NO inconsistent terminology (always "dependencies", not "deps" in docs)
- ❌ NO examples that don't work when copy-pasted

**Edge Cases Documented**:
1. When to use vs not use --with-deps
2. What --include-build does
3. Performance implications
4. Backward compatibility

**Files Modified**:
- `README.md` (Quick Start section)
- `GETTING_STARTED.md` (multiple sections)
- `mirror/README.md` (new section + examples)
- `bin/brew-offline` (help text)
- `mirror/bin/brew-mirror` (help text)
- `CHANGELOG.md` (v2.1.0 entry)

---

### Task 6.1.7: Remove Dead/Deprecated Code
**Priority**: 🟡 MEDIUM (cleanup, not blocking)
**Estimated Time**: 30 minutes
**Status**: 📋 Planned
**Depends On**: None (can be done in parallel)

**Objective**: Remove or archive legacy code that's no longer needed.

**Dead Code Identified**:
1. **`mirror/bin/brew-mirror-prune`** - Functionality moved to `brew-mirror --prune`
2. **`cache_based/` directory** - Legacy POC, superseded by mirror-based approach
3. **TODOs in code**:
   - `brew-offline-install:163` - Config from mirror (defer to Phase 7)
   - `brew-mirror:466` - Log unmirrorable resources (defer to Phase 7)

**Implementation Checklist**:
1. Remove `mirror/bin/brew-mirror-prune`:
   - Already deprecated by `brew-mirror --prune` (Task 4.3)
   - Update `bin/brew-offline` to remove prune command
   - Update documentation to remove references
2. Archive `cache_based/` directory:
   - Move to `archive/cache_based/`
   - Update README to note it's archived for historical reference
   - Remove from main documentation
3. Document TODOs as GitHub issues:
   - Create issue #X for config-from-mirror feature
   - Create issue #Y for unmirrorable resources logging
   - Update TODO comments to reference issues: `# TODO(#X): ...`
4. Remove any references to brew-mirror-prune from documentation

**Success Criteria** (Measurable):
- [ ] `brew-mirror-prune` file deleted
- [ ] `cache_based/` moved to `archive/`
- [ ] GitHub issues created for TODOs
- [ ] All TODO comments have issue numbers
- [ ] No broken documentation links
- [ ] `bin/brew-offline` prune command removed

**Anti-Patterns** (Prohibited):
- ❌ NO deleting without archiving (preserve history)
- ❌ NO TODOs without issue numbers
- ❌ NO removing features users might still use (check usage first)

**Edge Cases**:
1. Users still calling `brew offline prune`: Show deprecation warning
2. References in old documentation: Update or remove
3. Tests referencing dead code: Update or remove

**Files Deleted**:
- `mirror/bin/brew-mirror-prune`

**Files Moved**:
- `cache_based/` → `archive/cache_based/`

**Files Modified**:
- `bin/brew-offline` (remove prune command, add deprecation warning)
- `README.md` (update Architecture section)
- TODOs with issue numbers

---

## Dependencies Between Tasks

```
6.1.1 (DependencyResolver)
  ├─→ 6.1.2 (CLI flags) ─┐
  ├─→ 6.1.4 (Unit tests)  │
  └─→ 6.1.3 (Integration) ─→ 6.1.5 (Integration tests) ─→ 6.1.6 (Docs)

6.1.7 (Cleanup) ← can run in parallel with everything
```

**Critical Path**: 6.1.1 → 6.1.3 → 6.1.5 → 6.1.6 (5-6 hours)

---

## Testing Strategy

### Unit Tests
- **Location**: `mirror/test/test_dependency_resolver.rb`
- **Coverage**: ≥90% of DependencyResolver module
- **Runtime**: < 5 seconds
- **Run Command**: `ruby mirror/test/test_dependency_resolver.rb`

### Integration Tests
- **Location**: `mirror/test/integration/test_automatic_dependencies.rb`
- **Coverage**: Full workflow (mirror → serve → install)
- **Runtime**: < 2 minutes
- **Run Command**: `./mirror/test/run_integration_tests.sh dependencies`

### Manual Testing Checklist
- [ ] Mirror wget with --with-deps
- [ ] Verify dependencies in manifest.json
- [ ] Install wget on offline machine (should succeed)
- [ ] Mirror wget without --with-deps
- [ ] Try to install wget (should fail with dependency error)
- [ ] Test with large dependency tree (python@3.11)
- [ ] Test with cask that depends on formula
- [ ] Test --include-build flag

---

## Edge Cases & Failure Modes

### 1. Missing Formula During Resolution
**Scenario**: User requests formula that doesn't exist
**Handling**: Log warning, skip formula, continue with others
**Test**: Unit test with nonexistent formula

### 2. Circular Dependency
**Scenario**: a→b→c→a dependency cycle
**Handling**: Track visited nodes, detect cycle, include all once
**Test**: Unit test with mocked circular dependency

### 3. Empty Input
**Scenario**: No formulas specified
**Handling**: Return empty array, no error
**Test**: Unit test with empty array

### 4. Formula With No Dependencies
**Scenario**: Formula has zero dependencies
**Handling**: Return array with just that formula
**Test**: Unit test with standalone formula

### 5. Large Dependency Tree
**Scenario**: Python has 20+ dependencies
**Handling**: Show progress every 10 items, complete in < 1s
**Test**: Manual test with python@3.11

### 6. Network Failure During Mirror
**Scenario**: Network dies while mirroring dependencies
**Handling**: Existing error handling (not specific to this feature)
**Test**: Not tested (existing functionality)

### 7. Cask Depends on Formula
**Scenario**: Cask requires openjdk formula
**Handling**: Add formula to formula mirror list, deduplicate
**Test**: Integration test with Java cask

### 8. Unicode/Special Characters in Formula Names
**Scenario**: Formula name with special characters
**Handling**: Homebrew API handles this, pass through
**Test**: Not tested (Homebrew responsibility)

---

## Anti-Patterns (Prohibited)

### Code Anti-Patterns
- ❌ **NO `unwrap()` or `expect()`** - Use `Result` or proper error handling
- ❌ **NO unbounded recursion** - Always track visited nodes
- ❌ **NO silent failures** - Log warnings for all issues
- ❌ **NO TODOs without issue numbers** - Create issue, reference: `# TODO(#123): ...`
- ❌ **NO hardcoded formula names** - Use Homebrew API
- ❌ **NO mutable global state** - Pass options explicitly

### Testing Anti-Patterns
- ❌ **NO tests without assertions** - Every test must assert something
- ❌ **NO tests that can fail intermittently** - Must be deterministic
- ❌ **NO tests that depend on formula versions** - Test structure, not specifics
- ❌ **NO tests that don't clean up** - Always remove temp directories

### Documentation Anti-Patterns
- ❌ **NO examples that don't work** - Every example must be tested
- ❌ **NO vague language** - Be specific and measurable
- ❌ **NO inconsistent terminology** - Always "dependencies", not "deps"

---

## Performance Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Dependency resolution | < 500ms | wget (5 deps) |
| Large dependency tree | < 1s | python (20+ deps) |
| Unit test suite | < 5s | All tests |
| Integration test suite | < 2min | All tests |
| Memory usage | < 50MB | During resolution |

---

## Rollback Plan

If Phase 6 needs to be rolled back:

1. **Remove CLI flags**: Delete `--with-deps` and `--include-build` parsing
2. **Remove require**: Delete `require_relative dependency_resolver`
3. **Remove integration**: Delete dependency resolution blocks
4. **Keep tests**: Leave tests commented out for future use
5. **Update docs**: Remove all --with-deps references

**Rollback Time**: < 30 minutes
**Risk**: LOW (feature is opt-in, doesn't change default behavior)

---

## Success Criteria (Phase Complete)

Phase 6 is **DONE** when:

- [ ] All 7 tasks (6.1.1 through 6.1.7) marked complete
- [ ] All unit tests pass (≥7 tests, ≥90% coverage)
- [ ] All integration tests pass (≥5 tests)
- [ ] Manual testing checklist complete
- [ ] Documentation updated in all 6 files
- [ ] `brew offline mirror -f wget --with-deps` works end-to-end
- [ ] Installation from mirror succeeds on offline machine
- [ ] Performance targets met (< 1s for most formulas)
- [ ] Dead code removed or archived
- [ ] TODOs have issue numbers
- [ ] Code review approved
- [ ] Merged to main branch
- [ ] Released as v2.1.0

---

## Release Notes (v2.1.0)

**Feature**: Automatic Dependency Resolution

**What's New**:
- 🎯 **`--with-deps` flag** - Automatically mirrors all dependencies
- 🏗️ **`--include-build` flag** - Includes build dependencies for source builds
- 📊 **Progress reporting** - Shows dependency resolution progress
- 🐛 **Bug fix**: Removed dead `brew-mirror-prune` code
- 🗂️ **Cleanup**: Archived legacy `cache_based/` approach

**Migration Guide**:
```bash
# Old way (manual dependency tracking)
brew deps wget | xargs brew offline mirror -d ~/mirror -f wget,

# New way (automatic!)
brew offline mirror -d ~/mirror -f wget --with-deps
```

**Breaking Changes**: None (opt-in feature)

---

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Homebrew API changes | HIGH | LOW | Use stable API methods, add version checks |
| Performance issues | MEDIUM | LOW | Benchmark early, optimize if needed |
| Circular dependencies | LOW | VERY LOW | Track visited nodes |
| User confusion | MEDIUM | MEDIUM | Clear docs, good error messages |
| Edge case bugs | MEDIUM | MEDIUM | Comprehensive test coverage |

---

## Questions & Decisions

### Q: Should --with-deps be the default?
**A**: No. Opt-in for backward compatibility. Consider warning in Phase 7.

### Q: Should we support --without-deps to exclude specific deps?
**A**: Defer to Phase 7. YAGNI for MVP.

### Q: How deep should dependency resolution go?
**A**: Fully recursive. Stop only when no new deps found.

### Q: What about optional dependencies?
**A**: Skip by default. Add `--include-optional` flag if needed (Phase 7).

---

## Appendix A: Code Snippets

See `task-6.1-automatic-dependencies.md` for detailed code examples.

---

## Appendix B: Related Issues

- Issue #X: Fetch config from mirror (instead of local config)
- Issue #Y: Log unmirrorable resources (instead of aborting)
- Issue #Z: Dependency visualization in manifest.html

---

**End of Refined Phase 6 Plan**
