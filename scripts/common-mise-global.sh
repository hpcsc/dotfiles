#!/bin/bash

set -e

# need to be after stow script since this needs ~/.config/mise/config.toml
echo_yellow "=== Installing global tools with mise"
export PATH="$HOME/.cargo/bin:$PATH"
MISE_EXPERIMENTAL=true ~/.local/bin/mise --cd ~/ --yes install
