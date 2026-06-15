#!/usr/bin/env bash

# Session manager for workmux worktrees across every repo (not just the current
# one). Bound to Prefix + S in ~/.tmux.conf. The top-level menu lets you jump to,
# create, or delete a session. "Sessions" here are one of two kinds:
#
#   worktree  a workmux worktree. The menu opens each worktree as a tmux window
#             in the current session (overriding workmux's global session mode),
#             with the window named "<repo>-<name>" so handles stay unique and
#             readable across repos.
#   nvim      a plain tmux session opened on a repo's main checkout with no
#             worktree behind it, tagged with @wmm_kind so this menu can find it.
#
# Creating a session prompts for a repo, a name, and whether to open neovim in a
# new worktree or in the repo's main checkout.

# A tmux key binding runs this with the server's environment, which lacks the
# interactive shell's mise activation — add the shim dir so workmux/fzf/jq/git
# resolve the same way they do in a normal shell.
export PATH="$HOME/.local/share/mise/shims:$HOME/.fzf/bin:/opt/homebrew/bin:$PATH"

# Repos live one level under these roots.
PROJECT_ROOTS=("$HOME/Workspace/Code" "$HOME/Personal/Code")

# ----------------------------------------------------------------------------
# Listing
# ----------------------------------------------------------------------------

