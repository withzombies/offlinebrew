#!/bin/bash
# Run integration tests for offlinebrew
#
# Requirements:
# - Homebrew installed
# - Network access (for mirroring)
# - ~5-10 minutes execution time

set -e

echo "=============================================="
echo "Offlinebrew Integration Test Suite"
echo "=============================================="
echo ""

# Check Homebrew is available
if ! command -v brew &> /dev/null; then
    echo "ERROR: Homebrew not found. Integration tests require Homebrew."
    echo "Install from: https://brew.sh"
    exit 1
fi

echo "✓ Homebrew found: $(brew --version | head -1)"
echo "✓ Homebrew prefix: $(brew --prefix)"
echo ""

# Check Ruby is available
if ! command -v ruby &> /dev/null; then
    echo "ERROR: Ruby not found"
    exit 1
fi

echo "✓ Ruby found: $(ruby --version)"
echo ""

# Run integration tests
echo "Running integration tests..."
echo "This will take several minutes (downloading bottles, running installs)"
echo ""

cd "$(dirname "$0")"

ruby -I../lib:. integration/test_full_workflow.rb -v

echo ""
echo "=============================================="
echo "Integration Test Suite: Complete"
echo "=============================================="
