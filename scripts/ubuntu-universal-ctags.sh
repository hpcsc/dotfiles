#!/bin/bash

set -e

(command -v ctags >/dev/null 2>&1 && echo_green "=== ctags is already installed, skipped") || {
    sudo apt-get install -y autoconf pkg-config
    rm -rf ctags && git clone https://github.com/universal-ctags/ctags.git
    cd ctags
    ./autogen.sh
    ./configure
    make
    sudo make install
    cd .. && rm -rf ctags
}
