#!/bin/bash

set -euo pipefail

echo_yellow "=== Installing essential Python tools for Python@$(which python)"
AWSUME_SKIP_ALIAS_SETUP=true \
    ~/.local/bin/mise exec python -- pip3 install --upgrade -r ./python-requirements.txt
