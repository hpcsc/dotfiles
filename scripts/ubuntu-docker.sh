#!/bin/bash

set -e

is_ubuntu || exit 0

(command -v docker >/dev/null 2>&1 && echo_green "=== Docker is already installed, skipped") || {
  echo_yellow "=== Installing Docker CE"
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


(command -v docker-compose >/dev/null 2>&1 && echo_green "=== docker-compose is already installed, skipped") || {
  echo_yellow "=== Installing docker-compose"
  download_url=$(curl https://api.github.com/repos/docker/compose/releases/latest | \
                  jq -r '.assets[] | select(.name=="docker-compose-'$(uname -s | tr "[:upper:]" "[:lower:]")'-'$(uname -m)'") | .browser_download_url')
  echo_yellow "=== Downloading docker-compose from ${download_url}"
  sudo curl -L ${download_url} -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
}
