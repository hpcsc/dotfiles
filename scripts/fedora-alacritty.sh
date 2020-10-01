#!/bin/bash

set -e

is_fedora || exit 0

sudo dnf copr enable pschyska/alacritty
sudo dnf install alacritty
