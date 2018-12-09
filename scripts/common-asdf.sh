#!/bin/bash

set -e

([ -d ~/.asdf ] && echo_green "=== ASDF is already installed, skipped") || {
  asdf_version=$(curl https://api.github.com/repos/asdf-vm/asdf/tags | jq -r '.[0].name')
  echo_yellow "=== Checking out asdf at tag $asdf_version"
  git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch $asdf_version || {
    echo_red "=== Failed to install asdf"
    exit 1
  }
}

# python plugin for asdf
source ~/.asdf/asdf.sh

((asdf plugin-list | grep python >/dev/null 2>&1) && echo_green "=== ASDF Python plugin is already installed, skipped") || {
  asdf plugin-add python https://github.com/tuvistavie/asdf-python.git
  latest_python_version=$(asdf list-all python | grep -e '^3\.\d\.\d$' | sort | tail -n 1)
  asdf install python ${latest_python_version} && \
  asdf global python ${latest_python_version} || {
    echo_red "=== Failed to install asdf python version ${latest_python_version}"
    exit 1
  }
}


exit 0
