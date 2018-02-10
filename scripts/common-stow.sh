#!/bin/bash

set -e

echo_yellow "================================  Stow ==================================="

[ -f ~/.asdf/asdf.sh ] >/dev/null 2>&1 || {
  echo_red "ASDF (ruby plugin) must be installed before executing this script"
  exit 1
}

source ~/.asdf/asdf.sh
source ~/.asdf/completions/asdf.bash

backup_folder_name=~/dotfiles_backup
mkdir -p $backup_folder_name

packages=(
  git
  vim
  zsh
  Applications
  tmux
  tig
)
for i in "${packages[@]}"; do
  echo_yellow "=== Backing up folder $i"
  ruby ./scripts/common-backup.rb "$i" "~/dotfiles_backup"
  stow -vv $i
done
