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

# Copy project root to VM using tar stream (works with tart exec)
# This preserves all file permissions and symlinks including the portable symlink fix
info "Copying files via tar stream (preserves symlinks)..."

# Create tar archive from project root and pipe to VM via tart exec with stdin
# This approach works with tart exec without needing to mount directories
vm_name="${TART_VM_NAME:-offlinebrew-test}"
if tar -C "$PROJECT_ROOT" -cf - . | tart exec -i "$vm_name" bash -c "cd $OFFLINE_BREW_DIR && tar -xf -"; then
  ok "Code copied to VM successfully (symlinks preserved)"
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

# Test brew offline command - need to use the full path first (PATH not updated yet in this session)
# since the ~/.zprofile modifications won't be loaded until next shell session
full_path_test="$OFFLINE_BREW_DIR/bin/brew-offline --help"
if vm_exec "$full_path_test" 2>&1 | grep -q "USAGE\|COMMANDS"; then
  ok "brew offline command works (verified via full path)"
else
  error "brew offline command not working"
  error "Check that offlinebrew is in PATH and Homebrew is available"
  error "Test command: $full_path_test"
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
