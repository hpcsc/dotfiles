#!/bin/bash

# Dependencies: kubectl (installed by common-asdf-plugins.sh)
# This script requires kubectl to install plugins
# Note: Optional task - should be run after main installation

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

[ -d "$HOME/.krew" ] && {
  echo_green "=== krew is already installed, updating"
  ${HOME}/.krew/bin/kubectl-krew update
} || {
  set -x

  echo_yellow "=== Installing krew to manage kubectl plugins"

  cd "$(mktemp -d)"

  latest_release_version=$(curl https://api.github.com/repos/kubernetes-sigs/krew/releases/latest | jq -r '.tag_name')
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/download/${latest_release_version}/krew.{tar.gz,yaml}"

  tar zxvf krew.tar.gz

  KREW=./krew-"$(uname | tr '[:upper:]' '[:lower:]')_amd64"
  ${KREW} install --manifest=krew.yaml --archive=krew.tar.gz
  ${KREW} update
}

KREW_PLUGINS_LIST=./others/common/kube/krew-plugins
echo_yellow "=== Installing krew plugins from ${KREW_PLUGINS_LIST}"
# requires kubectl (installed by common-asdf-plugins.sh)
cat ${KREW_PLUGINS_LIST} | xargs ${HOME}/.krew/bin/kubectl-krew install
