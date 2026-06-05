#!/usr/bin/env bash

# Safely capture the absolute path to this script file
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# A tmux popup inherits the server's environment, which may lack fzf/fd
export PATH="$HOME/.fzf/bin:/opt/homebrew/bin:$PATH"

PROJECT_ROOTS=("$HOME/Workspace/Code" "$HOME/Personal/Code")

pick_project() {
    fd --max-depth 1 --type d . "${PROJECT_ROOTS[@]}" | fzf --reverse --prompt="Project: "
}

attach_or_switch() {
    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$1"
    else
        exec tmux attach-session -t "$1"
    fi
}

create_session() {
    local name="$1" dir="$2"

    [[ -z "$name" ]] && exit 0

    # "=" forces an exact match; bare names match by prefix
    if ! tmux has-session -t "=$name" 2>/dev/null; then
        tmux new-session -d -s "$name" -c "$dir"
        # Typed into the shell (rather than run as the session's initial
        # command) so quitting nvim drops to a shell instead of killing
        # the session, and nvim resolves via the interactive shell's PATH
        tmux send-keys -t "$name" 'nvim .' Enter
    fi
    attach_or_switch "$name"
}

prompt_and_create() {
    local dir name default

    dir="$(pick_project)"
    [[ -z "$dir" ]] && exit 0

    # tmux session names cannot contain "." or ":"
    default="$(basename "$dir" | tr '.:' '__')"
    # No "read -i" prefill: macOS bash 3.2 doesn't support it
    read -e -p "Session Name [$default]: " name
    create_session "${name:-$default}" "$dir"
}

# Re-entry point for the popup window
if [[ "$1" == "--prompt" ]]; then
    prompt_and_create
    exit 0
fi

# MAIN EXECUTION FLOW
if [[ -n "$TMUX" ]]; then
    tmux display-popup -E -w 70% -h 60% -T " New Tmux Session " bash -c "bash '$SCRIPT_PATH' --prompt"
else
    # Direct terminal run from outside tmux
    prompt_and_create
fi
