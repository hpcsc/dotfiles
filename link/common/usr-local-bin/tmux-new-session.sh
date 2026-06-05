#!/usr/bin/env bash

# Safely capture the absolute path to this script file
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

create_session() {
    local name="$1"
    
    # Do nothing if the string is empty
    [[ -z "$name" ]] && exit 0

    if [[ -n "$TMUX" ]]; then
        # Inside an existing tmux environment
        if tmux has-session -t "$name" 2>/dev/null; then
            tmux switch-client -t "$name"
        else
            tmux new-session -d -s "$name"
            tmux switch-client -t "$name"
        fi
    else
        # Direct terminal run from outside tmux
        exec tmux new-session -A -s "$name"
    fi
}

# Catch the argument payload passed from the popup window
if [[ "$1" == "--create" && -n "$2" ]]; then
    create_session "$2"
    exit 0
fi

# MAIN EXECUTION FLOW
if [[ -n "$TMUX" ]]; then
    # INSIDE TMUX: Run with -c and clean un-nested single quotes to force immediate exit
    tmux display-popup -E -w 40 -h 5 -T " New Tmux Session " bash -c '
        read -p "Session Name: " session_name
        bash "'"$SCRIPT_PATH"'" --create "$session_name"
    '
else
    # OUTSIDE TMUX: Prompt naturally in standard terminal
    read -p "Enter new tmux session name: " session_name
    create_session "$session_name"
fi
