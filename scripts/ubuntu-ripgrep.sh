#!/bin/bash

set -e

is_ubuntu || exit

echo_yellow "=============================  RipGrep ==================================="
command -v rg >/dev/null 2>&1 || {
  ripgrep_version=$(curl https://api.github.com/repos/BurntSushi/ripgrep/releases/latest | jq -r '.tag_name')
  ripgrep_url="https://github.com/BurntSushi/ripgrep/releases/download/$ripgrep_version/ripgrep-$ripgrep_version-x86_64-unknown-linux-musl.tar.gz"
  echo_yellow "=== Downloading ripgrep at $ripgrep_url"
  curl -L $ripgrep_url -o ripgrep.tar.gz
  mkdir ripgrep && tar -xzf ripgrep.tar.gz -C ripgrep --strip-components 1
  sudo mv ripgrep/rg /usr/local/bin && rm -rf ./ripgrep ripgrep.tar.gz
}
