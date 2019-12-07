#!/bin/bash

# source and export helper functions to be used by the rest of this script
set -a
source ./load-zsh-autoload-as-functions.sh
set +a

PLATFORM_SPECIFIC_GLOB=$(is_macos && echo 'macos-*.sh' || echo 'ubuntu-*.sh') 
SELECTED_SCRIPT=$(rg ./scripts --files \
                     -g 'common-*.sh' \
                     -g ${PLATFORM_SPECIFIC_GLOB} |
                 fzf)
${SELECTED_SCRIPT}
             
