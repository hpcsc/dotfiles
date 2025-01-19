#!/bin/bash

set -e

# must be installed before mise since mise installs some tools (yazi) using cargo

if (command -v rustup >/dev/null 2>&1) then
   echo_green "=== Rustup exists, updating"
   rustup self update
   rustup update stable
else
   echo_green "=== Installing rustup"
   curl https://sh.rustup.rs -sSf | sh
fi;

echo_green "=== Installing/Updating Rust language server"
rustup component add rls rust-analysis rust-src

echo_green "=== Installing/Updating Rust additional tools"
rustup component add rustfmt clippy
