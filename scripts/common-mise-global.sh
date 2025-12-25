#!/bin/bash

# Dependencies: mise (common-mise.sh), stow (common-stow.sh)
# This script requires ~/.local/bin/mise and ~/.config/mise/config.toml
# Note: Must run after stow script since this needs ~/.config/mise/config.toml

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e
export PATH="$HOME/.cargo/bin:$PATH"
MISE_EXPERIMENTAL=true ~/.local/bin/mise --cd ~/ --yes install
