#!/bin/bash

# Dependencies: none
# This script installs sudo on systems where it's not installed by default
# Note: Should be run first on fresh Ubuntu installations

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

is_ubuntu || exit 0

command -v sudo >/dev/null 2>&1 || {
    echo_blue "=== No sudo available, installing sudo"
    apt-get update && apt-get install -y sudo
}
