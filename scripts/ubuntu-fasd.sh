#!/bin/bash

set -e

is_ubuntu || exit 0

# install additional tools
command -v fasd >/dev/null 2>&1 || {
  echo_yellow "=== Adding fasd apt repository"
  sudo add-apt-repository -r ppa:aacebedo/fasd
  sudo add-apt-repository -y ppa:aacebedo/fasd
  sudo apt-get update

  echo_yellow "=== Installing fasd"
  sudo apt-get install fasd
}
