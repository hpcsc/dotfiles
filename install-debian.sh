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
code_name=$(lsb_release -cs)
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo mv microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-'$code_name'-prod '$code_name' main" > /etc/apt/sources.list.d/dotnetdev.list'
sudo apt-get update
sudo apt-get install dotnet-sdk-2.0.3

echo "=========================== Docker CE    ================================="
sudo apt-get install ca-certificates
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
sudo apt-get update
sudo apt-get install docker-ce
# add current user to docker group, to solve permission issue in ubuntu
sudo usermod -a -G docker $(id -un)

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

# golang plugin for asdf
asdf plugin-add golang https://github.com/kennyp/asdf-golang.git

echo "=============================  Antigen ==================================="
sudo sh -c 'mkdir -p /usr/share/antigen && curl -L git.io/antigen > /usr/share/antigen/antigen.zsh'

echo "=============================  Create working folders ===================="
mkdir -p ~/Workspace/Code
mkdir -p ~/Personal/Code

echo "=============================  Change Shell  ============================="
chsh -s $(which zsh)
