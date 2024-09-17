#!/bin/bash

# to be used when git commands intermittently fail due to network/firewall/VPN
# to set this up:
# 1. set ssh connect timeout to lower value, e.g.
# ```
# Host *
#   ConnectTimeout 1
# ```
# 2. change git ssh command to use this wrapper script
# ```
# git config --global core.sshCommand $HOME/.local/bin/ssh-with-retry.sh
# ```
MAX_RETRIES=3
RETRY_DELAY=2

echo_red() {
    echo -e "\033[0;31m$@\033[0m"
}

echo_green() {
    echo -e "\033[0;32m$@\033[0m"
}

attempt=0
while [ ${attempt} -lt ${MAX_RETRIES} ];
do
    ssh "$@"
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        if [ ${attempt} -neq 0 ]; then
            echo_green "Connection succeeded after ${attempt} attempts"
        fi
        exit 0
    fi
    attempt=$((attempt+1))
    echo_red "Connection failed. Retrying in ${RETRY_DELAY} seconds... (Attempt ${attempt} of ${MAX_RETRIES})"
    sleep ${RETRY_DELAY}
done

echo_red "Failed to connect after ${MAX_RETRIES} attempts."
exit $exit_code
