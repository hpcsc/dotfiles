#!/bin/bash

set -e

DESTINATION=$(is_macos && echo "${HOME}/Library/Fonts" || echo "${HOME}/.local/share/fonts")

mkdir -p "${DESTINATION}"
rm -rf /tmp/Fira.zip /tmp/Fira

latest_fonts_from_github=$(curl https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | \
  jq -r '.assets[] | select(.name | test("FiraCode.*?zip")) | .browser_download_url')

echo_yellow "=== Downloading Fira Code from ${latest_fonts_from_github}"
curl -L ${latest_fonts_from_github} -o /tmp/Fira.zip

unzip /tmp/Fira.zip -d /tmp/Fira

echo_yellow "=== Installing Fira Code fonts to ${DESTINATION}"
cp -vf /tmp/Fira/* ${DESTINATION}

rm -rf /tmp/Fira.zip /tmp/Fira

echo_yellow "=== Installing Powerline Fira Mono fonts to ${DESTINATION}"
git clone https://github.com/powerline/fonts.git /tmp/powerline-fonts
cp -vf /tmp/powerline-fonts/FiraMono/* ${DESTINATION}

rm -rf /tmp/powerline-fonts

if is_ubuntu || is_fedora; then
  echo_yellow "=== Refreshing fonts cache"
  fc-cache -vf
fi
