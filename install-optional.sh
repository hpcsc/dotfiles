#!/usr/bin/env bash

# source and export helper functions to be used by the rest of this script
set -a
source ./load-zsh-autoload-as-functions.sh
set +a

PS3='Choose script to execute: '

function prompt_and_execute() {
  local options=("$@")
  echo_green "========== Scripts ============="
  select opt in "${options[@]}"
  do
    echo_yellow "================================"
    local index=$((REPLY-1))

    if [ $index -lt 0 ]; then
      echo_red "=== Invalid option ${REPLY}"
    elif [ "$opt" = 'Quit' ]; then
      echo_yellow "=== Quitting"
      break
    else
      local script="${options[${index}]}"
      echo_yellow "=== Executing script ${script}"
      ${script} || echo_red "=== Failed to execute ${script}"
      echo_yellow "=== Done executing script ${script}"
    fi;
    echo ""
    echo ""
    echo_green "========== Scripts ============="
    REPLY=''
  done
}

macos_only_options=(
  './scripts/macos-haskell.sh' 
)

ubuntu_only_options=(
  './scripts/ubuntu-haskell.sh' 
  './scripts/ubuntu-net-core.sh'
  './scripts/ubuntu-tilix.sh'
)

common_options=(
  './scripts/common-asdf-plugins.sh nodejs'
  './scripts/common-asdf-plugins.sh ruby'
  './scripts/common-asdf-plugins.sh python'
  './scripts/common-asdf-plugins.sh kubectl'
  './scripts/common-asdf-plugins.sh helm'
  './scripts/common-krew.sh'
  './scripts/common-rust.sh'
  'Quit'
)

is_macos && (macos_options=("${macos_only_options[@]}" "${common_options[@]}") && prompt_and_execute "${macos_options[@]}")
is_ubuntu && (ubuntu_options=("${ubuntu_only_options[@]}" "${common_options[@]}") && prompt_and_execute "${ubuntu_options[@]}")

