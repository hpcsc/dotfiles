#!/bin/bash

# Dependencies: none
# This script configures GNOME keyboard settings (requires gsettings)
# Note: Only runs if gsettings is available (Ubuntu with GUI)

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

is_ubuntu || exit 0

(command -v gsettings >/dev/null && {
    echo_green "=== gsettings is available"
    echo_yellow "==== adjusting Gnome keyboard repeat interval"
    gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 30 # hz, default: 30

    echo_yellow "==== adjusting Gnome keyboard delay"
    gsettings set org.gnome.desktop.peripherals.keyboard delay 150 # ms, default: 500
}) || {
    echo_green "=== gsettings is not available, skipping"
}
