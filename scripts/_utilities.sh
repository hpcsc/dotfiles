#!/bin/bash
# Utility functions for installation scripts
# Ported from zsh autoload functions for bash compatibility

# Color definitions
export PURPLE='\033[1;35m'
export BLUE='\033[0;34m'
export RED='\033[0;31m'
export CYAN='\033[0;36m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export NC='\033[0m'

# Echo with color
echo_with_color() {
  local COLOR=$1
  shift
  echo -e "${COLOR}$@${NC}"
}

# Colored echo functions
echo_blue() {
  echo_with_color "${BLUE}" "$@"
}

echo_red() {
  echo_with_color "${RED}" "$@"
}

echo_cyan() {
  echo_with_color "${CYAN}" "$@"
}

echo_green() {
  echo_with_color "${GREEN}" "$@"
}

echo_purple() {
  echo_with_color "${PURPLE}" "$@"
}

echo_yellow() {
  echo_with_color "${YELLOW}" "$@"
}

# Get distribution name
distro_name() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "$NAME"
  elif command -v lsb_release >/dev/null 2>&1; then
    echo "$(lsb_release -si)"
  elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    echo "$DISTRIB_ID"
  elif [ -f /etc/debian_version ]; then
    echo 'Debian'
  elif [ -f /etc/SuSe-release ]; then
    echo 'SuSe'
  elif [ -f /etc/redhat-release ]; then
    echo 'Redhat'
  else
    echo "$(uname -s)"
  fi
}

# Check OS functions
is_macos() {
  [[ "$(distro_name)" = "Darwin" ]] || return 1
}

is_ubuntu() {
  [[ "$(distro_name)" = "Ubuntu" ]] || return 1
}

is_fedora() {
  [[ "$(distro_name)" == *"Fedora"* ]] || return 1
}

# Confirm functions
confirm_no() {
  local message="$@"
  read -p "$message (yN): " confirm_install
  if [ "$confirm_install" != "" ] && 
     [ "$confirm_install" != "n" ] && 
     [ "$confirm_install" != "N" ]; then
     return 1
  else
     return 0
  fi
}
