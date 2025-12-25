#!/bin/bash


# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

[ -d ~/.asdf ] && {
  echo_green "=== ASDF is already installed, updating"
  asdf update
} || {
  asdf_version=$(curl https://api.github.com/repos/asdf-vm/asdf/tags | jq -r '.[0].name')
  echo_yellow "=== Checking out asdf at tag $asdf_version"
  git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch $asdf_version || {
    echo_red "=== Failed to install asdf"
    exit 1
  }
}

exit 0
