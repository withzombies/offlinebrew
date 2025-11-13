# Changelog

All notable changes to offlinebrew will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2025-11-13

Automatic dependency resolution - the most requested feature!

### Added
- **Automatic dependency resolution** with `--with-deps` flag - Recursively resolve and mirror all dependencies
- **Build dependency support** with `--include-build` flag - Include build dependencies for source compilation
- **DependencyResolver module** - Core dependency resolution engine with BFS traversal
- **Dependency progress reporting** - Shows how many dependencies were added during mirroring
- **Debug mode dependency tree** - Visualize dependency relationships with `BREW_OFFLINE_DEBUG=1`
- **Comprehensive dependency tests** - Unit and integration tests for dependency resolution
- **Cask dependency resolution** - Automatically resolve formula dependencies for casks

### Changed
- **Documentation updates** - All examples now use `--with-deps` for selective mirroring
- **Recommended workflow** - `--with-deps` is now the recommended approach for mirroring specific packages
- **Better error messages** - Validation ensures `--include-build` requires `--with-deps`

### Fixed
- **Missing dependencies** - Packages now install successfully offline when mirrored with `--with-deps`
- **Manual dependency tracking** - No longer needed, automatic resolution handles it

## [2.0.0] - 2025-11-13

Major modernization release adding cask support, multi-tap configuration, and comprehensive tooling.

### Added
- **Full cask support** - Mirror and install GUI applications, fonts, drivers, and other cask packages
- **Multi-tap configuration** with `--taps` option - Support for any Homebrew tap
- **Tap name shortcuts** - Use `core`, `cask`, `fonts` instead of full tap names
- **Incremental mirror updates** with `--update` flag - Skip unchanged packages (10-100x faster)
- **Mirror verification tool** (`brew-mirror-verify`) - Validate mirror integrity
- **Manifest generation** - JSON and beautiful HTML reports of mirror contents
- **Deterministic Git identifiers** - Prevent duplicate repository downloads
- **Apple Silicon support** - Native support for M1/M2/M3 Macs
- **Cross-platform home directory detection** - Works on all macOS configurations
- **URL normalization** - Better cask URL matching with query parameters
- **Comprehensive test suite** - Unit and integration tests for all functionality
- **Download retry logic** - Exponential backoff for network failures
- **Container format verification** - Validate DMG, PKG, ZIP files
- **Progress tracking** - Better feedback for large downloads
- **--prune option** - Report removed/updated packages during incremental updates
- **SafeShell module** - Secure command execution with timeout protection
- **MacOSSecurity module** - Code signature and checksum verification
- **TapManager module** - Simplified tap name handling

### Changed
- **Config format** - Now uses `taps` hash for multi-tap support (backward compatible with v1.x)
- **Improved error messages** - More helpful validation and debugging output
- **Better download failure handling** - Retry logic and clearer error reporting
- **Enhanced debugging** - `BREW_OFFLINE_DEBUG` environment variable for detailed logs
- **Dynamic path detection** - Automatically detects Homebrew location (Intel vs Apple Silicon)
- **Modernized Homebrew API** - Compatible with latest Homebrew changes
- **Test infrastructure** - Moved to proper integration testing framework

### Fixed
- **Git UUID collision** - Using deterministic identifiers prevents duplicate repos
- **Hardcoded `/usr/local/Homebrew` paths** - Now dynamically detected
- **Hardcoded `/Users` home directory** - Works with all user configurations
- **URL matching for casks** - Properly handles query parameters and fragments
- **Homebrew API compatibility** - Works with modern Homebrew versions
- **Cask::URL.downloader removal** - Adapted to current Cask API
- **HOMEBREW_EVAL_ALL requirement** - Properly set for cask operations
- **SafeShell.execute return type** - Returns String, not Hash

### Deprecated
- Old config format (still supported, but `taps` format recommended)
- `brew-mirror-prune` - Superseded by `brew-mirror --prune` flag
- `cache_based/` directory - Legacy proof-of-concept, replaced by mirror-based approach

### Removed
- `brew-mirror-prune` tool (functionality moved to `brew-mirror --prune`)
- `cache_based/` directory (legacy approach, mirror-based is production solution)

## [1.0.0] - 2020-03-01

Initial release with basic formula mirroring functionality.

### Added
- **Formula mirroring** from homebrew-core tap
- **Cache-based approach** using `HOMEBREW_CACHE`
- **Basic offline installation** for formulas
- **URL rewriting** via curl and git shims
- **brew-mirror** tool for creating mirrors
- **brew-offline-install** tool for installations
- **brew-mirror-prune** tool for cleanup

### Known Limitations (v1.0)
- Formula-only support (no casks)
- Single tap only (homebrew-core)
- Hardcoded paths for Intel Macs
- No verification tools
- No incremental updates
- Manual cleanup required

## Migration Notes

### From v1.x to v2.0

**Good News:** Old mirrors work with new tools! The new code is backward compatible.

See [MIGRATION.md](MIGRATION.md) for detailed upgrade instructions.

**Quick Summary:**
- Old configs still work (auto-upgraded)
- Old mirrors work (but won't have casks)
- Use `--update` to add casks to existing mirrors
- All old CLI options still work

[2.0.0]: https://github.com/withzombies/offlinebrew/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/withzombies/offlinebrew/releases/tag/v1.0.0
