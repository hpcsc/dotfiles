#!/bin/bash

# Dependencies: rust (common-rust.sh)
# This script uses cargo to install tools like yazi

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
