#!/bin/bash

set -e

source ~/.functions/misc

function stow_packages() {
  stow -vv --dir=./link/macos/Applications --target="$HOME" --stow vscode || echo_red "Failed to stow vscode settings"
}

function install_extensions() {
  command -v code >/dev/null 2>&1 || {
      echo_yellow "VSCode executable is not in Path, creating symlink from /usr/local/bin/code -> /Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
      sudo ln -s "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" /usr/local/bin/code
  }

  echo_green "=== Installing VSCode extensions"

  while read extension; do
      echo_yellow "=== Installing $extension"
      code --install-extension $extension
  done <./others/macos/vscode/extensions
}

mkdir -p /Library
stow_packages
install_extensions
