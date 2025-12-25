#!/bin/bash

# Dependencies: working-folders (common-working-folders.sh)
# This script extracts Istio to ~/Tools/
# Note: Optional task - should be run after main installation

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

is_macos && OS=osx || OS=linux

latest_release=$(curl https://api.github.com/repos/istio/istio/releases/latest)
latest_tag=$(echo ${latest_release} | jq -r '.tag_name')
download_url=$(echo ${latest_release} | \
  jq -r '.assets[] | select(.name | test("'${OS}'.tar.gz$")) | .browser_download_url')

rm -rf ~/Tools/istio-${latest_tag}

echo_green "=== Downloading Istio from ${download_url} and extract to ~/Tools"
# requires working-folders (common-working-folders.sh) to create ~/Tools/ directory
curl -L ${download_url} | tar xvzf - -C ~/Tools 
