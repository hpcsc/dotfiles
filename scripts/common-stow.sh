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

common_packages=(
  git
  vim
  zsh
  tmux
  tig
)
for i in "${common_packages[@]}"; do
  echo_yellow "=== Backing up folder $i"
  ruby ./scripts/common-backup.rb "./link/common/$i" "~/dotfiles_backup"
  stow -vv --dir=./link/common --target="$HOME" --stow $i || echo_red "Failed to stow $i"
done

echo_yellow "=== Stowing .config folder"
mkdir -p ~/.config
stow -vv --dir=./link/common/dot-config --target="$HOME/.config" --stow .config || echo_red "Failed to stow .config folder"

is_macos && {
  macos_packages=(
    Applications
  )
  for i in "${macos_packages[@]}"; do
    echo_yellow "=== Backing up folder $i"
    ruby ./scripts/common-backup.rb "./link/macos/$i" "~/dotfiles_backup"
    stow -vv --dir=./link/macos --target="$HOME" --stow $i || echo_red "Failed to stow $i"
  done
}

exit 0
