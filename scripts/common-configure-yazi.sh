#!/bin/bash


# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

# must be after mise

install() {
  local name=$1

  if [ -z "$(~/.local/bin/mise exec cargo:yazi-cli -- ya pack -l | grep ${name})" ]; then
    echo_yellow "=== Installing yazi ${name}"
    ~/.local/bin/mise exec cargo:yazi-cli -- ya pack -a ${name}
  else
    echo_yellow "=== yazi ${name} exists, skip installation"
  fi
}

install bennyyip/gruvbox-dark
install yazi-rs/plugins:full-border
