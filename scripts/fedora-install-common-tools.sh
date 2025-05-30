#!/bin/bash

set -e

is_fedora || exit 0

# Install essential tools
for i in curl zsh stow vim tree jq tmux rsync python3-neovim ripgrep; do
  echo_yellow "=== Installing $i"
  sudo dnf install -y $i
  echo_green "Installed $i"
done
