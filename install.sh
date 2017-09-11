#!/bin/sh

echo "Setting up your Mac..."

sudo -v

# Keep-alive: update existing `sudo` time stamp until `install.sh` has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Check for Homebrew and install if we don't have it
if test ! $(which brew); then
  /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

# Update Homebrew recipes
brew update

# Install all our dependencies with bundle (See Brewfile)
brew tap homebrew/bundle
brew bundle

# Setup Prezto
git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"

# create symlink at home directory for these packages
ruby ./backup_and_stow.rb

# Set macOS preferences
# We will run this last because this will reload the shell
source .macos
