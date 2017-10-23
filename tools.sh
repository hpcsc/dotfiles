#!/bin/sh

command -v code >/dev/null 2>&1 || {
    echo "VSCode executable is not in Path, creating symlink from /usr/local/bin/code -> /Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
    sudo ln -s "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" /usr/local/bin/code
}

echo "===========================  VSCode Extensions ==========================="

while read extension; do
    code --install-extension $extension
done <vscode-extensions
