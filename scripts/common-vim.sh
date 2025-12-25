#!/bin/bash


# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

echo_yellow "=== Installing Vim plugins"

# install VimPlug plugins, this must be after mise setup since fzf plugin is dependent on Go SDK
vim +PlugInstall +qall
