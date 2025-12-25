#!/bin/bash

# Run a script with logging
# Usage: _run_with_logging.sh <script_path>

SCRIPT_PATH="$1"

if [ -z "$SCRIPT_PATH" ]; then
  echo "Error: No script path provided" >&2
  exit 1
fi

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Error: Script not found: $SCRIPT_PATH" >&2
  exit 1
fi

if [ -z "$LOG_DIR" ]; then
  echo "Error: LOG_DIR environment variable not set" >&2
  exit 1
fi

# Calculate LOG_PATH by finding the most recent log directory
LOG_PATH=$(ls "$LOG_DIR" | sort | tail -1 | xargs -I{} echo "$LOG_DIR"/{})
echo "Logging to directory: $LOG_PATH"

# Extract script name without path and .sh extension
# e.g., "scripts/ubuntu-install-sudo.sh" -> "install-sudo"
SCRIPT_FILENAME=$(basename "$SCRIPT_PATH" .sh)

# Remove platform prefix if present
# e.g., "ubuntu-install-sudo" -> "install-sudo"
# e.g., "common-vim" -> "vim"
LOG_NAME=$(echo "$SCRIPT_FILENAME" | sed -E 's/^(ubuntu|macos|fedora|common)-//')

LOG_FILE="${LOG_PATH}/${LOG_NAME}.log"

# Run script using 'script' command to capture output while preserving TTY
set +e
script -q -c "bash \"$SCRIPT_PATH\"" "$LOG_FILE"
EXIT_CODE=$?
set -e

# Append OK or FAIL at the end
if [ $EXIT_CODE -eq 0 ]; then
  echo "OK" >> "$LOG_FILE"
else
  echo "FAIL" >> "$LOG_FILE"
fi

exit $EXIT_CODE
