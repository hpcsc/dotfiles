#!/bin/sh

echo "Setting up your Linux..."

sudo -v

# Keep-alive: update existing `sudo` time stamp until `install.sh` has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# in case add-apt-repository is missing
apt-get update
apt-get install -y software-properties-common python-software-properties

# install additional tools
add-apt-repository ppa:aacebedo/fasd
apt-get update

# Install essential tools
apt-get install -y zsh fasd stow vim

echo "=========================== Prezto Setup ================================="

git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"

echo "================================= Stow  =================================="
stow zsh
stow vim

echo "=============================  VimPlug Update ============================"

# install VimPlug plugins
vim +PlugInstall +qall

echo "=============================  Change Shell  ============================="
chsh -s /bin/zsh
