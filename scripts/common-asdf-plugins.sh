#!/bin/bash

set -e

function install() {
    plugin=$1

    echo_green "=== Install latest version of ${plugin}"
    asdf install ${plugin} latest && \
    asdf global ${plugin} $(asdf latest ${plugin})
}

source ~/.asdf/asdf.sh

for line in $(cat ./.asdf-plugins); do
  IFS=',' read -ra plugin_config <<< "${line}"
  plugin="${plugin_config[0]}"
  plugin_repo="${plugin_config[1]}"

  [ -z "$(asdf plugin-list | grep ${plugin})" ] && {
    echo_green "=== Add plugin ${plugin} ${plugin_repo}"
    asdf plugin-add ${plugin} ${plugin_repo} 
    install ${plugin}
  } || {
    echo_green "=== Plugin ${plugin} exists, updating to latest version"
    asdf plugin-update ${plugin}
  }
done
