# Tart End-to-End Integration Tests

Automated end-to-end tests for offlinebrew using Tart VM isolation to validate the complete workflow:

1. **Setup fresh VM** - Create macOS VM with Tart
2. **Install Homebrew** - Non-interactive Homebrew installation
3. **Install offlinebrew** - Copy local code and configure
4. **Create mirror** - Mirror test packages with dependencies
5. **Verify installation** - Install packages from mirror and verify

This ensures offlinebrew works end-to-end with a real Homebrew installation on a clean system.

## Prerequisites

- **Tart CLI**: Install via Homebrew
  ```bash
  brew install tart
  ```
  Or download from https://github.com/cirruslabs/tart

- **macOS host**: Apple Silicon or Intel Mac
  - Apple Silicon recommended for best performance
  - Tart only runs on macOS

- **Disk space**: ~50GB available
  - 20-40GB for macOS base image (cached after first download)
  - 1-2GB for package mirror
  - 10GB for VM storage
  - Use `df -h` to check available space

- **Network**: Required for initial setup
  - Homebrew installation
  - Base image pull (first run only)
  - Package downloads

- **Time**:
  - First run: 15-20 minutes (includes base image download)
  - Subsequent runs: 10-15 minutes

## Quick Start

Run full test suite:
```bash
make test
```

Clean up after tests:
```bash
make clean
```

That's it! The test suite will:
- Pull macOS Sonoma base image (first run only, cached thereafter)
- Create fresh VM with 4 CPU, 8GB RAM
- Install Homebrew non-interactively
- Copy local offlinebrew code to VM
- Create mirror with 5 test packages and dependencies
- Install and verify all packages from mirror
- Report success or failure

## Usage

### Run Full Test Suite

```bash
make test
```

Runs all phases sequentially:
1. `setup-vm.sh` - Create fresh Tart VM
2. `install-homebrew.sh` - Install Homebrew
3. `install-offlinebrew.sh` - Copy and configure offlinebrew
4. `create-mirror.sh` - Mirror test packages
5. `verify-install.sh` - Install and verify packages

**Duration**: 10-15 minutes (first run may take longer for image download)

**VM cleanup**: VM is deleted on success, preserved on failure for debugging

### Run Specific Phases

For faster iteration during development:

```bash
# Test mirror creation only (assumes VM setup complete)
make test-mirror

# Test installation only (assumes mirror exists)
make test-install
```

**Note**: These assume prior setup. Use `make test` for full isolated test.

### Clean Up

```bash
make clean
```

Deletes the test VM and frees ~30GB disk space. Safe to run multiple times.

### Show Help

```bash
make help
```

Displays all available commands and configuration options.

### Customize VM Configuration

Override defaults via environment variables:

```bash
# Use more CPU and memory
make test TART_CPUS=8 TART_MEMORY=16384

# Use custom VM name
make test TART_VM_NAME=my-test-vm
```

**Defaults**:
- `TART_VM_NAME=offlinebrew-test`
- `TART_CPUS=4`
- `TART_MEMORY=8192` (MB)
- `TART_IMAGE=ghcr.io/cirruslabs/macos-sonoma-vanilla:latest`

## Package Configuration

Test packages are defined in `config/test-packages.txt` in CSV format:

```
# Format: type,name,version_command
formula,wget,wget --version
formula,jq,jq --version
formula,nginx,nginx -v
cask,firefox,/Applications/Firefox.app/Contents/MacOS/firefox --version
cask,rectangle,defaults read /Applications/Rectangle.app/Contents/Info CFBundleShortVersionString
```

**Fields**:
- `type`: Either `formula` (CLI tool) or `cask` (GUI application)
- `name`: Package name as known to Homebrew
- `version_command`: Shell command to verify installation

**Adding Packages**:

To test additional packages, add lines to this file:

```bash
# Add a formula
formula,htop,htop --version

# Add a cask
cask,slack,/Applications/Slack.app/Contents/MacOS/Slack --version
```

**Notes**:
- Comments start with `#`
- Empty lines are ignored
- Mirror includes dependencies automatically via `--with-deps` flag
- Large casks (e.g., firefox ~200MB) increase mirror size and test duration

## Troubleshooting

### VM fails to start

**Symptom**: `tart run` errors or hangs

**Solutions**:
- Check disk space: `df -h` (need ~50GB free)
- Check Tart version: `tart --version` (need 2.0+)
- Try manual VM start: `tart run offlinebrew-test`
- Check for stale VMs: `tart list`
- Delete and retry: `make clean && make test`

### Homebrew install hangs

