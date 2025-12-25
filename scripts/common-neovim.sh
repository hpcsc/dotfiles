#!/bin/bash


# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

echo_yellow "=== Installing Neovim plugins (lazy.nvim)"
~/.local/bin/mise exec neovim -- nvim --headless "+Lazy! sync" +qa
