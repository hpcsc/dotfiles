#!/usr/bin/env bash

# Show a tmux context menu of the current repo's workmux worktrees: jump to an
# existing one, create a new one, or delete one. Bound to Prefix + W in
# ~/.tmux.conf.

# A tmux key binding runs this with the server's environment, which lacks the
# interactive shell's mise activation — add the shim dir so workmux/jq resolve.
export PATH="$HOME/.local/share/mise/shims:/opt/homebrew/bin:$PATH"

# Non-main worktrees as: handle <TAB> branch <TAB> is_open <TAB> dirty <TAB> path
list_worktrees() {
    workmux list --json 2>/dev/null \
        | jq -r '.[] | select(.is_main | not)
                 | [.handle, .branch, (.is_open|tostring), (.has_uncommitted_changes|tostring), .path]
                 | @tsv'
}

# Filesystem path of the main worktree — a safe CWD for create/remove that is
# never the worktree being removed.
repo_root() {
    workmux list --json 2>/dev/null | jq -r 'first(.[] | select(.is_main) | .path)'
}

# Repo's default branch, mirroring the `gnb` helper: origin/HEAD, falling back
# to origin/main, origin/master, then a local main/master. Empty if none found.
default_branch() {
    local b
    b="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
    b="${b#origin/}"
    if [[ -z "$b" ]]; then
        local c
        for c in main master; do
            if git show-ref --verify --quiet "refs/remotes/origin/$c" \
            || git show-ref --verify --quiet "refs/heads/$c"; then
                b="$c"
                break
            fi
        done
    fi
    printf '%s' "$b"
}

# Menu items call back into this script (re-entry points) so PATH is set the
# same way for the workmux commands they run.
case "$1" in
    # Jump: workmux open creates the window/session if closed, or switches to it
    # if already open — mode-agnostic.
    --open)
        cd "$2" 2>/dev/null || exit 0
        exec workmux open "$3"
        ;;
    # Create: prompt for a branch name, then build the worktree + window off the
    # latest default branch (fetch first), regardless of which worktree the menu
    # was opened from.
    --add)
        cd "$2" 2>/dev/null || exit 0
        # No "read -i" prefill: macOS bash 3.2 doesn't support it
        read -e -p "New worktree branch name: " name
        [[ -z "$name" ]] && exit 0

        add_args=( "$name" )
        base="$(default_branch)"
        if [[ -n "$base" ]]; then
            echo "Fetching latest origin/$base…"
            git fetch origin "$base" 2>/dev/null
            # Base off the commit, not the remote branch, so the new worktree's
            # branch doesn't adopt origin/$base as its upstream.
            base_commit="$(git rev-parse --verify --quiet "origin/$base^{commit}" \
                        || git rev-parse --verify --quiet "$base^{commit}")"
            [[ -n "$base_commit" ]] && add_args+=( --base "$base_commit" )
        fi

        workmux add "${add_args[@]}" || { echo; read -rn1 -p "workmux add failed — press any key…"; }
        exit 0
        ;;
    # Remove: workmux confirms and refuses on uncommitted changes unless forced,
    # so its built-in prompt is the safety gate. Run from the main worktree.
    --delete)
        cd "$2" 2>/dev/null || exit 0
        workmux remove "$3"
        echo; read -rn1 -p "press any key…"
        exit 0
        ;;
    # Submenu of worktrees to delete, each opening a confirmation popup.
    --delete-menu)
        client="$2"
        cd "$3" 2>/dev/null || exit 0
        root="$(repo_root)"
        menu=()
        key=1
        while IFS=$'\t' read -r handle branch is_open dirty path; do
            [[ -z "$handle" ]] && continue
            [[ "$dirty" == "true" ]] && dirty_mark=" #[fg=yellow]*#[default]" || dirty_mark=""
            label="${handle}  #[fg=blue]${branch}#[default]${dirty_mark}"
            menu+=( "$label" "$key" \
                    "display-popup -E -w 70% -h 50% -T ' Delete Worktree ' \"$0 --delete '$root' '$handle'\"" )
            [[ "$key" =~ ^[1-9]$ ]] && key=$((key + 1)) || key=""
        done < <(list_worktrees)
        [[ ${#menu[@]} -eq 0 ]] && exit 0
        tmux display-menu -c "$client" -x C -y C -T " Delete which worktree? " "${menu[@]}"
        exit 0
        ;;
esac

client="$1"
cwd="$2"

cd "$cwd" 2>/dev/null || exit 0

menu=()
key=1
while IFS=$'\t' read -r handle branch is_open dirty path; do
    [[ -z "$handle" ]] && continue

    [[ "$is_open" == "true" ]] && open_mark="#[fg=green]●#[default] " || open_mark="  "
    [[ "$dirty" == "true" ]] && dirty_mark=" #[fg=yellow]*#[default]" || dirty_mark=""

    label="${open_mark}${handle}  #[fg=blue]${branch}#[default]${dirty_mark}"

    # Single quotes guard paths/handles against word splitting; they never
    # contain a single quote (handles are sanitized, worktrees live under
    # workmux-managed dirs).
    menu+=( "$label" "$key" "run-shell \"$0 --open '$path' '$handle'\"" )

    [[ "$key" =~ ^[1-9]$ ]] && key=$((key + 1)) || key=""
done < <(list_worktrees)

have_worktrees=$([[ ${#menu[@]} -gt 0 ]] && echo 1)

# Divider above the actions, but only when worktrees precede it — a leading "-"
# or separator as the first item would be misread by display-menu's flag parser.
[[ -n "$have_worktrees" ]] && menu+=( "" )

# A roomy popup so workmux's create output (hooks, agent boot) stays visible.
menu+=( "#[fg=cyan]+#[default] New worktree…" "n" \
        "display-popup -E -w 70% -h 60% -T ' New Workmux Worktree ' \"$0 --add '$cwd'\"" )

# Delete is only meaningful once a worktree exists.
[[ -n "$have_worktrees" ]] && menu+=( "#[fg=red]x#[default] Delete worktree…" "d" \
        "run-shell \"$0 --delete-menu '$client' '$cwd'\"" )

tmux display-menu -c "$client" -x C -y C -T " Workmux Worktrees " "${menu[@]}"
