#!/usr/bin/env bash
#
# create-mirror.sh - Create offlinebrew mirror of test packages
#
# Reads test-packages.txt, creates mirror with brew offline mirror command.

set -euo pipefail

# Get directory of this script and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source test helpers
source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Configuration
VM_NAME="${TART_VM_NAME:-offlinebrew-test}"
MIRROR_DIR="/tmp/brew_mirror"
TEST_CONFIG_DIR="/tmp/test-config"
PACKAGES_FILE="$PROJECT_ROOT/test/integration/config/test-packages.txt"

# Verify packages file exists on host
if [[ ! -f "$PACKAGES_FILE" ]]; then
  error "Package file not found: $PACKAGES_FILE"
  exit 1
fi

info "Copying test-packages.txt to VM..."
info "Source: $PACKAGES_FILE"

# Create config directory in VM
vm_exec "mkdir -p $TEST_CONFIG_DIR" || {
  error "Failed to create config directory in VM"
  exit 1
}

# Copy config file to VM using tar stream
# This approach works with tart exec and preserves file permissions
config_dir="$PROJECT_ROOT/test/integration/config"
if tar -C "$config_dir" -cf - test-packages.txt | tart exec -i "$VM_NAME" bash -c "cd $TEST_CONFIG_DIR && tar -xf -"; then
  ok "Config file copied to VM"
else
  error "Failed to copy config file to VM"
  exit 1
fi

# Parse formulae from config file
info "Parsing package lists..."

formulae=$(vm_exec "grep '^formula,' $TEST_CONFIG_DIR/test-packages.txt | cut -d, -f2 | tr '\n' ','")
formulae=${formulae%,}  # Remove trailing comma

if [[ -z "$formulae" ]]; then
  warn "No formulae found in config file"
else
  info "Formulae to mirror: $formulae"
fi

# Parse casks from config file
casks=$(vm_exec "grep '^cask,' $TEST_CONFIG_DIR/test-packages.txt | cut -d, -f2 | tr '\n' ','")
casks=${casks%,}  # Remove trailing comma

if [[ -z "$casks" ]]; then
  warn "No casks found in config file"
else
  info "Casks to mirror: $casks"
fi

# Verify at least one package type specified
if [[ -z "$formulae" && -z "$casks" ]]; then
  error "No packages found in config file"
  exit 1
fi

# Create mirror directory in VM
info "Creating mirror directory..."
vm_exec "mkdir -p $MIRROR_DIR" || {
  error "Failed to create mirror directory"
  exit 1
}
ok "Mirror directory created: $MIRROR_DIR"

# Build brew offline mirror command using full path (PATH not yet updated in new shell session)
# Use full path to brew-offline script since ~/.zprofile hasn't been sourced yet
info "Creating mirror with dependencies (this may take 5-10 minutes)..."
OFFLINEBREW_BIN="/tmp/offlinebrew/bin/brew-offline"
mirror_cmd="eval \$(/opt/homebrew/bin/brew shellenv) && $OFFLINEBREW_BIN mirror -d $MIRROR_DIR"

# Add formulae if present
if [[ -n "$formulae" ]]; then
  mirror_cmd="$mirror_cmd -f $formulae"
fi

# Add casks if present
if [[ -n "$casks" ]]; then
  mirror_cmd="$mirror_cmd --casks $casks"
fi

# Add --with-deps flag to include dependencies
mirror_cmd="$mirror_cmd --with-deps"

info "Mirror command: brew offline mirror -d $MIRROR_DIR -f ... --casks ... --with-deps"

# Execute mirror command
if vm_exec "$mirror_cmd"; then
  ok "Mirror creation completed"
else
  error "Mirror creation failed"
  error "Check network connection and package names"
  exit 1
fi

# Verify mirror files exist
info "Verifying mirror structure..."

# Check config.json
if vm_exec "test -f $MIRROR_DIR/config.json"; then
  ok "config.json found"
else
  error "config.json not found in mirror"
  exit 1
fi

# Check urlmap.json
if vm_exec "test -f $MIRROR_DIR/urlmap.json"; then
  ok "urlmap.json found"
else
  error "urlmap.json not found in mirror"
  exit 1
fi

# Check that mirror contains resource files (.tar.gz, .pem, etc.)
resource_count=$(vm_exec "ls $MIRROR_DIR/*.{tar.gz,pem,bz2} 2>/dev/null | wc -l | tr -d ' '" || echo "0")
if [[ "$resource_count" -gt 0 ]]; then
  ok "Mirror contains $resource_count resource files"
else
  error "No resource files found in mirror"
  exit 1
fi

# Log mirror statistics
info "Gathering mirror statistics..."

mirror_size=$(vm_exec "du -sh $MIRROR_DIR 2>/dev/null | cut -f1" || echo "unknown")
package_count=$resource_count

ok "Mirror created successfully"
ok "  Location: $MIRROR_DIR"
ok "  Size: $mirror_size"
ok "  Files: $package_count"

# Show config.json tap information
info "Mirror tap information:"
vm_exec "cat $MIRROR_DIR/config.json 2>/dev/null | head -20" || warn "Could not read config.json"

info "Mirror creation complete and verified"
exit 0
