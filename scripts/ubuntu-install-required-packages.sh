#!/bin/bash

set -e

is_ubuntu || exit

# in case add-apt-repository is missing
sudo apt-get update
for i in software-properties-common python-software-properties apt-transport-https lsb-release curl build-essential zlib1g-dev libssl-dev; do
  echo_yellow "=== Installing $i"
  sudo apt-get install -y $i || echo_red "=== Failed to install $i"
done
