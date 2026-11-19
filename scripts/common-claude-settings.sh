#!/bin/bash

# Dependencies: mise-global (common-mise-global.sh) for jq
# This script merges common-claude-settings.json into ~/.claude/settings.json.
# Note: settings.json is not stowed, because Claude Code writes to it.

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

SETTINGS_FILE="$HOME/.claude/settings.json"
SHARED_FILE="$SCRIPT_DIR/common-claude-settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  echo '{}' > "$SETTINGS_FILE"
fi

# jq's * replaces arrays, which drops the permission entries that only this machine has
MERGED="$(jq -s --arg home "$HOME" '
  def expand_home: if startswith("~/") then $home + ltrimstr("~") else . end;
  .[0] as $local
  | (.[1] | if .permissions.additionalDirectories then .permissions.additionalDirectories |= map(expand_home) else . end) as $shared
  | reduce ("allow", "ask", "deny", "additionalDirectories") as $key
      ($local * $shared;
       if ($local.permissions[$key] or $shared.permissions[$key]) then
         .permissions[$key] = (($local.permissions[$key] // []) + ($shared.permissions[$key] // []) | unique)
       else
         .
       end)
' "$SETTINGS_FILE" "$SHARED_FILE")"

printf '%s\n' "$MERGED" > "$SETTINGS_FILE"
echo_green "=== Merged $SHARED_FILE into $SETTINGS_FILE"
