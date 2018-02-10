#!/bin/bash

set -e

is_ubuntu || exit 0

# Install essential tools
for i in zsh stow vim tree jq tmux; do
  echo_yellow "=== Installing $i"
  sudo apt-get install -y $i
  command -v $i >/dev/null 2>&1 || echo_red "Failed to install $i"
done
