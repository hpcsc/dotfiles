#!/bin/bash

set -e

stow -vv \
    --dir=./link/macos/Applications \
    --target="$HOME" \
    --stow PathFinder || echo_red "Failed to stow vscode settings"
