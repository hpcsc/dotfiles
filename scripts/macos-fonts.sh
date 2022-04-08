#!/bin/bash

set -e

is_macos || exit 0

rm -rf /tmp/Fira.zip /tmp/Fira

latest_fonts_from_github=$(curl https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | \
  jq -r '.assets[] | select(.name | test("FiraCode.*?zip")) | .browser_download_url')

echo "=== Downloading Fira Code from ${latest_fonts_from_github}"
curl -L ${latest_fonts_from_github} -o /tmp/Fira.zip

unzip /tmp/Fira.zip -d /tmp/Fira

echo "=== Installing Fira Code fonts to $HOME/Library/Fonts"
cp -vf /tmp/Fira/* $HOME/Library/Fonts

rm -rf /tmp/Fira.zip /tmp/Fira
