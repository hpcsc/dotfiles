#!/bin/bash

set -e

echo_yellow "=== Installing Neovim plugins"
~/.local/bin/mise exec neovim -- nvim +PlugInstall +UpdateRemotePlugins +qall
