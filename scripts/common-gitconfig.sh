#!/bin/bash

# This script creates ~/.gitconfig-personal and ~/.gitconfig-work, which the stowed ~/.gitconfig includes.
# Note: you set the work email by hand and it stays out of the repo, so the script never changes a file that exists.

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_utilities.sh"
set -e

EMAIL_PLACEHOLDER="REPLACE_WITH_WORK_EMAIL"

create_gitconfig() {
  local file="$1"
  local ssh_key="$2"
  local email="$3"

  if [ -e "$file" ]; then
    echo_green "=== $file exists, not changed"
  else
    cat > "$file" <<EOF
[core]
	sshCommand = ssh -i ~/.ssh/${ssh_key}
[user]
	name = David Nguyen
	email = ${email}
	signingkey = ~/.ssh/${ssh_key}.pub
[gpg]
	format = ssh
[gpg "ssh"]
	allowedSignersFile = ~/.git_allowed_signers
EOF
    echo_green "=== Created $file"
  fi

  if [ "$(git config -f "$file" user.email)" = "$EMAIL_PLACEHOLDER" ]; then
    echo_yellow "=== Set user.email in $file: git accepts the placeholder and commits with it"
  fi
}

create_gitconfig "$HOME/.gitconfig-personal" "id_ed25519.hpcsc" "hpcsc@users.noreply.github.com"
create_gitconfig "$HOME/.gitconfig-work" "id_ed25519" "$EMAIL_PLACEHOLDER"
