# Offlinebrew Tart Integration Tests
#
# Makefile for running end-to-end tests using Tart VM

# Configuration
TART_VM_NAME := offlinebrew-test
# Note: TART_IMAGE not used - setup-vm.sh hardcodes the base image
# (base image has Tart Guest Agent pre-installed, vanilla does not)
TART_IMAGE := ghcr.io/cirruslabs/macos-sonoma-base:latest
TART_CPUS := 4
TART_MEMORY := 8192

# Paths
TEST_SCRIPT := test/integration/tart-e2e.sh
PHASES_DIR := test/integration/phases

# Phony targets (not actual files)
.PHONY: help test test-all test-setup-vm test-install-homebrew test-install-offlinebrew \
        test-create-mirror test-verify-install clean

# Default target - show help
help:
	@echo "Offlinebrew Tart Integration Tests"
	@echo ""
	@echo "Usage:"
	@echo "  make test                    - Run full end-to-end test suite (10-15 min)"
	@echo "  make test-all                - Same as 'make test'"
	@echo ""
	@echo "Individual phases (run in order):"
	@echo "  make test-setup-vm           - Create and start Tart VM"
	@echo "  make test-install-homebrew   - Install Homebrew in VM"
	@echo "  make test-install-offlinebrew - Install offlinebrew in VM"
	@echo "  make test-create-mirror      - Mirror packages (formulae, bottles, casks)"
	@echo "  make test-verify-install     - Install packages from mirror and verify"
	@echo ""
	@echo "Other commands:"
	@echo "  make clean                   - Delete test VM and artifacts"
	@echo "  make help                    - Show this help message"
	@echo ""
	@echo "Requirements:"
	@echo "  - Tart CLI installed (brew install tart)"
	@echo "  - ~50GB disk space for VM and mirror"
	@echo "  - macOS host (Apple Silicon or Intel)"
	@echo ""
	@echo "Environment variables:"
	@echo "  TART_VM_NAME       - VM name (default: $(TART_VM_NAME))"
	@echo "  TART_CPUS          - CPU count (default: $(TART_CPUS))"
	@echo "  TART_MEMORY        - Memory in MB (default: $(TART_MEMORY))"

# Run full end-to-end test suite
test:
	@echo "========================================"
	@echo "Starting Tart End-to-End Test Suite"
	@echo "========================================"
	@echo ""
	@echo "Configuration:"
	@echo "  VM Name: $(TART_VM_NAME)"
	@echo "  CPUs: $(TART_CPUS)"
	@echo "  Memory: $(TART_MEMORY)MB"
	@echo "  Image: $(TART_IMAGE)"
	@echo ""
	@export TART_VM_NAME=$(TART_VM_NAME) && bash $(TEST_SCRIPT)

# Alias for test
test-all: test

# Individual test phases (run in order for manual testing)

# Phase 1: Setup VM
test-setup-vm:
	@echo "========================================"
	@echo "Phase 1: Setup VM"
	@echo "========================================"
	@export TART_VM_NAME=$(TART_VM_NAME) && bash $(PHASES_DIR)/setup-vm.sh

# Phase 2: Install Homebrew
test-install-homebrew:
	@echo "========================================"
	@echo "Phase 2: Install Homebrew"
	@echo "========================================"
	@echo "Note: Assumes VM is running (use 'make test-setup-vm' first)"
	@export TART_VM_NAME=$(TART_VM_NAME) && bash $(PHASES_DIR)/install-homebrew.sh

# Phase 3: Install offlinebrew
test-install-offlinebrew:
	@echo "========================================"
	@echo "Phase 3: Install offlinebrew"
	@echo "========================================"
	@echo "Note: Assumes Homebrew is installed (use 'make test-install-homebrew' first)"
	@export TART_VM_NAME=$(TART_VM_NAME) && bash $(PHASES_DIR)/install-offlinebrew.sh

# Phase 4: Create mirror (formulae, bottles, casks with dependencies)
test-create-mirror:
	@echo "========================================"
	@echo "Phase 4: Create Mirror"
	@echo "========================================"
	@echo "Note: Assumes offlinebrew is installed (use 'make test-install-offlinebrew' first)"
	@export TART_VM_NAME=$(TART_VM_NAME) && bash $(PHASES_DIR)/create-mirror.sh

# Phase 5: Verify installation from mirror
test-verify-install:
	@echo "========================================"
	@echo "Phase 5: Verify Install"
	@echo "========================================"
	@echo "Note: Assumes mirror is created (use 'make test-create-mirror' first)"
	@export TART_VM_NAME=$(TART_VM_NAME) && bash $(PHASES_DIR)/verify-install.sh

# Clean up test VM and artifacts
clean:
	@echo "Cleaning up test environment..."
	@echo "Killing stale processes..."
	@ps aux | grep "[t]art run $(TART_VM_NAME)" | awk '{print $$2}' | xargs kill -9 2>/dev/null || echo "  No stale processes found"
	@ps aux | grep "[t]art exec.*$(TART_VM_NAME)" | awk '{print $$2}' | xargs kill -9 2>/dev/null || true
	@echo "Deleting VM..."
	@tart delete $(TART_VM_NAME) 2>/dev/null || echo "  VM not found (already clean)"
	@echo "Cleanup complete"
