#!/bin/bash

set -e

is_fedora || exit 0

FASD_VERSION=1.0.1

(command -v fasd >/dev/null 2>&1 && echo_green "=== fasd is already installed, skipped") || {
  echo_yellow "=== Installing fasd"

  curl -L https://github.com/clvv/fasd/archive/${FASD_VERSION}.tar.gz | tar xvzf - -C /tmp

  pushd /tmp/fasd-${FASD_VERSION}

  make install

  popd
}
