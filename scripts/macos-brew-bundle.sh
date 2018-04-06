#!/bin/bash

set -e

is_macos || exit 0

echo_yellow "=== Brew update"

# Update Homebrew recipes
brew update

echo_yellow "=== Restoring bundles from Brewfile"
# Install all our dependencies with bundle (See Brewfile)
brew tap homebrew/bundle
brew bundle
