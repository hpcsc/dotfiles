#!/bin/bash

set -e

# must be after mise

if [ -z "$(~/.local/bin/mise exec cargo:yazi-cli -- ya pack -l | grep gruvbox-dark)" ]; then
  echo_yellow "=== Installing yazi gruvbox-dark flavour"
  ~/.local/bin/mise exec cargo:yazi-cli -- ya pack -a bennyyip/gruvbox-dark
else
  echo_yellow "=== yazi gruvbox-dark flavour exists, skip installation"
fi
