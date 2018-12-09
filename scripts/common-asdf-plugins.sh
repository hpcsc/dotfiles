#!/bin/bash

set -e

function install() {
    plugin=$1

    echo_green "=== Availble $plugin version for asdf:"
    asdf list-all $plugin

    read -p "=== [$plugin] Choose version to install (leave empty to skip):" install_version
    if [ "$install_version" != "" ]; then
        asdf install $plugin $install_version && \
        asdf global $plugin $install_version
    fi
}

function install_nodejs() {
  # nodejs plugin for asdf
  ((asdf plugin-list | grep nodejs >/dev/null 2>&1) && echo_green "=== ASDF Nodejs plugin is already installed, skipped") || {
    asdf plugin-add nodejs https://github.com/asdf-vm/asdf-nodejs.git
    bash ~/.asdf/plugins/nodejs/bin/import-release-team-keyring # Imports Node.js release team's OpenPGP keys to main keyring
    install 'nodejs' || {
      echo_red "=== Failed to install asdf nodejs"
      exit 1
    }
  }
}

function install_ruby() {
  # ruby plugin for asdf
  ((asdf plugin-list | grep ruby >/dev/null 2>&1) && echo_green "=== ASDF Ruby plugin is already installed, skipped") || {
    asdf plugin-add ruby https://github.com/asdf-vm/asdf-ruby.git
    install 'ruby' || {
      echo_red "=== Failed to install asdf ruby"
      exit 1
    }
  }
}

function install_python() {
  # python plugin for asdf
  ((asdf plugin-list | grep python >/dev/null 2>&1) && echo_green "=== ASDF Python plugin is already installed, skipped") || {
    asdf plugin-add python https://github.com/tuvistavie/asdf-python.git
    asdf list-all python
    install 'python' || {
      echo_red "=== Failed to install asdf python"
      exit 1
    }
  }
}

source ~/.asdf/asdf.sh

plugin_to_install=$1

case ${plugin_to_install} in
	"nodejs")
	install_nodejs
  ;;
	"ruby")
	install_ruby
  ;;
	"python")
	install_python
  ;;
	*)
  echo "Not supported plugin ${plugin_to_install}"
  ;;
esac

