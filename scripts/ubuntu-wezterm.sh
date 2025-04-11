#!/bin/bash

set -e

is_ubuntu || exit 0

if (command -v wezterm >/dev/null 2>&1) then
  echo_yellow "=== wezterm is installed, updating"
  sudo apt-get install --only-upgrade wezterm
else
  echo_yellow "=== Installing wezterm"
  curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /etc/apt/keyrings/wezterm-fury.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list
  sudo apt update
  sudo apt install -y wezterm
fi
