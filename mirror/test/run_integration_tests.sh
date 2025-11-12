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

# Check if webrick is available (required for Ruby 3.0+)
if ! ruby -e "require 'webrick'" 2>/dev/null; then
    echo "Installing webrick gem (required for Ruby 3.0+)..."
    gem install webrick --no-document
    echo "✓ webrick installed"
    echo ""
fi

# Parse arguments
TEST_SUITE="${1:-all}"

cd "$(dirname "$0")"

case "$TEST_SUITE" in
  full)
    echo "Running full workflow integration tests..."
    echo ""
    ruby -I../lib:. integration/test_full_workflow.rb -v
    ;;

  url)
    echo "Running URL shim integration tests..."
    echo ""
    ruby -I../lib:. integration/test_url_shims.rb -v
    ;;

  error)
    echo "Running error handling integration tests..."
    echo ""
    ruby -I../lib:. integration/test_error_handling.rb -v
    ;;

  download)
    echo "Running download strategy integration tests..."
    echo ""
    ruby -I../lib:. integration/test_download_strategies.rb -v
    ;;

  real-world)
    echo "Running real-world formulae integration tests..."
    echo "Note: Set RUN_SLOW_TESTS=1 for slow tests"
    echo ""
    ruby -I../lib:. integration/test_real_world_formulae.rb -v
    ;;

  all|*)
    echo "Running all integration tests..."
    echo "This will take several minutes (downloading bottles, running installs)"
    echo ""

    echo ""
    echo "=============================================="
    echo "[1/5] Full Workflow Tests"
    echo "=============================================="
    ruby -I../lib:. integration/test_full_workflow.rb -v

    echo ""
    echo "=============================================="
    echo "[2/5] URL Shim Tests"
    echo "=============================================="
    ruby -I../lib:. integration/test_url_shims.rb -v

    echo ""
    echo "=============================================="
    echo "[3/5] Error Handling Tests"
    echo "=============================================="
    ruby -I../lib:. integration/test_error_handling.rb -v

    echo ""
    echo "=============================================="
    echo "[4/5] Download Strategy Tests"
    echo "=============================================="
    ruby -I../lib:. integration/test_download_strategies.rb -v

    echo ""
    echo "=============================================="
    echo "[5/5] Real-World Formulae Tests"
    echo "=============================================="
    ruby -I../lib:. integration/test_real_world_formulae.rb -v
    ;;
esac

echo ""
echo "=============================================="
echo "Integration Test Suite: Complete"
echo "=============================================="
