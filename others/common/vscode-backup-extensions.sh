#!/bin/bash


command -v code >/dev/null 2>&1 || {
    echo "=== VSCode executable is not in Path"
    exit 1
}

echo "=== Writing VSCode extension list to ./others/macos/vscode/extensions"
rm -f ./others/macos/vscode/extensions
code --list-extensions > ./others/macos/vscode/extensions
echo "=== VSCode extension list written"

