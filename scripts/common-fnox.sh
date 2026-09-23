#!/bin/bash

# Dependencies: stow (common-stow.sh)
# This script requires ~/.config/fnox/shared.toml from the stowed dot-config package.
# Note: Must run after stow script since this needs ~/.config/fnox/shared.toml

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

FNOX_DIR="$HOME/.config/fnox"
CONFIG_FILE="$FNOX_DIR/config.toml"

# The machine-specific config.toml is a real file (not stowed); it imports the
# stowed shared.toml so machine secrets can live outside the repo. A symlink
# here means the old stowed layout is on disk — replace it.
if [ -L "$CONFIG_FILE" ]; then
    rm "$CONFIG_FILE"
fi

# Create ~/.config/fnox/config.toml if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    mkdir -p "$FNOX_DIR"
    printf 'import = ["shared.toml"]\n' > "$CONFIG_FILE"
fi

if [ ! -f "$HOME/.config/fnox/shared.toml" ]; then
    echo_yellow "fnox: ~/.config/fnox/shared.toml not found — run common-stow.sh first"
fi