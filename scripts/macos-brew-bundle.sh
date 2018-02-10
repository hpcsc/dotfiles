#!/bin/bash

set -e

is_macos || exit 0

echo_yellow "==============================  Brew Bundle =============================="

# Update Homebrew recipes
brew update

# Install all our dependencies with bundle (See Brewfile)
brew tap homebrew/bundle
brew bundle
