#!/bin/bash

source ./zsh/.functions/misc

echo_yellow "=== Setting up your Linux..."

command -v sudo >/dev/null 2>&1 || {
    echo_yellow "=== No sudo available, installing sudo"
    apt-get update && apt-get install -y sudo
}

# in case add-apt-repository is missing
sudo apt-get update
for i in software-properties-common python-software-properties apt-transport-https lsb-release curl build-essential zlib1g-dev libssl-dev; do
  echo_yellow "=== Installing $i"
  sudo apt-get install -y $i
done

# install additional tools
command -v fasd >/dev/null 2>&1 || {
  echo_yellow "=== Adding fasd apt repository"
  sudo add-apt-repository -r ppa:aacebedo/fasd
  sudo add-apt-repository ppa:aacebedo/fasd -y
  sudo apt-get update

  echo_yellow "=== Installing fasd"
  sudo apt-get install fasd
}

# Install essential tools
for i in zsh stow vim tree jq tmux; do
  echo_yellow "=== Installing $i"
  sudo apt-get install -y $i
  command -v $i >/dev/null 2>&1 || echo_red "Failed to install $i"
done

command -v dotnet >/dev/null 2>&1 || {
  echo_yellow "=========================== .NET Core    ================================="
  code_name=$(lsb_release -cs)
  curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
  sudo mv microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
  sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-'$code_name'-prod '$code_name' main" > /etc/apt/sources.list.d/dotnetdev.list'
  sudo apt-get update
  echo_green "==== Available .NET Core SDK:"
  apt search dotnet-sdk
  read -p "=== Choose version number to install (.e.g. 2.0.3):" dotnet_sdk_version
  sudo apt-get install -y dotnet-sdk-$dotnet_sdk_version
}

command -v docker >/dev/null 2>&1 || {
  echo_yellow "=========================== Docker CE    ================================="
  echo_yellow "=== Installing docker CE"
  sudo apt-get install ca-certificates
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo add-apt-repository \
     "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
     $(lsb_release -cs) \
     stable"
  sudo sh -c 'apt-get update && apt-get install -y docker-ce'
  # add current user to docker group, to solve permission issue in ubuntu
  sudo usermod -a -G docker $(id -un)
}

echo_yellow "================================= Stow  =================================="

stow -vv zsh
stow -vv vim
stow -vv git
stow -vv tmux

echo_yellow "=============================  ASDF ======================================="

./scripts/common/install-asdf-plugins.sh

echo_yellow "=============================  Antigen ==================================="

[ -f /usr/share/antigen/antigen.zsh ] >/dev/null 2>&1 || {
  sudo sh -c 'mkdir -p /usr/share/antigen && curl -L git.io/antigen > /usr/share/antigen/antigen.zsh'
}

echo_yellow "=============================  RipGrep ==================================="
command -v rg >/dev/null 2>&1 || {
  ripgrep_version=$(curl https://api.github.com/repos/BurntSushi/ripgrep/releases/latest | jq -r '.tag_name')
  ripgrep_url="https://github.com/BurntSushi/ripgrep/releases/download/$ripgrep_version/ripgrep-$ripgrep_version-x86_64-unknown-linux-musl.tar.gz"
  echo_yellow "=== Downloading ripgrep at $ripgrep_url"
  curl -L $ripgrep_url -o ripgrep.tar.gz
  mkdir ripgrep && tar -xzf ripgrep.tar.gz -C ripgrep --strip-components 1
  sudo mv ripgrep/rg /usr/local/bin && rm -rf ./ripgrep ripgrep.tar.gz
}

echo_yellow "=============================  VimPlug Update ============================"

# install VimPlug plugins, this must be after asdf setup since fzf plugin is dependent on Go SDK
vim +PlugInstall +qall

echo_yellow "=============================  tmux ======================================"
./scripts/common/setup-tmux.sh

echo_yellow "=============================  Create working folders ===================="
mkdir -p ~/Workspace/Code
mkdir -p ~/Personal/Code

echo_yellow "=============================  Change Shell  ============================="
chsh -s $(which zsh)
