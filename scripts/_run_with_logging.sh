#!/bin/bash

# Run a script with logging
# Usage: _run_with_logging.sh <script_path>
# Set DRY_RUN=1 to just print task name without running

SCRIPT_PATH="$1"

if [ -z "$SCRIPT_PATH" ]; then
  echo "Error: No script path provided" >&2
  exit 1
fi

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Error: Script not found: $SCRIPT_PATH" >&2
  exit 1
fi

# Extract script name without path and .sh extension
# e.g., "scripts/ubuntu-install-sudo.sh" -> "ubuntu-install-sudo"
LOG_NAME=$(basename "$SCRIPT_PATH" .sh)

# Dry-run mode: just print task name
if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "$LOG_NAME"
  exit 0
fi

if [ -z "$LOG_DIR" ]; then
  echo "Error: LOG_DIR environment variable not set" >&2
  exit 1
fi

# Calculate LOG_PATH by finding the most recent log directory
LOG_PATH=$(ls "$LOG_DIR" | sort | tail -1 | xargs -I{} echo "$LOG_DIR"/{})
echo "Logging to directory: $LOG_PATH"

LOG_FILE="${LOG_PATH}/${LOG_NAME}.log"

# Run script using 'script' command to capture output while preserving TTY
# macOS and Linux use different syntax for the script command
set +e
if [[ "$(uname)" == "Darwin" ]]; then
  script -q "$LOG_FILE" bash "$SCRIPT_PATH"
else
  script -q -c "bash \"$SCRIPT_PATH\"" "$LOG_FILE"
fi
EXIT_CODE=$?
set -e

# Append OK, PARTIAL, or FAIL at the end
if [ $EXIT_CODE -eq 0 ]; then
  # Check for partial failures (scripts that completed but had some failures)
  # Patterns indicating partial failures from scripts that use || echo_red
  if grep -qi "Failed to install\|Failed to configure\|Failed to set up\|Failed to stow" "$LOG_FILE"; then
    echo "PARTIAL" >> "$LOG_FILE"
  else
    echo "OK" >> "$LOG_FILE"
  fi
else
  echo "FAIL" >> "$LOG_FILE"
fi

exit $EXIT_CODE
