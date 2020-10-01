#!/bin/bash

# source and export helper functions to be used by the rest of this script
set -a
source ./load-zsh-autoload-as-functions.sh
set +a

function execute_scripts() {
  local scripts_array_name=$1[@]
  local scripts=${!scripts_array_name}
  for i in $scripts; do
    echo_purple "=============================  $i ======================================="

    $i && echo "OK $i" >> ./install.log || {
      echo_red "FAILED $i"
      echo "FAILED $i" >> ./install.log
    }
  done
}

echo_purple "SETTING UP YOUR MACHINE..."
rm -f ./install.log

macos_scripts=(
  ./scripts/macos-keep-sudo.sh
  ./scripts/macos-install-homebrew.sh
  ./scripts/macos-brew-bundle.sh
  ./scripts/macos-fonts.sh
)

ubuntu_scripts=(
  ./scripts/ubuntu-install-sudo.sh
  ./scripts/ubuntu-install-required-packages.sh
  ./scripts/ubuntu-fasd.sh
  ./scripts/ubuntu-install-common-tools.sh
  ./scripts/ubuntu-docker.sh
  ./scripts/ubuntu-ripgrep.sh
  ./scripts/ubuntu-universal-ctags.sh
)

fedora_scripts=(
  ./scripts/fedora-install-required-packages.sh
  ./scripts/fedora-fasd.sh
  ./scripts/fedora-install-common-tools.sh
  ./scripts/fedora-docker.sh
  ./scripts/fedora-alacritty.sh
)

common_scripts=(
  ./scripts/common-prezto.sh
  ./scripts/common-asdf.sh
  ./scripts/common-asdf-plugins.sh
  ./scripts/common-stow.sh
  ./scripts/common-vim.sh
  ./scripts/common-neovim.sh
  ./scripts/common-python-tools.sh
  ./scripts/common-working-folders.sh
)

is_macos && (execute_scripts macos_scripts)
is_ubuntu && (execute_scripts ubuntu_scripts)
is_fedora && (execute_scripts fedora_scripts)
execute_scripts common_scripts

# This should be run last because this will reload the shell
is_macos && source ./scripts/macos-settings.sh
