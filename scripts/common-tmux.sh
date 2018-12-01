#!/bin/bash

set -e

source ~/.asdf/asdf.sh

command -v gem >/dev/null 2>&1 || {
  echo_red "=== no ruby available, skipping"
  exit 1
}

echo_yellow "=== Installing tmuxinator"

((gem list | grep tmuxinator >/dev/null 2>&1 ) && echo_green "=== Tmuxinator is already installed, skipped") || {
  gem install tmuxinator
  mkdir -p ~/.bin && curl https://raw.githubusercontent.com/tmuxinator/tmuxinator/master/completion/tmuxinator.zsh -o ~/.bin/tmuxinator.zsh
}
