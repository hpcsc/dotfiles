#!/bin/bash

set -e

source ~/.asdf/asdf.sh

asdf plugin-list | grep python >/dev/null 2>&1 || {
  echo_red "=== ASDF (python plugin) must be installed before executing this script"
  exit 1
}

echo_yellow "=== Installing Neovim Python support"
# install Neovim python support, this must be after asdf setup since it's dependent on Python
pip3 install neovim || echo_red "Failed to install Neovim python support"

echo_yellow "=== Installing Neovim plugins"
nvim +PlugInstall +UpdateRemotePlugins +qall
