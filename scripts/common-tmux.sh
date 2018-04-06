#!/bin/bash

set -e

echo_yellow "=== Installing tmuxinator"

source ~/.asdf/asdf.sh

((gem list | grep tmuxinator >/dev/null 2>&1 ) && echo_green "=== Tmuxinator is already installed, skipped") || {
  gem install tmuxinator
  mkdir -p ~/.bin && curl https://raw.githubusercontent.com/tmuxinator/tmuxinator/master/completion/tmuxinator.zsh -o ~/.bin/tmuxinator.zsh
}
