#!/bin/bash

# Dependencies: fedora-install-required-packages.sh
# This script installs essential tools including stow via dnf

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

is_fedora || exit 0

# Install essential tools
for i in curl zsh stow vim tree tmux rsync python3-neovim; do
  echo_yellow "=== Installing $i"
  sudo dnf install -y $i
  echo_green "Installed $i"
done
