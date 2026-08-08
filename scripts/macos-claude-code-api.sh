#!/bin/bash

# Store Claude Code API key in macOS keychain and optionally configure settings.json
# Run this on-demand: ./scripts/macos-claude-code-api.sh

set -e

KEYCHAIN_ACCOUNT="claude-code"
KEYCHAIN_SERVICE="claude-code-api-key"
SETTINGS_FILE="$HOME/.claude/settings.json"
API_HELPER="$HOME/.claude/api-key-helper"

echo "=== Claude Code API Key Setup ==="
echo ""

echo -n "Enter your Claude API key: "
read -r -s API_KEY
echo ""

if [ -z "$API_KEY" ]; then
    echo "Error: API key cannot be empty" >&2
    exit 1
fi

security add-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w "$API_KEY" -U
echo "API key stored in macOS keychain."

if RETRIEVED=$(security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null); then
    if [ "$RETRIEVED" = "$API_KEY" ]; then
        echo "Retrieval verified."
    else
        echo "Error: stored key does not match" >&2
        exit 1
    fi
else
    echo "Error: could not retrieve stored key" >&2
    exit 1
fi

if [ ! -x "$API_HELPER" ]; then
    echo "Warning: $API_HELPER not found or not executable (run stow first)" >&2
fi

if [ -f "$SETTINGS_FILE" ]; then
    echo ""
    echo -n "Configure ~/.claude/settings.json to use apiKeyHelper? [Y/n] "
    read -r CONFIGURE
    if [ "$CONFIGURE" != "n" ] && [ "$CONFIGURE" != "N" ]; then
        jq --arg helper "$API_HELPER" '.apiKeyHelper = $helper' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && /bin/mv -f "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        echo "apiKeyHelper configured in $SETTINGS_FILE"
    else
        echo "Skipping. Add this to ~/.claude/settings.json:"
        echo '  "apiKeyHelper": "'"$API_HELPER"'"'
    fi
else
    echo ""
    echo "$SETTINGS_FILE does not exist yet. Add this to it:"
    echo '  "apiKeyHelper": "'"$API_HELPER"'"'
fi

echo ""
echo "Done."
