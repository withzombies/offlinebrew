#!/usr/bin/env bash
#
# test-helpers.sh: Shared utilities for Tart integration tests
#
# This file provides logging, assertion, and VM communication helpers
# for offlinebrew end-to-end tests running in Tart VMs.
#
# Usage: source test/integration/lib/test-helpers.sh

set -euo pipefail

# Color codes using ANSI-C quoting
BLUE=$'\033[0;34m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
NC=$'\033[0m'  # No Color

# Logging functions
info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

ok() {
  echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Assertion helpers
assert_command_exists() {
  local cmd="$1"
  if command -v "$cmd" &>/dev/null; then
    return 0
  else
    error "Command not found: $cmd"
    return 1
  fi
}

assert_file_exists() {
  local file="$1"
  if [[ -f "$file" ]]; then
    return 0
  else
    error "File not found: $file"
    return 1
  fi
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  if [[ "$actual" -eq "$expected" ]]; then
    return 0
  else
    error "Expected exit code $expected, got $actual"
    return 1
  fi
}

# VM communication helpers
vm_exec() {
  local vm_name="${TART_VM_NAME:-offlinebrew-test}"
  tart run "$vm_name" -- bash -c "$*"
}

vm_copy() {
  local vm_name="${TART_VM_NAME:-offlinebrew-test}"
  local src="$1"
  local dest="$2"

  warn "vm_copy is not fully implemented"
  warn "Tart uses --dir for mounting, not traditional copy"
  warn "Use: tart run $vm_name --dir=name:$src"
  warn "Then access at /Volumes/name in VM"
  return 1
}
