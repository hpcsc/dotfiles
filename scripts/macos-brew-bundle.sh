#!/bin/bash


# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

is_macos || exit 0

echo_yellow "=== Brew update"

# Update Homebrew recipes
brew update

echo_yellow "=== Restoring bundles from Brewfile"
# Install all our dependencies with bundle (See Brewfile)
brew bundle
