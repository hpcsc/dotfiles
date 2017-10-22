#!/bin/sh

echo "===========================  VSCode Extensions ==========================="

while read extension; do
    code --install-extension $extension
done <vscode-extensions
