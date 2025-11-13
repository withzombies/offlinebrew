#!/usr/bin/env bash
#
# tart-e2e.sh - End-to-end tests using Tart VM
#
# Orchestrates full test suite: VM setup, Homebrew install, mirror creation, package verification.

set -euo pipefail

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASES_DIR="$SCRIPT_DIR/phases"
VM_NAME="${TART_VM_NAME:-offlinebrew-test}"

# Source test helpers
source "$SCRIPT_DIR/lib/test-helpers.sh"

# Cleanup function runs on exit
cleanup() {
  local exit_code=$?

  echo ""

  if [[ $exit_code -eq 0 ]]; then
    info "Tests passed - cleaning up..."
    if tart delete "$VM_NAME" 2>/dev/null; then
      ok "VM deleted: $VM_NAME"
    else
      warn "Failed to delete VM (may not exist)"
    fi
  else
    warn "Tests failed - VM left running for debugging"
    warn "  VM name: $VM_NAME"
    warn "  Connect: tart run $VM_NAME"
    warn "  Delete:  tart delete $VM_NAME"
  fi

  return $exit_code
}

# Register cleanup trap
trap cleanup EXIT

# Record start time
start_time=$(date +%s)

echo ""
info "========================================"
info "Starting Tart End-to-End Tests"
info "========================================"
echo ""

# Define phases in execution order
phases=(
  "setup-vm.sh"
  "install-homebrew.sh"
  "install-offlinebrew.sh"
  "create-mirror.sh"
  "verify-install.sh"
)

current_phase=0
total_phases=${#phases[@]}

# Run each phase
for phase in "${phases[@]}"; do
  current_phase=$((current_phase + 1))

  echo ""
  info "========================================"
  info "Phase $current_phase/$total_phases: $phase"
  info "========================================"
  echo ""

  phase_start=$(date +%s)

  # Run phase script (fail-fast: set -e will exit on error)
  "$PHASES_DIR/$phase"

  phase_end=$(date +%s)
  phase_duration=$((phase_end - phase_start))

  echo ""
  ok "Phase complete: $phase (${phase_duration}s)"
done

# Calculate total duration
end_time=$(date +%s)
total_duration=$((end_time - start_time))
minutes=$((total_duration / 60))
seconds=$((total_duration % 60))

# Print summary
echo ""
info "========================================"
ok "All tests passed!"
info "Total phases: $total_phases"
info "Total duration: ${minutes}m ${seconds}s"
info "========================================"
echo ""

exit 0
