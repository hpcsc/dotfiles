#!/bin/bash

set -e

is_fedora || exit 0

(command -v docker >/dev/null 2>&1 && echo_green "=== Docker is already installed, skipped") || {
  echo_yellow "=== Installing Docker CE"
  sudo dnf -y install dnf-plugins-core
  sudo dnf config-manager \
    --add-repo \
    https://download.docker.com/linux/fedora/docker-ce.repo
  sudo dnf install -y docker-ce docker-ce-cli containerd.io

  echo_yellow "=== Enable backward compatibility for cgroups"
  sudo grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=0"

  # add current user to docker group, to solve permission issue in ubuntu
  sudo usermod -a -G docker $(id -un)
}
