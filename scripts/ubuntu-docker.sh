#!/bin/bash

set -e

is_ubuntu || exit 0

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
