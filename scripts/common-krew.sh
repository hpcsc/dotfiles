#!/bin/bash

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
