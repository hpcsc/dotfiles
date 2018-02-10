#!/bin/bash

set -e

is_macos || exit 0

command -v brew >/dev/null 2>&1 || {
  echo_yellow "=== Installing homebrew"
  /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
}
