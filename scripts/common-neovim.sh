#!/bin/bash

set -e

echo_yellow "================================  NeoVim ==================================="

source ~/.asdf/asdf.sh

asdf plugin-list | grep python >/dev/null 2>&1 && {
    echo_yellow "=== Installing Neovim Python support"
    # install Neovim python support, this must be after asdf setup since it's dependent on Python
    pip3 install neovim
}

echo_yellow "=== Installing plugins"
nvim +PlugInstall +UpdateRemotePlugins +qall
