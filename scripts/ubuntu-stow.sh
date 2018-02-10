#!/bin/bash

set -e

is_ubuntu || exit 0

echo_yellow "================================= Stow  =================================="

stow -vv zsh
stow -vv vim
stow -vv git
stow -vv tmux
stow -vv tig
