#!/bin/sh

echo "=== Generating Brewfile"
brew bundle dump --force
echo "=== Brewfile generated"
