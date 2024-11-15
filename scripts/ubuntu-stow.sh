#!/bin/bash

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
