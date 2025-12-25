#!/bin/bash

# Show installation progress and status

export PATH="${PATH}:$(pwd)/bin"

# Detect OS from log files
detect_os_from_logs() {
  local log_path="$1"

  # Check for platform-specific prefixes in log files
  if ls "$log_path"/ubuntu-* &>/dev/null; then
    echo "ubuntu"
  elif ls "$log_path"/macos-* &>/dev/null; then
    echo "macos"
  elif ls "$log_path"/fedora-* &>/dev/null; then
    echo "fedora"
  else
    # Fallback to current OS if no platform-specific files found
    if [[ "$(uname -s)" == "Darwin" ]]; then
      echo "macos"
    elif grep -q 'Ubuntu' /etc/os-release 2>/dev/null; then
      echo "ubuntu"
    elif grep -q 'Fedora' /etc/os-release 2>/dev/null; then
      echo "fedora"
    else
      echo "unknown"
    fi
  fi
}

# Get expected tasks by running in dry-run mode
get_expected_tasks() {
  local os="$1"

  # Run appropriate default task in dry-run mode and filter task names
  DRY_RUN=1 task -s "default-$os" 2>&1 | sort -u
}

if [ ! -d "${LOG_DIR}" ]; then
  echo "No logs directory found. Run 'task up' first."
  exit 1
fi

# Find most recent log directory (exclude dry-run directories)
LATEST_LOG=$(ls "$LOG_DIR" 2>/dev/null | grep -v "dry-run" | sort | tail -1)

if [ -z "$LATEST_LOG" ]; then
  echo "No installation logs found."
  exit 1
fi

LOG_PATH="${LOG_DIR}/${LATEST_LOG}"

# Detect OS from log files
DETECTED_OS=$(detect_os_from_logs "$LOG_PATH")

echo "Installation status for: ${LATEST_LOG} (detected: ${DETECTED_OS})"
echo ""

# Get expected tasks based on detected OS
EXPECTED_TASKS=($(get_expected_tasks "$DETECTED_OS"))

# Initialize categories
SUCCESS=""
FAILED=""
PARTIAL=""
PENDING=""

# Check each expected task
for task_name in "${EXPECTED_TASKS[@]}"; do
  log_file="${LOG_PATH}/${task_name}.log"

  if [ -f "$log_file" ]; then
    last_line=$(tail -1 "$log_file" 2>/dev/null)
    case "$last_line" in
      "OK") SUCCESS="${SUCCESS} ${task_name}" ;;
      "FAIL") FAILED="${FAILED} ${task_name}" ;;
      "PARTIAL") PARTIAL="${PARTIAL} ${task_name}" ;;
      *) PENDING="${PENDING} ${task_name}" ;;
    esac
  else
    PENDING="${PENDING} ${task_name}"
  fi
done

# Count tasks
SUCCESS_COUNT=$(echo $SUCCESS | wc -w | tr -d ' ')
FAILED_COUNT=$(echo $FAILED | wc -w | tr -d ' ')
PARTIAL_COUNT=$(echo $PARTIAL | wc -w | tr -d ' ')
PENDING_COUNT=$(echo $PENDING | wc -w | tr -d ' ')

# Sort and display
if [ "$SUCCESS_COUNT" -gt 0 ]; then
  echo -e "\033[32m✓ SUCCESS (${SUCCESS_COUNT}):\033[0m"
  echo $SUCCESS | tr ' ' '\n' | sort
fi

if [ "$PARTIAL_COUNT" -gt 0 ]; then
  echo -e "\033[33m⚠ PARTIAL (${PARTIAL_COUNT}):\033[0m"
  echo $PARTIAL | tr ' ' '\n' | sort
fi

if [ "$FAILED_COUNT" -gt 0 ]; then
  echo -e "\033[31m✗ FAILED (${FAILED_COUNT}):\033[0m"
  echo $FAILED | tr ' ' '\n' | sort
fi

if [ "$PENDING_COUNT" -gt 0 ]; then
  echo -e "\033[90m○ PENDING (${PENDING_COUNT}):\033[0m"
  echo $PENDING | tr ' ' '\n' | sort
fi

echo ""
echo "Total: $(( SUCCESS_COUNT + PARTIAL_COUNT + FAILED_COUNT + PENDING_COUNT )) tasks"
echo "Expected: ${#EXPECTED_TASKS[@]} tasks"
echo "View logs: ${LOG_PATH}"

# Show details for partial and failed tasks
if [ "$PARTIAL_COUNT" -gt 0 ] || [ "$FAILED_COUNT" -gt 0 ]; then
  echo ""
  read -p "View partial/failed logs? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    TASKS_TO_VIEW=$(echo ${PARTIAL} ${FAILED} | tr ' ' '\n' | sort)
    for task in $TASKS_TO_VIEW; do
      echo ""
      echo -e "\033[33m=== ${task}.log ===\033[0m"
      tail -30 "${LOG_PATH}/${task}.log"
      read -p "Press Enter to continue..." </dev/tty
    done
  fi
fi
