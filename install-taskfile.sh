#!/bin/bash
set -e

detect_platform() {
  local os=$(uname -s | tr '[:upper:]' '[:lower:]')
  local arch=$(uname -m)

  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
  esac
  
  echo "$os $arch"
}

validate_platform() {
  local os=$1
  local arch=$2

  case "$os/$arch" in
    darwin/amd64|darwin/arm64|linux/amd64|linux/arm64) ;;
    *)
      echo "Unsupported platform: $os/$arch (only darwin and linux supported)"
      exit 1
      ;;
  esac
}

check_task_exists() {
  local bindir=$1

  if [ -x "$bindir/task" ]; then
    echo "task already exists at $bindir/task, skipping installation"
    exit 0
  fi
}

install_curl_if_needed() {
  local os=$1

  if [ "$os" = "linux" ] && ! command -v curl >/dev/null 2>&1; then
    echo "curl not found, installing..."
    if command -v apt-get >/dev/null 2>&1; then
      if command -v sudo >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y curl
      else
        apt-get update && apt-get install -y curl
      fi
    elif command -v yum >/dev/null 2>&1; then
      yum install -y curl
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y curl
    else
      echo "Cannot install curl: no known package manager found"
      exit 1
    fi
  fi
}

get_latest_tag() {
  curl -sL -H "Accept: application/json" "https://github.com/go-task/task/releases/latest" | sed -n 's/.*"tag_name":"\([^"]*\)".*/\1/p'
}

install_task() {
  local tag=$1
  local os=$2
  local arch=$3
  local bindir="./bin"
  local github_download="https://github.com/go-task/task/releases/download"

  mkdir -p "$bindir"

  local name="task_${os}_${arch}"
  local tarball_url="${github_download}/${tag}/${name}.tar.gz"

  echo "Installing task $tag for $os/$arch..."
  echo "Downloading $tarball_url ..."
  curl -sL "$tarball_url" | tar -xz -C "$bindir" --no-same-owner task
  chmod +x "$bindir/task"

  echo "Installed $bindir/task"
}

read -r OS ARCH <<< "$(detect_platform)"
validate_platform "$OS" "$ARCH"
install_curl_if_needed "$OS"

TAG=${1:-latest}
if [ "$TAG" = "latest" ]; then
  TAG=$(get_latest_tag)
fi

check_task_exists "./bin"
install_task "$TAG" "$OS" "$ARCH"
