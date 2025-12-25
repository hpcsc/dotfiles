#!/bin/bash


# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

is_macos || exit 0

packages=(
  Rectangle
  PathFinder
)

function stow_packages() {
  for i in "${packages[@]}"; do
    stow -vv \
         --dir=./link/macos/Applications \
         --target="$HOME" \
         --stow $i || echo_red "Failed to stow $i"
  done
}

stow_packages

exit 0
