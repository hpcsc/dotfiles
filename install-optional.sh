#!/usr/bin/env bash

# source and export helper functions to be used by the rest of this script
set -a
source ./load-zsh-autoload-as-functions.sh
set +a

PS3='Choose script to execute: '

function prompt_and_execute() {
  local options=("$@")
  echo "========== Scripts ============="
  select opt in "${options[@]}"
  do
    echo "================================"
    local index=$((REPLY-1))

    if [ $index -lt 0 ]; then
      echo "=== Invalid option ${REPLY}"
    elif [ "$opt" = 'Quit' ]; then
      echo "=== Quitting"
      break
    else
      local script="${options[${index}]}"
      echo "=== Executing script ${script}"
      ${script}
      echo "=== Done executing script ${script}"
    fi;
    echo ""
    echo ""
    echo "========== Scripts ============="
    REPLY=''
  done
}

macos_options=(
  './scripts/macos-haskell.sh' 
  'Quit'
)

ubuntu_options=(
  './scripts/ubuntu-haskell.sh' 
  './scripts/ubuntu-net-core.sh'
  'Quit'
)

is_macos && (prompt_and_execute "${macos_options[@]}")
is_ubuntu && (prompt_and_execute "${ubuntu_options[@]}")

