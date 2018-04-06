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

(command -v asdf >/dev/null 2>&1 && echo_green "=== ASDF is already installed, skipped") || {
  asdf_version=$(curl https://api.github.com/repos/asdf-vm/asdf/tags | jq -r '.[0].name')
  echo_yellow "=== Checking out asdf at tag $asdf_version"
  git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch $asdf_version || {
    echo_red "=== Failed to install asdf"
    exit 1
  }
}

source ~/.asdf/asdf.sh
source ~/.asdf/completions/asdf.bash

exit_code=0

# nodejs plugin for asdf
((asdf plugin-list | grep nodejs >/dev/null 2>&1) && echo_green "=== ASDF Nodejs plugin is already installed, skipped") || {
  asdf plugin-add nodejs https://github.com/asdf-vm/asdf-nodejs.git
  bash ~/.asdf/plugins/nodejs/bin/import-release-team-keyring # Imports Node.js release team's OpenPGP keys to main keyring
  install 'nodejs' || {
    echo_red "=== Failed to install asdf nodejs"
    exit_code=1
  }
}

# ruby plugin for asdf
((asdf plugin-list | grep ruby >/dev/null 2>&1) && echo_green "=== ASDF Ruby plugin is already installed, skipped") || {
  asdf plugin-add ruby https://github.com/asdf-vm/asdf-ruby.git
  install 'ruby' || {
    echo_red "=== Failed to install asdf ruby"
    exit_code=1
  }
}

# golang plugin for asdf
((asdf plugin-list | grep golang >/dev/null 2>&1) && echo_green "=== ASDF Golang plugin is already installed, skipped") || {
  asdf plugin-add golang https://github.com/kennyp/asdf-golang.git
  install 'golang' || {
    echo_red "=== Failed to install asdf golang"
    exit_code=1
  }
}

# python plugin for asdf
((asdf plugin-list | grep python >/dev/null 2>&1) && echo_green "=== ASDF Python plugin is already installed, skipped") || {
  asdf plugin-add python https://github.com/tuvistavie/asdf-python.git
  install 'python' || {
    echo_red "=== Failed to install asdf python"
    exit_code=1
  }
}

exit $exit_code
