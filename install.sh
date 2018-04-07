#!/bin/bash

# source and export helper functions to be used by the rest of this script
source ./link/common/zsh/.functions/misc
export -f distro_name
export -f is_macos
export -f is_ubuntu
export -f echo_with_color
export -f echo_yellow
export -f echo_red
export -f echo_green
export -f echo_blue
export -f echo_purple
export -f echo_cyan

function execute_scripts() {
  local scripts_array_name=$1[@]
  local scripts=("${!scripts_array_name}")
  for i in "${scripts[@]}"; do
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
)

ubuntu_scripts=(
  ./scripts/ubuntu-install-sudo.sh
  ./scripts/ubuntu-install-required-packages.sh
  ./scripts/ubuntu-fasd.sh
  ./scripts/ubuntu-install-common-tools.sh
  ./scripts/ubuntu-net-core.sh
  ./scripts/ubuntu-docker.sh
  ./scripts/ubuntu-antigen.sh
  ./scripts/ubuntu-ripgrep.sh
)

common_scripts=(
  ./scripts/common-asdf-plugins.sh
  ./scripts/common-stow.sh
  ./scripts/common-vim.sh
  ./scripts/common-neovim.sh
  ./scripts/common-tmux.sh
  ./scripts/common-working-folders.sh
)

macos_after_scripts=(
  ./scripts/macos-stow.sh
)

is_macos && (execute_scripts macos_scripts)
is_ubuntu && (execute_scripts ubuntu_scripts)
execute_scripts common_scripts
is_macos && (execute_scripts macos_after_scripts)

# This should be run last because this will reload the shell
is_macos && source ./scripts/macos-settings.sh
