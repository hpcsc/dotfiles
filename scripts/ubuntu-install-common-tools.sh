#!/bin/bash

# Dependencies: ubuntu-install-required-packages.sh
# This script installs essential tools including stow
# Note: Checks for fc-cache and identify binaries (not the fontconfig and
# imagemagick package names) after installation

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

is_ubuntu || exit 0

if [[ -n "${DISPLAY}" ]]; then
  echo_yellow "=== GUI is detected"

  echo_yellow "installing gnome-tweak-tool"
  sudo apt-get install -y gnome-tweak-tool

  echo_yellow "=== Adding copyq apt repository"
  sudo add-apt-repository ppa:hluk/copyq
  sudo apt update

  echo_yellow "=== Installing copyq"
  sudo apt install -y copyq
fi

# Install essential tools
for i in zsh stow vim tree tmux rsync unzip chafa; do
  echo_yellow "=== Installing $i"
  sudo apt-get install -y $i
  command -v $i >/dev/null 2>&1 || echo_red "Failed to install $i"
done

echo_yellow "=== Installing fontconfig"
sudo apt-get install -y fontconfig
command -v fc-cache >/dev/null 2>&1 || echo_red "Failed to install fontconfig"

# Ubuntu ships ImageMagick 6, whose binary is `identify`; the unified `magick`
# entrypoint only exists in ImageMagick 7. snacks.nvim probes for both.
echo_yellow "=== Installing imagemagick"
sudo apt-get install -y imagemagick
command -v identify >/dev/null 2>&1 || echo_red "Failed to install imagemagick"

