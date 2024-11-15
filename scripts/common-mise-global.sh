#!/bin/bash

set -e

# need to be after stow script since this needs ~/.config/mise/config.toml
echo_yellow "=== Installing global tools with mise"
MISE_EXPERIMENTAL=true ~/.local/bin/mise --cd ~/ --yes install
