#!/bin/bash


# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

is_fedora || exit 0

sudo dnf copr enable pschyska/alacritty
sudo dnf install alacritty
