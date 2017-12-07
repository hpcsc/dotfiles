#!/bin/bash

function install() {
    plugin=$1

    echo "=== Availble $plugin version for asdf:"
    asdf list-all $plugin
    read -p "=== Choose version to install:" install_version
    if [ "$install_version" != "" ]; then
        asdf install $plugin $install_version
        asdf global $plugin $install_version
    fi
}

asdf_version=$(curl https://api.github.com/repos/asdf-vm/asdf/tags | jq -r '.[0].name')
echo "=== Checking out asdf at tag $asdf_version"
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch $asdf_version

source ~/.asdf/asdf.sh
source ~/.asdf/completions/asdf.bash

# nodejs plugin for asdf
asdf plugin-add nodejs https://github.com/asdf-vm/asdf-nodejs.git
bash ~/.asdf/plugins/nodejs/bin/import-release-team-keyring # Imports Node.js release team's OpenPGP keys to main keyring
install 'nodejs'

# ruby plugin for asdf
asdf plugin-add ruby https://github.com/asdf-vm/asdf-ruby.git
install 'ruby'

# golang plugin for asdf
asdf plugin-add golang https://github.com/kennyp/asdf-golang.git
install 'golang'
