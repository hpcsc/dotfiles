#!/bin/bash

set -e

is_ubuntu || exit

echo_yellow "================================= Stow  =================================="

stow -vv zsh
stow -vv vim
stow -vv git
stow -vv tmux
stow -vv tig
