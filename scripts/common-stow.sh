#!/bin/bash

set -e

[ -f ~/.asdf/asdf.sh ] >/dev/null 2>&1 || {
  echo_red "=== ASDF (ruby plugin) must be installed before executing this script"
  exit 1
}

source ~/.asdf/asdf.sh

common_packages=(
  git
  vim
  zsh
  tmux
  tig
)

function backup() {
  read -p "=== Backing up before stowing? (Yn)" confirm_backup
  if [ "$confirm_backup" = "" ] || [ "$confirm_backup" = "y" ] || [ "$confirm_backup" = "Y" ]; then
    local backup_folder_name=~/dotfiles_backup
    mkdir -p $backup_folder_name

    for i in "${common_packages[@]}"; do
      echo_yellow "=== Backing up folder $i"
      ruby ./scripts/common-backup.rb "./link/common/$i" "$backup_folder_name"
    done
  fi
}

function stow_packages() {
  for i in "${common_packages[@]}"; do
    stow -vv --dir=./link/common --target="$HOME" --stow $i || echo_red "Failed to stow $i"
  done

  echo_yellow "=== Stowing .config folder"
  mkdir -p ~/.config
  stow -vv --dir=./link/common/dot-config --target="$HOME/.config" --stow .config || echo_red "Failed to stow .config folder"
}

backup
stow_packages

exit 0
