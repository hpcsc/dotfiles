#!/bin/bash


# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e


if [ -f ~/.local/bin/mise ]; then
    echo_green "=== mise exists, skip installation"
else
    echo_yellow "=== Installing mise"
    curl https://mise.run | sh
fi
