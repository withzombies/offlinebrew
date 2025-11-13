# Phase 6: Enhanced User Experience

**Status**: 📋 Planned
**Priority**: HIGH
**Estimated Time**: 6-8 hours

## Overview

Phase 6 focuses on improving the user experience by addressing the #1 pain point: manual dependency management for selective mirroring.

## Background

The 2025 update (Phases 0-5) successfully modernized offlinebrew with:
- ✅ Full cask support
- ✅ Multi-tap configuration
- ✅ Incremental updates
- ✅ Mirror verification
- ✅ Comprehensive documentation
- ✅ `brew offline` command interface

However, one critical usability issue remains:

**Problem**: When users mirror specific packages, dependencies are NOT included:
```bash
brew offline mirror -d ~/mirror -f wget
# Only mirrors wget, NOT its dependencies (openssl, libidn2, etc.)

brew offline install wget  # FAILS on offline machine ❌
# Error: wget depends on openssl@3, which is not installed
```

**Current Workarounds**:
1. Mirror everything (`--taps core`) - wastes space/time
2. Manually track dependencies with `brew deps` - tedious and error-prone
3. Trial-and-error on offline machine - frustrating

**User Impact**: This is the most common complaint and biggest barrier to adoption.

## Goals

Transform offlinebrew from "mirror everything or suffer" to "mirror exactly what you need, automatically."

### Primary Goal
Automatically resolve and mirror all dependencies for specified packages, making selective mirroring practical and reliable.

### Secondary Goals
- Maintain backward compatibility (opt-in feature)
- Keep performance fast (< 1 second for dependency resolution)
- Provide visibility into what's being mirrored
- Support both formulas and casks

## Tasks

### Task 6.1: Automatic Dependency Mirroring ⭐ HIGH PRIORITY

**Status**: 📋 Planned
**Estimated Time**: 4-6 hours
**File**: [task-6.1-automatic-dependencies.md](task-6.1-automatic-dependencies.md)

**Objective**: Add `--with-deps` flag to automatically resolve and mirror all dependencies.

**User Experience**:
```bash
# New recommended way
brew offline mirror -d ~/mirror -f wget --with-deps
# Automatically mirrors: wget, openssl@3, libidn2, libunistring, gettext

# Works perfectly on offline machine ✅
brew offline install wget
```

**Key Features**:
- `--with-deps` flag for automatic dependency resolution
- `--include-build` flag for build dependencies
- Recursive dependency resolution
- Deduplication
- Progress reporting
- Debug mode shows dependency tree

**Implementation**:
1. Create `DependencyResolver` module
2. Integrate into `brew-mirror`
3. Add unit and integration tests
4. Update documentation and help text

**Acceptance Criteria**:
- ✅ Resolves dependencies recursively
- ✅ Works for formulas and casks
- ✅ Handles edge cases gracefully
- ✅ Backward compatible
- ✅ Clear progress reporting
- ✅ All tests pass

### Task 6.2: Smart Defaults and Warnings (Optional Enhancement)

**Status**: 💡 Future Enhancement
**Estimated Time**: 1-2 hours

**Objective**: Warn users when mirroring without dependencies.

**Implementation**:
```ruby
if options[:formulae] && !options[:with_deps]
  opoo "⚠️  Mirroring specific formulas WITHOUT dependencies"
  puts "    Installations may fail on offline machines"
  puts "    Tip: Add --with-deps to include dependencies automatically"
  puts
end
```

### Task 6.3: Dependency Visualization (Future)

**Status**: 💡 Future Enhancement
**Estimated Time**: 3-4 hours

**Objective**: Generate interactive dependency graph visualization.

**Example**:
```bash
brew offline mirror -f wget --with-deps --show-graph
# Opens manifest.html with interactive dependency graph
```

**Benefits**:
- Visual understanding of dependencies
- Identify heavy dependencies
- Useful for documentation and debugging

## Success Metrics

### Before Phase 6
```bash
# User wants to mirror wget for offline use
brew deps wget  # Manually check dependencies
# Output: gettext, libidn2, libunistring, openssl@3

# Manually list all dependencies
brew offline mirror -d ~/mirror \
  -f wget,gettext,libidn2,libunistring,openssl@3

# Tedious! Easy to miss dependencies!
```

### After Phase 6
```bash
# Just add --with-deps!
brew offline mirror -d ~/mirror -f wget --with-deps

# Done! All dependencies automatically included ✅
```