**Symptom**: Install phase doesn't complete after 5+ minutes

**Solutions**:
- Check network connectivity from host
- VM may need more time - wait up to 10 minutes for first boot
- Check if VM is running: `tart list`
- Connect to VM to inspect: `tart run offlinebrew-test`
- Check Homebrew install logs in VM

### Package mirror fails

**Symptom**: Mirror creation phase errors with "Tap not installed"

**Solutions**:
- Ensure bundled tap fix is applied (see commits: "Support bundled core/cask taps")
- Verify Homebrew version in VM: `brew --version` (must be 5.0+)
- Check packages exist: `brew search <package>`
- Verify network access from VM
- Try with fewer packages first

### Version command fails for package

**Symptom**: Package installs but version verification fails

**Solutions**:
- Check version command syntax in test-packages.txt
- Some commands write to stderr (e.g., nginx -v)
- Some commands require full path (casks)
- Test command manually in VM: `tart run offlinebrew-test`
- Check if application actually installed: `ls /Applications/`

### Tests fail but VM is running

**Symptom**: Test reports failure but VM still exists

**Expected behavior**: VM is intentionally left running on failure for debugging

**Inspection**:
```bash
# Connect to VM
tart run offlinebrew-test

# Inside VM, check state:
brew --version
brew offline --help
ls /tmp/brew_mirror
```

**Cleanup when done**:
```bash
make clean
```

### Disk space issues

**Symptom**: "No space left on device" errors

**Solutions**:
- Check space: `df -h`
- Clean up test VM: `make clean`
- Clear Tart image cache: `rm -rf ~/.tart/vms/cache/`
- Clear Homebrew cache: `brew cleanup`

### Network rate limiting

**Symptom**: "Too many requests" from GitHub/Homebrew

**Solutions**:
- Wait 15-30 minutes before retrying
- Use authentication token for higher limits
- Test with fewer packages

## Test Architecture

```
test/integration/
├── tart-e2e.sh           # Main orchestrator (runs all phases)
├── phases/               # Individual test phases
│   ├── setup-vm.sh       # Create fresh Tart VM
│   ├── install-homebrew.sh      # Install Homebrew
│   ├── install-offlinebrew.sh   # Copy and configure offlinebrew
│   ├── create-mirror.sh         # Mirror packages
│   └── verify-install.sh        # Install and verify packages
├── config/               # Test configuration
│   └── test-packages.txt # Package list
├── lib/                  # Shared utilities
│   └── test-helpers.sh   # Logging, assertions, VM communication
└── README.md             # This file
```

**Key Principles**:
- **Isolation**: Fresh VM for each full test run
- **Fail-fast**: Stops on first phase failure
- **Debugging**: VM preserved on failure
- **Cleanup**: VM deleted on success

**Phase Dependencies**:
1. setup-vm → 2. install-homebrew → 3. install-offlinebrew → 4. create-mirror → 5. verify-install

Each phase depends on successful completion of previous phases.

## Development

### Running Individual Phases

For development and debugging, run phases directly:

```bash
# From project root
bash test/integration/phases/setup-vm.sh
bash test/integration/phases/install-homebrew.sh
bash test/integration/phases/install-offlinebrew.sh
bash test/integration/phases/create-mirror.sh
bash test/integration/phases/verify-install.sh
```

**Note**: Later phases assume earlier phases completed successfully.

### Modifying Test Helpers

Shared utilities in `lib/test-helpers.sh`:
- `info()`, `ok()`, `warn()`, `error()` - Colored logging
- `vm_exec()` - Execute commands in VM
- `assert_*()` - Assertion helpers

Changes to helpers affect all phase scripts.

### Adding New Phases

To add a new test phase:

1. Create script in `phases/` directory
2. Source `test-helpers.sh` for utilities
3. Add to `phases` array in `tart-e2e.sh`
4. Update this README

## FAQ

**Q: Why does the first run take so long?**
A: First run downloads ~20-40GB macOS Sonoma base image. Subsequent runs use cached image.

**Q: Can I run tests in parallel?**
A: No, phases must run sequentially due to dependencies.

**Q: Can I use existing VM?**
A: Not with `make test` - it creates fresh VM. Use individual phase scripts for existing VM.

**Q: Why is VM deleted after tests?**
A: To save ~30GB disk space. VM is preserved on failure for debugging.

**Q: Can I test on Linux?**
A: No, Tart only runs on macOS. Consider using Docker for Linux testing.

**Q: How do I update base image?**
A: `tart pull ghcr.io/cirruslabs/macos-sonoma-vanilla:latest` - downloads latest version.
