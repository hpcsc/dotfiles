#!/bin/bash

set -e

is_ubuntu || exit 0

# Install essential tools
for i in zsh stow vim tree jq tmux tig direnv; do
  echo_yellow "=== Installing $i"
  sudo apt-get install -y $i
  command -v $i >/dev/null 2>&1 || echo_red "Failed to install $i"
done

(command -v nvim >/dev/null && echo_green "=== Neovim is already installed, skipped")|| {
  echo_yellow "=== Adding fasd apt repository"
  sudo add-apt-repository -r -y ppa:neovim-ppa/stable
  sudo add-apt-repository -y ppa:neovim-ppa/stable
  sudo apt-get update

  echo_yellow "=== Installing Neovim"
  sudo apt-get install -y neovim
}
