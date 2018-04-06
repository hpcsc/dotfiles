#!/bin/bash

set -e

is_ubuntu || exit 0

([ -f /usr/share/antigen/antigen.zsh ] >/dev/null 2>&1 && echo_green "=== Antigen is already installed, skipped") || {
  echo_yellow "=== Installing Antigen"
  sudo sh -c 'mkdir -p /usr/share/antigen && curl -L git.io/antigen > /usr/share/antigen/antigen.zsh'
}
