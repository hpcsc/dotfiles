#!/bin/bash

set -e

ZPREZTO_DIR="${ZDOTDIR:-$HOME}/.zprezto"

if [ -d "${ZPREZTO_DIR}" ]; then
  echo_yellow "=== Updating Prezto"
  pushd "${ZDOTDIR:-$HOME}/.zprezto"
  git pull
  git submodule update --init --recursive
  popd
else
  echo_yellow "=== Installing Prezto"
  git clone --recursive https://github.com/sorin-ionescu/prezto.git ${ZPREZTO_DIR}
fi;
