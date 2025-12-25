#!/bin/bash

# Dependencies: ubuntu-install-common-tools.sh (installs stow)
# This script stows Ubuntu application settings
# Note: stow is installed by ubuntu-install-common-tools.sh

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

is_ubuntu || exit 0

declare -A packages=(
  [copyq]="$HOME/.config/copyq"
  [vscode]="$HOME/.config/Code/User"
)

function stow_packages() {
  for package in "${!packages[@]}"; do
    mkdir -p "${packages[$package]}"
    stow -vv \
      --dir=./link/ubuntu \
      --target="${packages[$package]}" \
      --stow $package || echo_red "Failed to stow $package"
  done
}

stow_packages
