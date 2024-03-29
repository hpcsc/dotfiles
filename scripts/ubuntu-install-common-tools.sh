#!/bin/bash

set -e

is_ubuntu || exit 0

if [[ -n "${DISPLAY}" ]]; then
  echo_yellow "=== GUI is detected"

  echo_yellow "installing gnome-tweak-tool"
  sudo apt-get install -y gnome-tweak-tool

  echo_yellow "=== Adding copyq apt repository"
  sudo add-apt-repository ppa:hluk/copyq
  sudo apt update

  echo_yellow "=== Installing copyq"
  sudo apt install -y copyq
fi

# Install essential tools
for i in zsh stow vim tree jq tmux rsync; do
  echo_yellow "=== Installing $i"
  sudo apt-get install -y $i
  command -v $i >/dev/null 2>&1 || echo_red "Failed to install $i"
done

(command -v nvim >/dev/null && echo_green "=== Neovim is already installed, skipped")|| {
  if [[ "$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d'=' -f2)" < "18.04" ]]; then
    echo_yellow "=== Adding neovim apt repository"
    sudo add-apt-repository -r -y ppa:neovim-ppa/stable
    sudo add-apt-repository -y ppa:neovim-ppa/stable
    sudo apt-get update

    echo_yellow "=== Installing Neovim"
    sudo apt-get install -y neovim
  else
    echo_yellow "=== Installing Neovim"
    sudo apt install -y neovim
  fi;
}
