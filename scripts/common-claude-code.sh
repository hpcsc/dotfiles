#!/bin/bash

# The Claude Code binary is self-contained and does not require Node.js.
#
# Neither half of the gopls integration is configured here, deliberately. Each
# session runs its own gopls, which watches the whole workspace, and on macOS
# kqueue costs one file descriptor per watched path -- a ~12k-file monorepo runs
# about 28k descriptors per session against a default kern.maxfiles of 122880.
# Four such sessions exhaust the system file table, which surfaces as unrelated
# apps failing rather than as anything pointing at Go. Opt in per repo instead,
# where the workspace is small enough to be worth it:
#   cd <repo> && claude mcp add gopls -- "$HOME/.local/share/mise/shims/gopls" mcp
#   cd <repo> && claude plugin enable gopls-lsp@claude-plugins-official -s local

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

if CLAUDE_BIN="$(command -v claude 2>/dev/null)"; then
  echo_green "=== Claude Code exists, updating"
  "$CLAUDE_BIN" update
else
  echo_yellow "=== Installing Claude Code (native binary)"
  curl -fsSL https://claude.ai/install.sh | bash
fi
