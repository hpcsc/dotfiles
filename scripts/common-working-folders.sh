#!/bin/bash


# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

echo_yellow "=== Creating working folders"
mkdir -p ~/Workspace/Code
mkdir -p ~/Personal/Code
mkdir -p ~/Tools
