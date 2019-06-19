#!/bin/bash

set -e

source ./load-zsh-autoload-as-functions.sh

function stow_packages() {
  stow -vv --dir='./link/macos/Applications/vscode/Library/Application Support' --target="$HOME/.config/Code" --stow Code || echo_red "Failed to stow vscode settings"
}

function install_extensions() {
  command -v code >/dev/null 2>&1 || {
      echo_yellow "VSCode executable is not in Path, exiting"
      exit 1
  }

  echo_green "=== Installing VSCode extensions"

  while read extension; do
      echo_yellow "=== Installing $extension"
      code --install-extension $extension
  done <./others/ubuntu/vscode/extensions
}

mkdir -p "$HOME/.config/Code"
stow_packages
install_extensions
