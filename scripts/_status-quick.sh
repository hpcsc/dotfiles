#!/bin/bash

# Quick status summary (one line)
export PATH="${PATH}:$(pwd)/bin"

# Detect OS from log files
detect_os_from_logs() {
  local log_path="$1"

  if ls "$log_path"/ubuntu-* &>/dev/null; then
    echo "ubuntu"
  elif ls "$log_path"/macos-* &>/dev/null; then
    echo "macos"
  elif ls "$log_path"/fedora-* &>/dev/null; then
    echo "fedora"
  else
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

  DRY_RUN=1 task -s "default-$os" 2>&1 | sort -u
}

if [ -d "${LOG_DIR}" ]; then
  LATEST_LOG=$(ls "$LOG_DIR" 2>/dev/null | grep -v "dry-run" | sort | tail -1)

  if [ -z "$LATEST_LOG" ]; then
    echo "No installation logs found"
    exit 0
  fi

  LOG_PATH="${LOG_DIR}/${LATEST_LOG}"

  # Detect OS from log files
  DETECTED_OS=$(detect_os_from_logs "$LOG_PATH")

  # Get expected tasks based on detected OS
  EXPECTED_TASKS=($(get_expected_tasks "$DETECTED_OS"))

  SUCCESS=0
  PARTIAL=0
  FAILED=0
  PENDING=0

  # Check each expected task
  for task_name in "${EXPECTED_TASKS[@]}"; do
    log_file="${LOG_PATH}/${task_name}.log"

    if [ -f "$log_file" ]; then
      last_line=$(tail -1 "$log_file" 2>/dev/null)
      case "$last_line" in
        "OK") SUCCESS=$((SUCCESS + 1)) ;;
        "PARTIAL") PARTIAL=$((PARTIAL + 1)) ;;
        "FAIL") FAILED=$((FAILED + 1)) ;;
        *) PENDING=$((PENDING + 1)) ;;
      esac
    else
      PENDING=$((PENDING + 1))
    fi
  done

  if [ $FAILED -gt 0 ]; then
    echo -e "\033[31m✗ ${LATEST_LOG}: ${SUCCESS}✓ ${PARTIAL}⚠ ${FAILED}✗ ${PENDING}○\033[0m"
  elif [ $PARTIAL -gt 0 ]; then
    echo -e "\033[33m⚠ ${LATEST_LOG}: ${SUCCESS}✓ ${PARTIAL}⚠ ${FAILED}✗ ${PENDING}○\033[0m"
  elif [ $PENDING -gt 0 ]; then
    echo -e "\033[90m○ ${LATEST_LOG}: ${SUCCESS}✓ ${PARTIAL}⚠ ${FAILED}✗ ${PENDING}○\033[0m"
  else
    echo -e "\033[32m✓ ${LATEST_LOG}: ${SUCCESS}✓ ${PARTIAL}⚠ ${FAILED}✗ ${PENDING}○\033[0m"
  fi
else
  echo "No logs found"
fi
