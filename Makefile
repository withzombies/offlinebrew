# Offlinebrew Tart Integration Tests
#
# Makefile for running end-to-end tests using Tart VM

# Configuration
TART_VM_NAME := offlinebrew-test
TART_IMAGE := ghcr.io/cirruslabs/macos-sonoma-vanilla:latest
TART_CPUS := 4
TART_MEMORY := 8192

# Paths
TEST_SCRIPT := test/integration/tart-e2e.sh
PHASES_DIR := test/integration/phases

# Phony targets (not actual files)
.PHONY: help test test-mirror test-install clean

# Default target - show help
help:
	@echo "Offlinebrew Tart Integration Tests"
	@echo ""
	@echo "Usage:"
	@echo "  make test          - Run full end-to-end test suite (10-15 min)"
	@echo "  make test-mirror   - Run mirror creation test only"
	@echo "  make test-install  - Run installation verification only"
	@echo "  make clean         - Delete test VM and artifacts"
	@echo "  make help          - Show this help message"
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

# Run mirror creation test only (assumes VM already setup)
test-mirror:
	@echo "Running mirror creation test..."
	@echo "Note: Assumes VM is setup with Homebrew and offlinebrew installed"
	@export TART_VM_NAME=$(TART_VM_NAME) && bash $(PHASES_DIR)/create-mirror.sh

# Run installation verification test only (assumes mirror exists)
test-install:
	@echo "Running installation verification test..."
	@echo "Note: Assumes mirror already created"
	@export TART_VM_NAME=$(TART_VM_NAME) && bash $(PHASES_DIR)/verify-install.sh

# Clean up test VM and artifacts
clean:
	@echo "Cleaning up test environment..."
	@tart delete $(TART_VM_NAME) 2>/dev/null || echo "  VM not found (already clean)"
	@echo "Cleanup complete"
