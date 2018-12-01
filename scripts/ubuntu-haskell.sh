#!/bin/bash

set -e

is_ubuntu || exit 0

confirm_no "=== Install Haskell?" && exit 0

echo_yellow "=== Installing/Updating Haskell Stack"
if [ -f /usr/local/bin/stack ]; then
  /usr/local/bin/stack upgrade
else
  curl -sSL https://get.haskellstack.org/ | sh
fi;

confirm_no "=== Install haskell-ide-engine" && {
  echo_yellow "=== Skipping haskell-ide-engine"
  exit 0
}

echo_yellow "=== Installing haskell-ide-engine"
echo_yellow "====== Installing libtinfo-dev for haskell-ide-engine"
sudo apt-get update && sudo apt-get install -y libtinfo-dev 

echo_yellow "====== Installing haskell-ide-engine"
git clone https://github.com/haskell/haskell-ide-engine ~/haskell-ide-engine && cd ~/haskell-ide-engine
stack install
