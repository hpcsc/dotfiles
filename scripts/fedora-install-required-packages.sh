#!/bin/bash

# Dependencies: none
# This script installs required packages on Fedora before common tools

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

is_fedora || exit 0

# bison, pkgconf-pkg-config and ncurses-devel are what the mise-tmux build compiles against
for i in findutils @development-tools grubby bison pkgconf-pkg-config ncurses-devel zlib-devel sqlite-devel bzip2-devel openssl-devel libffi-devel libclang-devel; do
  echo_yellow "=== Installing $i"
  sudo dnf install -y $i || echo_red "=== Failed to install $i"
done
