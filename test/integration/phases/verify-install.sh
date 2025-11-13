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

while IFS=, read -r type name version_cmd; do
  # Skip comments and empty lines
  [[ "$type" =~ ^# ]] && continue
  [[ -z "$type" ]] && continue
  [[ -z "$name" ]] && continue

  total_count=$((total_count + 1))

  info "[$total_count] Testing $type: $name"

  # Install package based on type
  if [[ "$type" == "cask" ]]; then
    install_cmd="eval \$(/opt/homebrew/bin/brew shellenv) && brew offline install --cask $name"
  else
    install_cmd="eval \$(/opt/homebrew/bin/brew shellenv) && brew offline install $name"
  fi

  # Execute install command
  if vm_exec "$install_cmd" 2>&1 | grep -q "Error:"; then
    error "  Failed to install $name"
    fail_count=$((fail_count + 1))
    echo ""
    continue
  fi

  ok "  Installed $name"

  # Verify version command works
  # Note: nginx -v writes to stderr, so redirect stderr to stdout
  verify_cmd="eval \$(/opt/homebrew/bin/brew shellenv) && $version_cmd"
  if vm_exec "$verify_cmd" >/dev/null 2>&1; then
    ok "  Verified: $version_cmd"
    success_count=$((success_count + 1))
  else
    error "  Version command failed: $version_cmd"
    fail_count=$((fail_count + 1))
  fi

  echo ""
done <<< "$package_list"

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
