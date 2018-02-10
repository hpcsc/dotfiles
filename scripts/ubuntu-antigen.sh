#!/bin/bash

set -e

is_ubuntu || exit

echo_yellow "=============================  Antigen ==================================="

[ -f /usr/share/antigen/antigen.zsh ] >/dev/null 2>&1 || {
  sudo sh -c 'mkdir -p /usr/share/antigen && curl -L git.io/antigen > /usr/share/antigen/antigen.zsh'
}
