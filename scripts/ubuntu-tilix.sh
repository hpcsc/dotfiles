#!/bin/bash


# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

sudo apt-get update && sudo apt-get install -y tilix && dconf load /com/gexperts/Tilix/ < ~/dotfiles/others/ubuntu/tilix.dconf
