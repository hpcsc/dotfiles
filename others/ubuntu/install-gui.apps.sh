#!/bin/bash

sudo apt-get update
for i in gnome-tweak-tool; do
  echo "=== Installing $i"
  sudo apt-get install -y $i
  command -v $i >/dev/null 2>&1 || echo_red "Failed to install $i"
done
