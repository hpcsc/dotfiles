#!/bin/bash

common_packages=(
  bash
  git
  vim
  zsh
  tmux
  tig
  ctags
  shell
  alacritty
)

function backup() {
  local backup_folder_name=~/dotfiles_backup
  mkdir -p $backup_folder_name

  for i in "${common_packages[@]}"; do
    echo_yellow "=== Backing up folder $i"
    # --filter tells rsync to do a directory merge with .gitignore files and have them exclude per git's rules
    rsync -v \
          --times \
          --remove-source-files \
          --delete \
          --recursive \
          --human-readable \
          --filter=':- .gitignore' \
          --files-from=<(ls -A "./link/common/$i") \
          $HOME \
          "${backup_folder_name}/${i}"
    echo_yellow "=== Folder $i is backed up to ${backup_folder_name}/${i}"
  done
}

function stow_packages() {
  for i in "${common_packages[@]}"; do
    stow -vv --dir=./link/common --target="$HOME" --stow $i || echo_red "Failed to stow $i"
  done

  echo_yellow "=== Stowing .config folder"
  mkdir -p ~/.config
  stow -vv --dir=./link/common/dot-config --target="$HOME/.config" --stow .config || echo_red "Failed to stow .config folder"

  echo_yellow "=== Stowing .local/bin folder"
  mkdir -p ~/.local/bin
  stow -vv --dir=./link/common/dot-local --target="$HOME/.local/bin" --stow bin
}

# backup
stow_packages

exit 0
