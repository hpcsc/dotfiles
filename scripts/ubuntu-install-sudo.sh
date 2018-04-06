#!/bin/bash

set -e

is_ubuntu || exit 0

command -v sudo >/dev/null 2>&1 || {
    echo_blue "=== No sudo available, installing sudo"
    apt-get update && apt-get install -y sudo
}
