#!/bin/bash

set -euo pipefail

KEY_PATH="$@"

if [ -z "${KEY_PATH}" ]; then
    echo "Path to GPG key file is required"
    echo "Usage: $0 path-to-gpg-key-file"
    exit 1
fi

IMPORT_OUTPUT=$(gpg --import "${KEY_PATH}" 2>&1)
KEY_ID=$(echo "${IMPORT_OUTPUT}" | grep ": secret key" | sed 's/gpg: key \(.*\):.*/\1/')

echo "=== Imported key with id ${KEY_ID}"

gpg --edit-key ${KEY_ID} trust quit

echo "=== Key with signature"

gpg --list-signatures ${KEY_ID}
