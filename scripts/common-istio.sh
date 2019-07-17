#!/bin/bash

set -e

is_macos && OS=osx || OS=linux

latest_release=$(curl https://api.github.com/repos/istio/istio/releases/latest)
latest_tag=$(echo ${latest_release} | jq -r '.tag_name')
download_url=$(echo ${latest_release} | \
  jq -r '.assets[] | select(.name | test("'${OS}'.tar.gz$")) | .browser_download_url')

rm -rf ~/Tools/istio-${latest_tag}

echo_green "=== Downloading Istio from ${download_url} and extract to ~/Tools"
curl -L ${download_url} | tar xvzf - -C ~/Tools 
