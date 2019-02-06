#!/bin/bash

set -e

function install() {
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
    install 'python' || {
      echo_red "=== Failed to install asdf python"
      exit 1
    }
  }
}

function install_kubectl() {
  # kubectl plugin for asdf
  ((asdf plugin-list | grep kubectl >/dev/null 2>&1) && echo_green "=== ASDF kubectl plugin is already installed, skipped") || {
    asdf plugin-add kubectl https://github.com/Banno/asdf-kubectl.git
    install 'kubectl' || {
      echo_red "=== Failed to install asdf kubectl"
      exit 1
    }
  }
}

function install_helm() {
  # helm plugin for asdf
  ((asdf plugin-list | grep helm >/dev/null 2>&1) && echo_green "=== ASDF helm plugin is already installed, skipped") || {
    asdf plugin-add helm https://github.com/Antiarchitect/asdf-helm.git
    install 'helm' || {
      echo_red "=== Failed to install asdf helm"
      exit 1
    }
  }
}

source ~/.asdf/asdf.sh

plugin_to_install=$1

case ${plugin_to_install} in
	"nodejs"|"ruby"|"python"|"kubectl"|"helm")
	install_${plugin_to_install}
  ;;
	*)
  echo "Not supported plugin ${plugin_to_install}"
  ;;
esac

