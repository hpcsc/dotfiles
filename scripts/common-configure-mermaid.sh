#!/bin/bash

# Dependencies: mise (common-mise.sh), mise-global (common-mise-global.sh)
# This script requires ~/.local/bin/mise to provide npm:@mermaid-js/mermaid-cli
# Note: must be after mise-global, which installs mermaid-cli itself

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

# mmdc renders through puppeteer, which drives a headless Chrome it downloads in
# a postinstall hook. npm >= 11 blocks that hook by default (allow-scripts), so
# mermaid-cli installs "successfully" and then fails at first render with
# "Could not find chrome-headless-shell". Running the hook by hand is what makes
# the install complete; it is idempotent and skips browsers already present.
MMDC_BIN="$(~/.local/bin/mise --cd ~/ which mmdc 2>/dev/null || true)"
if [ -z "$MMDC_BIN" ]; then
  echo_red "=== mmdc not found, skipping puppeteer browser install"
  exit 0
fi

MERMAID_ROOT="$(dirname "$(dirname "$MMDC_BIN")")"
PUPPETEER_INSTALL="$MERMAID_ROOT/lib/node_modules/@mermaid-js/mermaid-cli/node_modules/puppeteer/install.mjs"

if [ ! -f "$PUPPETEER_INSTALL" ]; then
  echo_red "=== puppeteer install hook not found at $PUPPETEER_INSTALL"
  exit 0
fi

echo_yellow "=== Installing puppeteer browser for mermaid-cli"
~/.local/bin/mise --cd ~/ exec node -- node "$PUPPETEER_INSTALL"
echo_green "Installed puppeteer browser for mermaid-cli"
