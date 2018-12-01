#!/bin/bash

set -e

is_macos || exit 0

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
echo_yellow "====== Installing text-icu dependency for haskell-ide-engine"
stack install text-icu \
 --extra-lib-dirs=/usr/local/opt/icu4c/lib \
 --extra-include-dirs=/usr/local/opt/icu4c/include

echo_yellow "====== Installing haskell-ide-engine"
git clone https://github.com/haskell/haskell-ide-engine ~/haskell-ide-engine && cd ~/haskell-ide-engine
stack install
