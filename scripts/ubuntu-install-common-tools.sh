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
for i in zsh stow vim tree jq tmux rsync unzip; do
  echo_yellow "=== Installing $i"
  sudo apt-get install -y $i
  command -v $i >/dev/null 2>&1 || echo_red "Failed to install $i"
done

