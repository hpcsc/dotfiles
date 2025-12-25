#!/bin/bash

# Dependencies: mise (common-mise.sh)
# This script requires mise to provide Go SDK for fzf plugin
# Note: install VimPlug plugins, this must be after mise setup since fzf plugin is dependent on Go SDK

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

echo_yellow "=== Installing Vim plugins"
vim +PlugInstall +qall
