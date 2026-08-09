#!/bin/bash

# Dependencies: mise (common-mise.sh), mise-global (common-mise-global.sh)
# The Claude Code binary is self-contained and does not require Node.js, but the
# gopls shim it is pointed at afterwards comes from mise-global.
#
# The gopls settings are applied imperatively rather than stowed because both
# live in files that also hold machine-specific state: the MCP server belongs to
# ~/.claude.json, which carries the oauth account and per-project history, and
# the plugin toggle belongs to ~/.claude/settings.json, which on a work machine
# also carries private marketplaces and a credential-export command. Both steps
# below only add their own key and leave every other key on the machine alone.

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
  CLAUDE_BIN="$HOME/.local/bin/claude"
fi

if [ ! -x "$CLAUDE_BIN" ]; then
  echo_red "=== claude not found at $CLAUDE_BIN, skipping gopls setup"
  exit 0
fi

GOPLS_SHIM="$HOME/.local/share/mise/shims/gopls"
if [ ! -x "$GOPLS_SHIM" ]; then
  echo_red "=== gopls shim not found at $GOPLS_SHIM, skipping (run mise-global first)"
  exit 0
fi

echo_yellow "=== Registering gopls MCP server at user scope"
"$CLAUDE_BIN" mcp remove gopls -s user >/dev/null 2>&1 || true
"$CLAUDE_BIN" mcp add gopls -s user -- "$GOPLS_SHIM" mcp
echo_green "Registered gopls MCP server"

echo_yellow "=== Enabling gopls-lsp plugin"
if "$CLAUDE_BIN" plugin enable gopls-lsp@claude-plugins-official -s user >/dev/null 2>&1; then
  echo_green "Enabled gopls-lsp plugin"
else
  echo_green "gopls-lsp plugin already enabled"
fi
