#!/bin/bash

set -e

echo_yellow "=== Installing Neovim plugins"
nvim +PlugInstall +UpdateRemotePlugins +qall
