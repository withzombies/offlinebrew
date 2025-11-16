#!/usr/bin/env bash
#
# verify-install.sh - Verify packages install from mirror
#
# Reads test-packages.txt and installs each package via brew offline install.

set -euo pipefail

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source test helpers
source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Configuration
VM_NAME="${TART_VM_NAME:-offlinebrew-test}"
TEST_CONFIG_FILE="/tmp/test-config/test-packages.txt"
MIRROR_DIR="/tmp/brew_mirror"

# Counters
success_count=0
fail_count=0
total_count=0

# Verify test config file exists in VM
info "Checking prerequisites..."

if ! vm_exec "test -f $TEST_CONFIG_FILE"; then
  error "Test config file not found in VM: $TEST_CONFIG_FILE"
  error "Run create-mirror.sh first to copy config file"
  exit 1
fi

if ! vm_exec "test -d $MIRROR_DIR"; then
  error "Mirror directory not found in VM: $MIRROR_DIR"
  error "Run create-mirror.sh first to create mirror"
  exit 1
fi

ok "Prerequisites verified"

# Install and verify each package
info "Installing and verifying packages..."
echo ""

# Read package list from VM and process locally
package_list=$(vm_exec "cat $TEST_CONFIG_FILE")

# IMPORTANT: File Descriptor 3 Workaround
# --------------------------------------
# Problem: vm_exec uses 'tart exec -i' which opens stdin for piping data to the VM.
#          When we use 'while read' normally, vm_exec inside the loop consumes ALL
#          remaining stdin lines, causing the loop to only process the first package.
#
# Solution: Read from file descriptor 3 instead of stdin (fd 0).
#          1. exec 3<<< "$package_list"  - Opens fd 3 with package list as input
#          2. read ... <&3                - Reads from fd 3, not stdin
#          3. vm_exec can now safely use stdin without stealing our loop input
#
# This pattern is necessary whenever you need to read line-by-line while calling
# commands that consume stdin (like tart exec -i, ssh, or other interactive tools).
exec 3<<< "$package_list"

while IFS=, read -r type name version_cmd <&3; do
  # Skip comments and empty lines
  [[ "$type" =~ ^# ]] && continue
  [[ -z "$type" ]] && continue
  [[ -z "$name" ]] && continue

  total_count=$((total_count + 1))

  info "[$total_count] Testing $type: $name"

  # Install package based on type
  # Use full path to brew-offline (works reliably in non-interactive shells)
  OFFLINEBREW_BIN="/tmp/offlinebrew/bin/brew-offline"
  if [[ "$type" == "cask" ]]; then
    install_cmd="eval \$(/opt/homebrew/bin/brew shellenv) && $OFFLINEBREW_BIN install --cask $name"
  else
    install_cmd="eval \$(/opt/homebrew/bin/brew shellenv) && $OFFLINEBREW_BIN install $name"
  fi

  # Execute install command
  install_output=$(vm_exec "$install_cmd" 2>&1) || true

  # Check for errors in output (disable exit-on-error for grep)
  set +e
  echo "$install_output" | grep -qE "(Error:|Fatal:)"
  has_error=$?
  set -e

  if [[ $has_error -eq 0 ]]; then
    error "  Failed to install $name"
    fail_count=$((fail_count + 1))
    echo ""
    continue
  fi

  ok "  Installed $name"

  # Verify version command works
  # Note: nginx -v writes to stderr, so redirect stderr to stdout
  verify_cmd="eval \$(/opt/homebrew/bin/brew shellenv) && $version_cmd"
  set +e  # Temporarily disable exit-on-error for version check
  vm_exec "$verify_cmd" >/dev/null 2>&1
  verify_exit=$?
  set -e  # Re-enable exit-on-error

  if [[ $verify_exit -eq 0 ]]; then
    ok "  Verified: $version_cmd"
    success_count=$((success_count + 1))
  else
    error "  Version command failed: $version_cmd"
    fail_count=$((fail_count + 1))
  fi

  echo ""
done

# Close file descriptor 3
exec 3<&-

# Print summary
echo ""
info "========================================="
info "Installation test results:"
info "  Total packages: $total_count"

if [[ $success_count -gt 0 ]]; then
  ok "  Successful: $success_count"
fi

if [[ $fail_count -gt 0 ]]; then
  error "  Failed: $fail_count"
fi

info "========================================="
echo ""

# Exit based on results
if [[ $fail_count -gt 0 ]]; then
  error "Some packages failed to install or verify"
  exit 1
fi

if [[ $total_count -eq 0 ]]; then
  warn "No packages found in config file"
  exit 1
fi

ok "All $success_count packages installed and verified successfully"
exit 0
