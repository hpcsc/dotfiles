#!/bin/bash

# Dependencies: mise-global (common-mise-global.sh)
# This script adds a .NET SDK to ~/.config/mise/config.local.toml, so only this machine installs it
# Note: Optional task - run it after the main installation

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

echo_green "==== Latest .NET SDK versions:"
~/.local/bin/mise ls-remote dotnet | tail -n 10
read -p "=== Choose .NET SDK version to install (e.g. 10.0.100), leave empty to ignore: " dotnet_sdk_version
if [ -n "$dotnet_sdk_version" ]; then
  ~/.local/bin/mise --cd ~/ use --path ~/.config/mise/config.local.toml "dotnet@${dotnet_sdk_version}"
fi
