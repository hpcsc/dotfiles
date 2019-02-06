#!/bin/bash

set -e

( [ -d "$HOME/.krew" ] && echo_green "=== krew is already installed, skipped") || {
  set -x

  echo_yellow "=== Installing krew to manage kubectl plugins"

  cd "$(mktemp -d)"

  latest_release_version=$(curl https://api.github.com/repos/GoogleContainerTools/krew/releases/latest | jq -r '.tag_name')
  curl -fsSLO "https://storage.googleapis.com/krew/${latest_release_version}/krew.{tar.gz,yaml}"

  tar zxvf krew.tar.gz

  ./krew-"$(uname | tr '[:upper:]' '[:lower:]')_amd64" install --manifest=krew.yaml --archive=krew.tar.gz
}
