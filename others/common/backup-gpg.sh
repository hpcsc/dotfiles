#!/bin/bash

set -euo pipefail

OUT_FOLDER=./tmp/gpg
rm -rf ${OUT_FOLDER} && mkdir -p ${OUT_FOLDER}

echo "=== going to back up following keys"
gpg --list-secret-keys --keyid-format LONG

echo "=== backing up public keys"
gpg --export --export-options backup --output ${OUT_FOLDER}/public.gpg

echo "=== backing up private keys"
gpg --export-secret-keys --export-options backup --output ${OUT_FOLDER}/private.gpg

echo "=== backing up trust relationships"
gpg --export-ownertrust > ${OUT_FOLDER}/trust.gpg

ls -la ${OUT_FOLDER}
