#!/usr/bin/env bash
#
# setup-vm.sh - Set up fresh Tart VM for testing
#
# Creates a new macOS VM using Tart, configures resources, and waits for ready state.

set -euo pipefail

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source test helpers
source "$SCRIPT_DIR/../lib/test-helpers.sh"

# VM Configuration
VM_NAME="offlinebrew-test"
BASE_IMAGE="ghcr.io/cirruslabs/macos-sonoma-vanilla:latest"
VM_CPUS=4
VM_MEMORY=8192  # MB

# Check if Tart is installed
info "Checking for Tart CLI..."
if ! command -v tart &>/dev/null; then
  error "Tart CLI not found"
  error "Install from: https://github.com/cirruslabs/tart"
  error "  brew install tart"
  exit 1
fi
ok "Tart CLI found: $(tart --version 2>&1 | head -1)"

# Pull base image (will be cached if already downloaded)
info "Pulling base image: $BASE_IMAGE"
info "Note: First pull downloads ~20-40GB, subsequent pulls use cache"

if tart pull "$BASE_IMAGE"; then
  ok "Base image ready"
else
  error "Failed to pull base image"
  error "Check network connection and disk space (~50GB needed)"
  exit 1
fi

# Delete existing VM if present
if tart list 2>/dev/null | grep -q "^$VM_NAME"; then
  warn "Existing VM found: $VM_NAME"
  info "Deleting existing VM to start fresh..."
  if tart delete "$VM_NAME"; then
    ok "Existing VM deleted"
  else
    warn "Failed to delete existing VM (will try to continue)"
  fi
fi

# Clone fresh VM from base image
info "Cloning VM: $VM_NAME from $BASE_IMAGE"
if tart clone "$BASE_IMAGE" "$VM_NAME"; then
  ok "VM cloned successfully"
else
  error "Failed to clone VM"
  error "Check disk space (need ~30GB for VM)"
  exit 1
fi

# Configure VM resources
info "Configuring VM: $VM_CPUS CPU, $VM_MEMORY MB RAM"
if tart set "$VM_NAME" --cpu "$VM_CPUS" --memory "$VM_MEMORY"; then
  ok "VM resources configured"
else
  error "Failed to configure VM resources"
  exit 1
fi

# Start VM in background
info "Starting VM: $VM_NAME (this may take 1-2 minutes)"
tart run "$VM_NAME" --no-graphics &
VM_PID=$!
info "VM process started (PID: $VM_PID)"

# Give VM initial time to boot
sleep 10

# Wait for VM to be running (poll up to 120 seconds)
info "Waiting for VM to be ready..."
max_wait=120
elapsed=0
while [[ $elapsed -lt $max_wait ]]; do
  if tart list 2>/dev/null | grep -q "$VM_NAME.*running"; then
    ok "VM is running"
    break
  fi

  # Still waiting
  info "  Waiting for VM... ($elapsed/$max_wait seconds)"
  sleep 5
  elapsed=$((elapsed + 5))
done

# Check if VM started successfully
if [[ $elapsed -ge $max_wait ]]; then
  error "VM failed to start within $max_wait seconds"
  error "Check VM logs with: tart run $VM_NAME"
  exit 1
fi

# Final verification
info "Verifying VM status..."
if tart list | grep "$VM_NAME.*running"; then
  ok "VM setup complete: $VM_NAME"
  ok "VM is running and ready for testing"
  exit 0
else
  error "VM not found in running state after setup"
  error "VM status:"
  tart list | grep "$VM_NAME" || echo "  VM not found"
  exit 1
fi
