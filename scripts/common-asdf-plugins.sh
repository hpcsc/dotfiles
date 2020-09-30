#!/bin/bash

set -e

function install() {
    plugin=$1

    echo_green "=== Install latest version of ${plugin}"
    asdf install ${plugin} latest && \
    asdf global ${plugin} $(asdf latest ${plugin})
}

source ~/.asdf/asdf.sh

for plugin in $(cat ./.asdf-plugins); do
  [ -z "$(asdf plugin-list | grep ${plugin})" ] &&
    asdf plugin-add ${plugin} ||
    asdf plugin-update ${plugin}

  install ${plugin}
done
