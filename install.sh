#!/bin/bash

# source and export helper functions to be used by the rest of this script
source ./zsh/.functions/misc
export -f distro_name
export -f is_macos
export -f is_ubuntu
export -f echo_with_color
export -f echo_yellow
export -f echo_red
export -f echo_green

rm -f ./install.log

echo_green "=====  Setting up your machine..."

scripts=(
  ./scripts/macos-keep-sudo.sh 
  ./scripts/macos-install-homebrew.sh 
  ./scripts/macos-brew-bundle.sh 
  ./scripts/macos-stow.sh 

  ./scripts/ubuntu-install-sudo.sh 
  ./scripts/ubuntu-install-required-packages.sh 
  ./scripts/ubuntu-fasd.sh 
  ./scripts/ubuntu-install-common-tools.sh 
  ./scripts/ubuntu-net-core.sh 
  ./scripts/ubuntu-docker.sh 
  ./scripts/ubuntu-stow.sh 
  ./scripts/ubuntu-antigen.sh 
  ./scripts/ubuntu-ripgrep.sh 

  ./scripts/common-asdf-plugins.sh
  ./scripts/common-vim.sh
  ./scripts/common-tmux.sh
  ./scripts/common-working-folders.sh

  ./scripts/macos-settings.sh
)

for i in "${scripts[@]}"; do
  $i && echo "OK $i" >> ./install.log || {
    echo_red "FAILED $i"
    echo "FAILED $i" >> ./install.log
  }
done
