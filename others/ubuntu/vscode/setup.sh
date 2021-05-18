#!/bin/bash

set -euo pipefail

source ./load-zsh-autoload-as-functions.sh

function stow_packages() {
  stow -vv \
    --dir=./link/ubuntu/vscode/.config \
    --target="$HOME/.config/Code" \
    --stow Code || echo_red "Failed to stow vscode settings"
}

function sync_extensions() {
  command -v code >/dev/null 2>&1 || {
      echo_yellow "VSCode executable is not in Path, exiting"
      exit 1
  }

  echo_green "=== Installing VSCode extensions"

  while read extension; do
      echo_yellow "=== Installing $extension"
      code --install-extension $extension
  done <./others/ubuntu/vscode/extensions

  # get list of extensions that are installed but not in the extensions files
  # need to suppress error code from diff since it returns code 1 when there's difference
  TO_UNINSTALL=( $(diff <(code --list-extensions) \
                      <(cat ./others/ubuntu/vscode/extensions) \
                      --old-line-format="%L" \
                      --new-line-format="" \
                      --unchanged-line-format="" || true) )
  for extension in "${TO_UNINSTALL[@]}"; do
      echo_yellow "=== Uninstalling $extension"
      # code --uninstall-extension $extension
  done
}

mkdir -p "$HOME/.config/Code"
stow_packages
sync_extensions
