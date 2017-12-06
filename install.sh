#!/bin/sh

echo "Setting up your Mac..."

sudo -v

# Keep-alive: update existing `sudo` time stamp until `install.sh` has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Check for Homebrew and install if we don't have it
if test ! $(which brew); then
  /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

echo "==============================  Brew Bundle =============================="

# Update Homebrew recipes
brew update

# Install all our dependencies with bundle (See Brewfile)
brew tap homebrew/bundle
brew bundle

echo "================================  Stow ==================================="

# create symlink at home directory for these packages
ruby ./backup_and_stow.rb

# Specify the preferences directory
defaults write com.googlecode.iterm2.plist PrefsCustomFolder -string "~/dotfiles/iterm"
# Tell iTerm2 to use the custom preferences in the directory
defaults write com.googlecode.iterm2.plist LoadPrefsFromCustomFolder -bool true

echo "=============================  VimPlug Update ============================"

# install VimPlug plugins
vim +PlugInstall +qall

echo "=============================  ASDF ======================================="

git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.4.0
source ~/.asdf/asdf.sh
source ~/.asdf/completions/asdf.bash

# nodejs plugin for asdf
asdf plugin-add nodejs https://github.com/asdf-vm/asdf-nodejs.git
bash ~/.asdf/plugins/nodejs/bin/import-release-team-keyring # Imports Node.js release team's OpenPGP keys to main keyring

# ruby plugin for asdf
asdf plugin-add ruby https://github.com/asdf-vm/asdf-ruby.git

# golang plugin for asdf
asdf plugin-add golang https://github.com/kennyp/asdf-golang.git

echo "=============================  Create working folders ============================="
mkdir -p ~/Workspace/Code
mkdir -p ~/Personal/Code

echo "==========================  MacOS Preferences ============================"

# Set macOS preferences
# We will run this last because this will reload the shell
source .macos
