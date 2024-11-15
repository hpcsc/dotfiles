#!/bin/bash

set -e


if [ -f ~/.local/bin/mise ]; then
    echo_green "=== mise exists, skip installation"
else
    echo_yellow "=== Installing mise"
    curl https://mise.run | sh
fi
