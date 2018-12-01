#!/bin/bash

set -e

is_ubuntu || exit 0

# in case add-apt-repository is missing
sudo apt-get update

for i in software-properties-common apt-transport-https lsb-release curl build-essential zlib1g-dev libssl-dev libffi-dev libreadline-dev; do
  echo_yellow "=== Installing $i"
  sudo apt-get install -y $i || echo_red "=== Failed to install $i"
done
