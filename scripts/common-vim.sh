#!/bin/bash

set -e

echo_yellow "=== Installing Vim plugins"

# install VimPlug plugins, this must be after mise setup since fzf plugin is dependent on Go SDK
vim +PlugInstall +qall
