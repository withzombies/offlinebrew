#!/usr/bin/env bash
#
# install-offlinebrew.sh - Install offlinebrew in Tart VM
#
# Copies local offlinebrew code to VM and configures PATH.

set -euo pipefail

# Get directory of this script and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source test helpers
source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Configuration
VM_NAME="${TART_VM_NAME:-offlinebrew-test}"
OFFLINE_BREW_DIR="/tmp/offlinebrew"

# Copy offlinebrew code to VM
info "Copying offlinebrew code to VM..."
info "Project root: $PROJECT_ROOT"
info "Destination in VM: $OFFLINE_BREW_DIR"

# Create destination directory in VM
vm_exec "mkdir -p $OFFLINE_BREW_DIR" || {
  error "Failed to create directory in VM"
  exit 1
}

# Mount project root and copy to VM
# Use tart run --dir to mount host directory as read-only
# Then copy to writable location in VM
info "Mounting and copying files (this may take a moment)..."
if tart run "$VM_NAME" --dir=offlinebrew:"$PROJECT_ROOT" -- \
  bash -c "cp -r /Volumes/offlinebrew/* $OFFLINE_BREW_DIR/"; then
  ok "Code copied to VM successfully"
else
  error "Failed to copy code to VM"
  exit 1
fi

# Add offlinebrew/bin to PATH
info "Configuring offlinebrew PATH..."

# Add to .zprofile for persistence
vm_exec "echo 'export PATH=\"$OFFLINE_BREW_DIR/bin:\$PATH\"' >> ~/.zprofile" || {
  error "Failed to add offlinebrew to PATH"
  exit 1
}

ok "offlinebrew PATH configured"

# Verify brew offline command works
info "Verifying offlinebrew installation..."

# Test brew offline command (needs Homebrew shellenv)
if vm_exec 'eval "$(/opt/homebrew/bin/brew shellenv)" && brew offline --help' | grep -q "brew offline"; then
  ok "brew offline command works"
else
  error "brew offline command not working"
  error "Check that offlinebrew is in PATH and Homebrew is available"
  exit 1
fi

# Verify bin directory exists
if vm_exec "test -d $OFFLINE_BREW_DIR/bin"; then
  ok "offlinebrew bin directory confirmed"
else
  error "offlinebrew bin directory not found"
  exit 1
fi

info "offlinebrew installation complete and verified"
exit 0
