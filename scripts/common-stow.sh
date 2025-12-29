#!/bin/bash

# Dependencies: stow binary (installed by OS package manager)
# This script creates symlinks for dotfiles including config files
# Platform-specific: macOS uses brew, Ubuntu uses apt, Fedora uses dnf

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
common_packages=(
  bash
  claude
  git
  vim
  zsh
  tmux
  shell
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

# use --adopt option with stow so that stow import existing file from target (if have) to this dotfiles repo and then remove existing file from target
# git restore to revert the import
# this is a hack for stow to overwrite file in target if exist
function stow_packages() {
  for i in "${common_packages[@]}"; do
    stow -vv --dir=./link/common --target="$HOME" --adopt $i || echo_red "Failed to stow $i"
    git restore ./link/common/$i
  done

  echo_yellow "=== Stowing .config folder"

  echo_yellow "====== Stowing starship folder"
  mkdir -p ~/.config/
  stow -vv --dir=./link/common/dot-config --target="$HOME/.config" starship || echo_red "Failed to stow starship folder"

  for dot_config_dir in ./link/common/dot-config/.config/*/; do
    echo_yellow "====== Stowing ${dot_config_dir} folder"
    local dot_config_package=$(basename ${dot_config_dir})
    mkdir -p ~/.config/${dot_config_package}
    stow -vv --dir=./link/common/dot-config/.config --target="$HOME/.config/${dot_config_package}" --adopt ${dot_config_package} || echo_red "Failed to stow ${dot_config_dir} folder"
    git restore ./link/common/dot-config/.config/${dot_config_package}
  done

  echo_yellow "=== Stowing .local/bin folder"
  mkdir -p ~/.local/bin
  stow -vv --dir=./link/common/dot-local --target="$HOME/.local/bin" --adopt bin || echo_red "Failed to stow .local/bin"
  git restore ./link/common/dot-local/bin

  echo_yellow "=== Stowing /usr/local/bin folder"
  mkdir -p /usr/local/bin
  sudo stow -vv --dir=./link/common --target="/usr/local/bin" --adopt usr-local-bin || echo_red "Failed to stow usr-local-bin"
  git restore ./link/common/usr-local-bin
}

# backup
stow_packages

exit 0
