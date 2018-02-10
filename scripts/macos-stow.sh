#!/bin/bash

set -e

is_macos || exit 0

echo_yellow "================================  Stow ==================================="

# create symlink at home directory for these packages
ruby ./backup_and_stow.rb
