#!/bin/bash

set -e

sudo apt-get update && apt-get install -y tilix && dconf load /com/gexperts/Tilix/ < ~/dotfiles/others/ubuntu/tilix.dconf
