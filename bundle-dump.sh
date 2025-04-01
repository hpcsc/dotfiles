#!/bin/sh

echo "=== Generating Brewfile"
brew bundle dump --force --no-vscode
echo "=== Brewfile generated"
