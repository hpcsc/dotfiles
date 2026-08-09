#!/bin/bash

# Dependencies: mise (common-mise.sh), mise-global (common-mise-global.sh)
# Requires the claude binary and the gopls shim from mise-global.
#
# These two settings are applied imperatively rather than stowed because both
# live in files that also hold machine-specific state: the MCP server belongs to
# ~/.claude.json, which carries the oauth account and per-project history, and
# the plugin toggle belongs to ~/.claude/settings.json, which on a work machine
# also carries private marketplaces and a credential-export command. Both steps
# below only add their own key and leave every other key on the machine alone.

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

if ! command -v claude >/dev/null 2>&1; then
  echo_red "=== claude not found, skipping Claude Go setup"
  exit 0
fi

GOPLS_SHIM="$HOME/.local/share/mise/shims/gopls"
if [ ! -x "$GOPLS_SHIM" ]; then
  echo_red "=== gopls shim not found at $GOPLS_SHIM, skipping (run mise-global first)"
  exit 0
fi

echo_yellow "=== Registering gopls MCP server at user scope"
claude mcp remove gopls -s user >/dev/null 2>&1 || true
claude mcp add gopls -s user -- "$GOPLS_SHIM" mcp
echo_green "Registered gopls MCP server"

echo_yellow "=== Enabling gopls-lsp plugin"
if claude plugin enable gopls-lsp@claude-plugins-official -s user >/dev/null 2>&1; then
  echo_green "Enabled gopls-lsp plugin"
else
  echo_green "gopls-lsp plugin already enabled"
fi
