#!/bin/bash

set -e

is_ubuntu || exit 0

command -v dotnet >/dev/null 2>&1 || {
  echo_yellow "=========================== .NET Core    ================================="
  code_name=$(lsb_release -cs)
  curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
  sudo mv microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
  sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-'$code_name'-prod '$code_name' main" > /etc/apt/sources.list.d/dotnetdev.list'
  sudo apt-get update
  echo_green "==== Available .NET Core SDK:"
  apt search dotnet-sdk
  read -p "=== Choose version number to install (.e.g. 2.0.3), leave empty to ignore:" dotnet_sdk_version
  if [ "$dotnet_sdk_version" != "" ]; then
    sudo apt-get install -y dotnet-sdk-$dotnet_sdk_version || echo_red "Failed to install .NET Core version $dotnet_sdk_version"
  fi
}