**Metrics**:
- ⏱️ **Time saved**: 5-10 minutes per package (no manual dep tracking)
- 📦 **Mirror size**: Optimal (only what's needed, no bloat)
- ✅ **Success rate**: 100% (no missing dependencies)
- 😊 **User satisfaction**: High (most requested feature)

## Dependencies

### Prerequisites
- Phase 0-5 complete (all foundational work done)
- Understanding of Homebrew Formula API
- Familiarity with graph traversal (DFS for dependency resolution)

### Related Work
- Task 3.1: Multi-tap support (enables resolving deps from multiple taps)
- Task 4.2: Manifest generation (will show resolved dependencies)
- GETTING_STARTED.md (needs examples with --with-deps)

## Testing Strategy

### Unit Tests
- DependencyResolver module tests
- Edge case handling (missing formulas, circular deps)
- Deduplication logic

### Integration Tests
- Mirror with dependencies, verify all present
- Install from mirror with dependencies
- Compare with/without --with-deps

### Manual Testing
- Small package (jq: 1 dependency)
- Medium package (wget: ~5 dependencies)
- Large package (python: 20+ dependencies)
- Cask with formula dependencies

## Documentation Updates

### Files to Update

**README.md**:
```markdown
## Quick Start

### 1. Create a Mirror (on a machine with internet)

```bash
# Mirror specific packages WITH dependencies (recommended)
brew offline mirror \
  -d ~/brew-mirror \
  -f wget,jq,htop \
  --with-deps \
  --casks firefox,visual-studio-code \
  -s 1
```
```

**GETTING_STARTED.md**:
- Update all selective mirroring examples to use `--with-deps`
- Add FAQ: "Do dependencies get mirrored automatically?"
- Add troubleshooting: "What if a dependency is missing?"

**mirror/README.md**:
- New section: "Automatic Dependency Resolution"
- Examples with `--with-deps` and `--include-build`
- Explanation of dependency types

**CHANGELOG.md** (for v2.1.0):
```markdown
## [2.1.0] - TBD

### Added
- **Automatic dependency resolution** - `--with-deps` flag automatically includes all dependencies
- **Build dependency support** - `--include-build` flag for source builds
- Dependency resolution progress reporting
- Debug mode shows dependency tree

### Changed
- Recommended selective mirroring now uses `--with-deps`
```

## Timeline

**Estimated Total Time**: 6-8 hours

| Task | Hours | Notes |
|------|-------|-------|
| 6.1.1: Create DependencyResolver module | 2 | Core algorithm |
| 6.1.2: Integrate into brew-mirror | 1 | CLI and workflow |
| 6.1.3: Unit tests | 1 | DependencyResolver tests |
| 6.1.4: Integration tests | 1 | Full workflow tests |
| 6.1.5: Documentation | 1 | All docs + examples |
| 6.1.6: Manual testing & polish | 1-2 | Edge cases, UX |

**Completion Target**: 1-2 days of focused work

## Risks and Mitigations

### Risk 1: Homebrew API Changes
**Impact**: Medium
**Likelihood**: Low
**Mitigation**: Use stable Formula API methods, add version checks if needed

### Risk 2: Performance Issues with Large Dep Trees
**Impact**: Low
**Likelihood**: Low
**Mitigation**: Cache lookups, show progress, typically < 1s even for Python

### Risk 3: Circular Dependencies
**Impact**: Low
**Likelihood**: Very Low (Homebrew shouldn't have cycles)
**Mitigation**: Track visited nodes, handle gracefully with warning

### Risk 4: User Confusion About --with-deps
**Impact**: Low
**Likelihood**: Low
**Mitigation**: Clear documentation, good default behavior, helpful warnings

## Migration Path

**This is a NEW feature** - no migration required. All existing commands continue to work.

**Old behavior** (preserved):
```bash
brew offline mirror -d ~/mirror -f wget
# Only mirrors wget (no dependencies)
```

**New behavior** (opt-in):
```bash
brew offline mirror -d ~/mirror -f wget --with-deps
# Mirrors wget + all dependencies
```

**Recommended** for new users: Always use `--with-deps` for selective mirroring.

## Future Enhancements

After Task 6.1 is complete, consider:

### 6.2: Intelligent Warnings
Warn users when they might be missing dependencies:
```
⚠️  Warning: Mirroring 3 formulas without dependencies
   Use --with-deps to automatically include dependencies
```

### 6.3: Dependency Caching
Cache dependency resolution results:
```bash
# First time: resolves dependencies
brew offline mirror -f wget --with-deps

# Second time: uses cached results (instant)
brew offline mirror -f wget,jq --with-deps
```

### 6.4: Dependency Graph Visualization
Generate visual dependency graphs in manifest.html:
- Interactive D3.js visualization
- Shows dependency relationships
- Highlights heavy dependencies
- Useful for understanding mirror contents

### 6.5: Selective Dependency Exclusion
Allow excluding specific dependencies:
```bash
# Assume openssl is already available
brew offline mirror -f wget --with-deps --except openssl
```

### 6.6: Dependency Locking
Generate a lock file for reproducible mirrors:
```bash
brew offline mirror -f wget --with-deps --generate-lock
# Creates brew-mirror.lock with exact versions
```

## Success Criteria

Phase 6 is considered complete when:

- ✅ `--with-deps` flag is implemented and tested
- ✅ Documentation is updated with `--with-deps` examples
- ✅ All unit and integration tests pass
- ✅ Manual testing shows reliable dependency resolution
- ✅ User can mirror specific packages and install them offline successfully
- ✅ Performance is acceptable (< 1 second for most formulas)
- ✅ Edge cases are handled gracefully

## Impact Assessment

### User Impact: 🔥 VERY HIGH
- Eliminates #1 pain point
- Makes selective mirroring practical
- Saves time and reduces errors
- Most requested feature

### Code Impact: 📊 MEDIUM
- New module: `dependency_resolver.rb` (~200 lines)
- Modifications to `brew-mirror` (~50 lines)
- New tests (~200 lines)
- Documentation updates (~500 lines)
- Total: ~950 lines

### Maintenance Impact: 🟢 LOW
- Simple algorithm (DFS traversal)
- Uses stable Homebrew APIs
- Well-tested with edge cases covered
- Clear separation of concerns

## Conclusion

Phase 6 completes the offlinebrew modernization by solving the last major usability issue. After this phase:

- ✅ **Foundational work** (Phases 0-5): Complete
- ✅ **User experience** (Phase 6): Complete
- 🎯 **Production-ready**: Fully

Offlinebrew will be a **best-in-class** tool for offline Homebrew package management, with:
- Full feature parity with Homebrew
- Excellent user experience
- Comprehensive documentation
- Production-grade quality

**Next Steps**:
1. Review and approve this plan
2. Implement Task 6.1 (automatic dependencies)
3. Test thoroughly
4. Update documentation
5. Release v2.1.0 🎉
