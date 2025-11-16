#!/usr/bin/env bash
#
# install-homebrew.sh - Install Homebrew in Tart VM
#
# Installs Homebrew non-interactively and configures PATH.

set -euo pipefail

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source test helpers
source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Configuration
VM_NAME="${TART_VM_NAME:-offlinebrew-test}"
HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

# Install Homebrew using official install script
info "Installing Homebrew in VM (this may take 2-5 minutes)..."
info "Install URL: $HOMEBREW_INSTALL_URL"

if vm_exec "NONINTERACTIVE=1 /bin/bash -c \"\$(curl -fsSL $HOMEBREW_INSTALL_URL)\""; then
  ok "Homebrew installation completed"
else
  error "Homebrew installation failed"
  error "Check network connection and VM logs"
  exit 1
fi

# Configure Homebrew PATH
info "Configuring Homebrew PATH..."

# Add shellenv to .zprofile for persistence
# Using heredoc for better readability than nested quote escaping
vm_exec 'cat >> ~/.zprofile <<'"'"'EOF'"'"'
eval "$(/opt/homebrew/bin/brew shellenv)"
EOF
' || {
  error "Failed to add Homebrew to PATH"
  exit 1
}

ok "Homebrew PATH configured"

# Verify Homebrew works
info "Verifying Homebrew installation..."

# Get Homebrew version
brew_version=$(vm_exec 'eval "$(/opt/homebrew/bin/brew shellenv)" && brew --version | head -1' 2>/dev/null)

if [[ -z "$brew_version" ]]; then
  error "Failed to get Homebrew version"
  error "Homebrew may not be installed correctly"
  exit 1
fi

ok "Homebrew installed successfully: $brew_version"

# Verify brew command works
if vm_exec 'eval "$(/opt/homebrew/bin/brew shellenv)" && command -v brew' >/dev/null 2>&1; then
  ok "brew command is available in PATH"
else
  error "brew command not found in PATH"
  exit 1
fi

# Skip tap installation for modern Homebrew (5.0+)
# homebrew/core and homebrew/cask are now bundled with Homebrew
info "Skipping tap installation (bundled in Homebrew 5.0+)..."
ok "Using bundled homebrew/core and homebrew/cask taps"

info "Homebrew installation complete and verified"
exit 0
