#!/bin/bash

set -e

echo_yellow "=============================  VimPlug Update ============================"

# install VimPlug plugins, this must be after asdf setup since fzf plugin is dependent on Go SDK
vim +PlugInstall +qall
