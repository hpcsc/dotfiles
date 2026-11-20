#!/bin/bash

# Dependencies: macos-brew-bundle.sh (installs docker and docker-compose)
# This script lets the docker CLI find the Homebrew Compose plugin, so that
# `docker compose` works. Homebrew installs the plugin in a folder that docker
# does not search (see `brew info docker-compose`).

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

is_macos || exit 0

echo_yellow "=== Linking the Docker Compose plugin into ~/.docker/cli-plugins"

plugin="$(brew --prefix)/lib/docker/cli-plugins/docker-compose"

if [[ ! -x "$plugin" ]]; then
  echo_red "No Compose plugin at $plugin. Run macos-brew-bundle.sh first."
  exit 1
fi

mkdir -p "$HOME/.docker/cli-plugins"
ln -sfn "$plugin" "$HOME/.docker/cli-plugins/docker-compose"

docker compose version
