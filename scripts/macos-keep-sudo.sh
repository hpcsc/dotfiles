#!/bin/bash


# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

is_macos || exit 0

sudo -v

# Keep-alive: update existing `sudo` time stamp until `install.sh` has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
