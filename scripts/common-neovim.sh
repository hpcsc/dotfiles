#!/bin/bash

set -e

echo_yellow "=== Installing Neovim plugins (lazy.nvim)"
~/.local/bin/mise exec neovim -- nvim --headless "+Lazy! sync" +qa
