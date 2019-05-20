#!/bin/bash

set -e

stow -vv \
    --dir=./link/macos/Applications \
    --target="$HOME" \
    --stow Spectacle || echo_red "Failed to stow spectacle settings"