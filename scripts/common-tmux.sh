#!/bin/bash

set -e

echo_yellow "================================  Tmuxinator ==================================="

source ~/.asdf/asdf.sh

gem list | grep tmuxinator >/dev/null 2>&1 || {
  gem install tmuxinator
  mkdir -p ~/.bin && curl https://raw.githubusercontent.com/tmuxinator/tmuxinator/master/completion/tmuxinator.zsh -o ~/.bin/tmuxinator.zsh
}
