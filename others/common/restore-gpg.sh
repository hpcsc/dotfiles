#!/bin/bash

set -euo pipefail

INPUT_FOLDER=${1}

gpg --import ${INPUT_FOLDER}/public.gpg
gpg --import ${INPUT_FOLDER}/private.gpg
gpg --import-ownertrust ${INPUT_FOLDER}/trust.gpg

gpg --list-secret-keys --keyid-format LONG
