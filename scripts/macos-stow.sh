#!/bin/bash

set -e

is_macos || exit 0

[ -f ~/.asdf/asdf.sh ] >/dev/null 2>&1 || {
  echo_red "=== ASDF (ruby plugin) must be installed before executing this script"
  exit 1
}

source ~/.asdf/asdf.sh

macos_packages=(
  Applications
)

function backup() {
  read -p "=== Backing up before stowing? (Yn)" confirm_backup
  if [ "$confirm_backup" = "" ] || [ "$confirm_backup" = "y" ] || [ "$confirm_backup" = "Y" ]; then
    local backup_folder_name=~/dotfiles_backup
    mkdir -p $backup_folder_name

    for i in "${macos_packages[@]}"; do
      echo_yellow "=== Backing up folder $i"
      ruby ./scripts/common-backup.rb "./link/macos/$i" "$backup_folder_name"
    done
  fi
}

function stow_packages() {
  for i in "${macos_packages[@]}"; do
    stow -vv --dir=./link/macos --target="$HOME" --stow $i || echo_red "Failed to stow $i"
  done
}

backup
stow_packages
