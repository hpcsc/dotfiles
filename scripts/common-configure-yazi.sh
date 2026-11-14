#!/bin/bash

# Dependencies: mise (common-mise.sh)
# This script requires ~/.local/bin/mise to execute yazi
# Note: must be after mise

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

install() {
  local name=$1

  # requires mise (common-mise.sh) to provide yazi
  if [ -z "$(~/.local/bin/mise exec yazi -- ya pack -l | grep ${name})" ]; then
    echo_yellow "=== Installing yazi ${name}"
    ~/.local/bin/mise exec yazi -- ya pack -a ${name}
  else
    echo_yellow "=== yazi ${name} exists, skip installation"
  fi
}

install bennyyip/gruvbox-dark
install yazi-rs/plugins:full-border
# Both calls require mise (common-mise.sh) to provide yazi
