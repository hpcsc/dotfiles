#!/bin/bash

set -euo pipefail

if [ -d ~/.tmux/plugins/tpm ]; then
  echo_yellow "=== tmux plugin manager installed, updating"
  pushd ~/.tmux/plugins/tpm
  git pull -r
  popd
  echo_yellow "=== updating tmux plugins using tpm"
  ~/.tmux/plugins/tpm/bin/update_plugins all
else
  echo_yellow "=== installing tmux plugin manager"
  mkdir -p ~/.tmux/plugins
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
  echo_yellow "=== installing tmux plugins using tpm"
  ~/.tmux/plugins/tpm/bin/install_plugins
fi
