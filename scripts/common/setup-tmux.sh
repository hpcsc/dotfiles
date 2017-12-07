#!/bin/bash

echo "=== Setup tmuxinator"

source ~/.asdf/asdf.sh

gem install tmuxinator
mkdir -p ~/.bin && curl https://raw.githubusercontent.com/tmuxinator/tmuxinator/master/completion/tmuxinator.zsh -o ~/.bin/tmuxinator.zsh
