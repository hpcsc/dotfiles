#!/bin/bash

set -e

function install() {
    # TODO: replace by asdf install plugin latest
    plugin=$1

    echo_green "=== Availble $plugin version for asdf:"
    asdf list-all $plugin
    wait

    read -p "=== [$plugin] Choose version to install (leave empty to skip):" install_version
    if [ "$install_version" != "" ]; then
        asdf install $plugin $install_version && \
        asdf global $plugin $install_version
    fi
}

source ~/.asdf/asdf.sh

for plugin in $(cat ./.asdf-plugins); do
  [ -z "$(asdf plugin-list | grep ${plugin})" ] &&
    asdf plugin-add ${plugin} ||
    asdf plugin-update ${plugin}

  install ${plugin}
done
