#!/bin/bash

# Dependencies: none
# Claude Code native binary installer - follows the same pattern as common-rust.sh and common-mise.sh
# The binary is self-contained and does not require Node.js

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

if command -v claude >/dev/null 2>&1; then
    echo_green "=== Claude Code exists, updating"
    claude update
else
    echo_yellow "=== Installing Claude Code (native binary)"
    curl -fsSL https://claude.ai/install.sh | bash
fi
