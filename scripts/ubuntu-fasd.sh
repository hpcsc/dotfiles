#!/bin/bash

set -e

is_ubuntu || exit 0

(command -v fasd >/dev/null 2>&1 && echo_green "=== fasd is already installed, skipped") || {
  if [ -z "$(apt-cache search fasd)" ] 
  then
    echo_yellow "=== Adding fasd apt repository"
    sudo add-apt-repository -r -y ppa:aacebedo/fasd
    sudo add-apt-repository -y ppa:aacebedo/fasd
    sudo apt-get update
  fi;

  echo_yellow "=== Installing fasd"
  sudo apt-get install -y fasd
}
