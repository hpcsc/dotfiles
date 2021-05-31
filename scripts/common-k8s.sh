#!/bin/bash

set -euo pipefail

KUBECTX_PATH=${HOME}/kubectx
[ -d "${KUBECTX_PATH}" ] && {
  echo_green "=== kubectx is already installed, updating"
  git -C "${KUBECTX_PATH}" pull -r
} || {
  echo_yellow "=== Cloning kubectx repository to ${KUBECTX_PATH}"
  git clone https://github.com/ahmetb/kubectx "${KUBECTX_PATH}"
}

if [ ! -f /usr/local/bin/kubectx ]; then
  sudo ln -vs ${KUBECTX_PATH}/kubectx /usr/local/bin/kubectx
fi

if [ ! -f /usr/local/bin/kubens ]; then
  sudo ln -vs ${KUBECTX_PATH}/kubens /usr/local/bin/kubens
fi
