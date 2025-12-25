#!/bin/bash


# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -euo pipefail

echo_yellow "=== Installing essential Python tools for Python@$(which python)"
AWSUME_SKIP_ALIAS_SETUP=true \
    ~/.local/bin/mise exec python -- pip3 install --upgrade -r ./python-requirements.txt
