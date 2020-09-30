#!/bin/bash

set -e

is_fedora || exit 0

for i in findutils @development-tools grubby zlib-devel sqlite-devel bzip2-devel openssl-devel libffi-devel; do
  echo_yellow "=== Installing $i"
  sudo dnf install -y $i || echo_red "=== Failed to install $i"
done
