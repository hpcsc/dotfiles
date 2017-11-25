#!/bin/bash

echo "Setting up your Linux..."

command -v sudo >/dev/null 2>&1 || {
    echo "No sudo available, installing sudo"
    apt-get update && apt-get install -y sudo
}

# in case add-apt-repository is missing
sudo apt-get update
sudo apt-get install -y software-properties-common python-software-properties apt-transport-https lsb-release curl

# install additional tools
sudo add-apt-repository ppa:aacebedo/fasd
sudo apt-get update

# Install essential tools
sudo apt-get install -y zsh fasd stow vim

echo "=========================== .NET Core    ================================="
code_name=$(lsb_release -c | cut -f2)
sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-'$code_name'-prod '$code_name' main" > /etc/apt/sources.list.d/dotnetdev.list'
sudo apt-get update
sudo apt-get install -y dotnet-sdk-2.0.0

echo "================================= Stow  =================================="
stow zsh
stow vim
stow git

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

echo "=============================  Antigen=================================="
sudo sh -c 'mkdir -p /usr/share/antigen && curl -L git.io/antigen > /usr/share/antigen/antigen.zsh'

echo "=============================  Create working folders ============================="
mkdir -p ~/Workspace/Code
mkdir -p ~/Personal/Code

echo "=============================  Change Shell  ============================="
chsh -s $(which zsh)