# Emit every workmux worktree under PROJECT_ROOTS as:
#   worktree <TAB> session <TAB> repo <TAB> branch <TAB> is_open <TAB> dirty <TAB> path <TAB> root
# Only repos that actually have linked worktrees (a non-empty .git/worktrees)
# pay the cost of a workmux invocation, so scanning many repos stays cheap.
list_worktrees_all() {
    local root repo
    for root in "${PROJECT_ROOTS[@]}"; do
        [[ -d "$root" ]] || continue
        while IFS= read -r repo; do
            [[ -d "$repo/.git/worktrees" ]] || continue
            [[ -n "$(ls -A "$repo/.git/worktrees" 2>/dev/null)" ]] || continue
            (
                cd "$repo" 2>/dev/null || exit 0
                workmux list --json 2>/dev/null | jq -r --arg fallback "$repo" '
                    ( [ .[] | select(.is_main) | .path ] | first ) as $rp0
                    | ( $rp0 // ($fallback | rtrimstr("/")) ) as $rp
                    | ( $rp | split("/") | last ) as $reponame
                    | .[]
                    | select(.is_main | not)
                    | [ "worktree", .handle, $reponame, .branch,
                        (.is_open | tostring), (.has_uncommitted_changes | tostring),
                        .path, $rp ] | @tsv'
            )
        done < <(fd --max-depth 1 --type d . "$root" 2>/dev/null)
    done
}

# Emit this menu's plain neovim sessions in the same TSV shape. They are tagged
# with @wmm_kind at creation; dirtiness is read from the repo's main checkout.
list_nvim_sessions() {
    tmux list-sessions -F '#{session_name}|#{@wmm_kind}|#{@wmm_root}' 2>/dev/null \
        | while IFS='|' read -r sname kind root; do
            [[ "$kind" == "nvim" ]] || continue
            local reponame dirty
            reponame="$(basename "$root")"
            if [[ -n "$(git -C "$root" status --porcelain 2>/dev/null)" ]]; then
                dirty=true
            else
                dirty=false
            fi
            printf 'nvim\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$sname" "$reponame" "" "true" "$dirty" "$root" "$root"
        done
}

list_all() {
    { list_worktrees_all; list_nvim_sessions; } | sort -t$'\t' -k2
}

# ----------------------------------------------------------------------------
# Shared helpers
# ----------------------------------------------------------------------------

pick_project() {
    fd --max-depth 1 --type d . "${PROJECT_ROOTS[@]}" 2>/dev/null \
        | fzf --reverse --prompt="Repository: "
}

attach_or_switch() {
    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "=$1"
    else
        exec tmux attach-session -t "=$1"
    fi
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

# Build a worktree off the latest default branch and open it as a single-pane
# nvim window in the current session.
add_worktree() {
    local branch="$1" session="$2"
    # The session that hosts the new window. Resolve it from tmux rather than
    # passing --parent-session to workmux: workmux lowercases that value, so a
    # capitalised session like "Work" would spawn a detached "work" holder
    # session instead of reusing the attached one. With no --parent-session,
    # workmux adds the window to the current session, which resolves correctly
    # from both this popup and the run-shell jump path.
    local parent
    parent="$(tmux display-message -p '#{session_name}')"
    # Open the worktree as a window in the current session (overriding workmux's
    # global session mode) with plain shells (-C) rather than the agent panes.
    local add_args=( "$branch" --name "$session" --mode window -C )

    local base base_commit
    base="$(default_branch)"
    if [[ -n "$base" ]]; then
        echo "Fetching latest origin/$base…"
        git fetch origin "$base" 2>/dev/null
        # Base off the commit, not the remote branch, so the new branch doesn't
        # adopt origin/$base as its upstream.
        base_commit="$(git rev-parse --verify --quiet "origin/$base^{commit}" \
                    || git rev-parse --verify --quiet "$base^{commit}")"
        [[ -n "$base_commit" ]] && add_args+=( --base "$base_commit" )
    fi

    if ! workmux add "${add_args[@]}"; then
        echo; read -rn1 -p "workmux add failed — press any key…"
        return
    fi

    # Collapse the configured split to a single pane, then type `nvim .` into it
    # so quitting nvim drops to a shell instead of killing the window.
    local target="${parent}:${session}.{top-left}"
    tmux kill-pane -a -t "$target" 2>/dev/null
    tmux send-keys -t "$target" 'nvim .' Enter
}

create_nvim_only() {
    local session="$1" dir="$2"
    if ! tmux has-session -t "=$session" 2>/dev/null; then
        tmux new-session -d -s "$session" -c "$dir"
        # Tag so list/delete can recognise it; there is no worktree behind it.
        # set-option/send-keys resolve -t as a pane target, where the "=" exact
        # prefix fails to match — use the bare session name here.
        tmux set-option -t "$session" @wmm_kind nvim
        tmux set-option -t "$session" @wmm_root "$dir"
        # Typed into the shell (not run as the session command) so quitting nvim
        # drops to a shell instead of killing the session.
        tmux send-keys -t "$session" 'nvim .' Enter
    fi
    attach_or_switch "$session"
}

# ----------------------------------------------------------------------------
# Re-entry points — menu items call back into this script so PATH is set the
# same way for the commands they run.
# ----------------------------------------------------------------------------

case "$1" in
    # Jump: open the worktree's session (creates it if closed, switches if open)
    # or switch to the plain nvim session.
    --open)
        client="$2"; kind="$3"; session="$4"; path="$5"; root="$6"
        if [[ "$kind" == "nvim" ]]; then
            tmux switch-client -c "$client" -t "=$session"
        else
            cd "$path" 2>/dev/null || cd "$root" 2>/dev/null || exit 0
            # No --parent-session: workmux lowercases it and would spawn a
            # detached holder session. With just --mode window it reopens the
            # window in the current session and switches the client to it.
            exec workmux open "$session" --mode window
        fi
        ;;

    # Create: pick a repo, name it, choose how to start it.
    --new)
        client="$2"
        dir="$(pick_project)"
        [[ -z "$dir" ]] && exit 0
        dir="${dir%/}"

        # tmux session names cannot contain "." or ":".
        repo_san="$(basename "$dir" | tr '.:' '__')"
        # No "read -i" prefill: macOS bash 3.2 doesn't support it.
        read -e -p "Name (session will be ${repo_san}-…): " name
        [[ -z "$name" ]] && exit 0
        name_san="$(printf '%s' "$name" | tr ' .:/' '____')"
        session="${repo_san}-${name_san}"

        choice="$(printf '%s\n' \
            'worktree — nvim in a new worktree (default)' \
            'no worktree — nvim at repo root' \
            | fzf --reverse --no-sort --height=40% --prompt='Start with: ')"
        [[ -z "$choice" ]] && exit 0

        cd "$dir" 2>/dev/null || exit 0
        case "$choice" in
            worktree*)      add_worktree "$name_san" "$session" ;;
            'no worktree'*) create_nvim_only "$session" "$dir" ;;
        esac
        exit 0
        ;;

    # Remove: workmux confirms and refuses on uncommitted changes (its prompt is
    # the safety gate). Killing a plain nvim session is confirmed here.
    --delete)
        kind="$2"; session="$3"; root="$4"
        if [[ "$kind" == "nvim" ]]; then
            read -rn1 -p "Kill nvim session '$session'? [y/N] " ans; echo
            [[ "$ans" == "y" || "$ans" == "Y" ]] && tmux kill-session -t "=$session"
        else
            cd "$root" 2>/dev/null || exit 0
            workmux remove "$session"
            echo; read -rn1 -p "press any key…"
        fi
        exit 0
        ;;

    # Submenu of sessions to delete, each opening a confirmation popup.
    --delete-menu)
        client="$2"
        menu=()
        key=1
        while IFS=$'\t' read -r kind session repo branch is_open dirty path root; do
            [[ -z "$kind" ]] && continue
            [[ "$dirty" == "true" ]] && dirty_mark=" #[fg=yellow]*#[default]" || dirty_mark=""
            [[ "$kind" == "nvim" ]] && tag="#[fg=magenta]nvim#[default]" || tag="#[fg=blue]${branch}#[default]"
            label="${session}  ${tag}${dirty_mark}"
            menu+=( "$label" "$key" \
                    "display-popup -E -w 70% -h 50% -T ' Delete Session ' \"$0 --delete '$kind' '$session' '$root'\"" )
            [[ "$key" =~ ^[1-9]$ ]] && key=$((key + 1)) || key=""
        done < <(list_all)
        [[ ${#menu[@]} -eq 0 ]] && exit 0
        tmux display-menu -c "$client" -x C -y C -T " Delete which session? " "${menu[@]}"
        exit 0
        ;;
esac

# ----------------------------------------------------------------------------
# Top-level menu (entered from the key binding with the client name as $1).
# ----------------------------------------------------------------------------

client="$1"

menu=()
key=1
while IFS=$'\t' read -r kind session repo branch is_open dirty path root; do
    [[ -z "$kind" ]] && continue

    [[ "$is_open" == "true" ]] && open_mark="#[fg=green]●#[default] " || open_mark="  "
    [[ "$dirty" == "true" ]] && dirty_mark=" #[fg=yellow]*#[default]" || dirty_mark=""
    [[ "$kind" == "nvim" ]] && tag="#[fg=magenta]nvim#[default]" || tag="#[fg=blue]${branch}#[default]"

    label="${open_mark}${session}  ${tag}${dirty_mark}"

    # Single quotes guard paths/handles against word splitting; they never
    # contain a single quote (handles are sanitized; worktrees and project roots
    # live under workmux/home dirs that have none).
    menu+=( "$label" "$key" "run-shell \"$0 --open '$client' '$kind' '$session' '$path' '$root'\"" )

    [[ "$key" =~ ^[1-9]$ ]] && key=$((key + 1)) || key=""
done < <(list_all)

have_sessions=$([[ ${#menu[@]} -gt 0 ]] && echo 1)

# Divider above the actions, but only when sessions precede it — a leading
# separator as the first item would be misread by display-menu's flag parser.
[[ -n "$have_sessions" ]] && menu+=( "" )

# A roomy popup so the repo picker, prompt, and workmux's create output fit.
menu+=( "#[fg=cyan]+#[default] New session…" "n" \
        "display-popup -E -w 80% -h 70% -T ' New Session ' \"$0 --new '$client'\"" )

[[ -n "$have_sessions" ]] && menu+=( "#[fg=red]x#[default] Delete session…" "d" \
        "run-shell \"$0 --delete-menu '$client'\"" )

tmux display-menu -c "$client" -x C -y C -T " Workmux Sessions " "${menu[@]}"
