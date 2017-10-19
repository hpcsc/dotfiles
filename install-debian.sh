#!/bin/sh

echo "Setting up your Linux..."

# in case add-apt-repository is missing
sudo apt-get update
sudo apt-get install -y software-properties-common python-software-properties

# install additional tools
sudo add-apt-repository ppa:aacebedo/fasd
sudo apt-get update

# Install essential tools
sudo apt-get install -y zsh fasd stow vim

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
