#!/bin/bash

set -e

source ~/.asdf/asdf.sh

asdf plugin-list | grep python >/dev/null 2>&1 || {
  echo_red "=== ASDF (python plugin) must be installed before executing this script"
  exit 1
}

# install Python tools, this must be after asdf setup since it's dependent on Python
echo_yellow "=== Installing essential Python tools"
AWSUME_SKIP_ALIAS_SETUP=true \
    pip3 install --upgrade -r ./python-requirements.txt
