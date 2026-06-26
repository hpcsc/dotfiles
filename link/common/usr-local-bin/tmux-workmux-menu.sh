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
# Creating a session shows a single-screen form (workmux-new-form, built from
# tools/workmux-new-form) to pick the repo, name it, choose a worktree vs. the
# repo's main checkout, and whether to open it as a tmux window (in the current
# session) or its own tmux session. A no-worktree window is a quick editor
# window and is not tracked by this menu; the other three are.

# A tmux key binding runs this with the server's environment, which can lack the
# interactive shell's PATH. The mise shim dir (workmux/jq/fd) and ~/.local/bin
# (workmux-new-form) are needed on every platform; /opt/homebrew/bin supplies
# tmux/git on macOS (on Linux they come from /usr/bin, already on PATH), added
# only when present.
_prefix="$HOME/.local/share/mise/shims:$HOME/.local/bin"
[[ -d /opt/homebrew/bin ]] && _prefix="$_prefix:/opt/homebrew/bin"
export PATH="$_prefix:$PATH"
unset _prefix

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
# nvim target. $3 is the workmux multiplexer mode: "window" puts it in the
# current session, "session" gives the worktree its own tmux session.
add_worktree() {
    local branch="$1" session="$2" mux="$3"
    local parent
    parent="$(tmux display-message -p '#{session_name}')"
    # Plain shells (-C) instead of the agent panes. Resolve the host session
    # from tmux rather than passing --parent-session, which workmux lowercases
    # (a capitalised "Work" would spawn a detached "work" holder session).
    local add_args=( "$branch" --name "$session" --mode "$mux" -C )

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

    # Collapse the configured split to a single pane and type `nvim .` so
    # quitting nvim drops to a shell. In window mode the worktree is a window in
    # the current session; in session mode it is its own session named after the
    # handle, so the pane target differs.
    local target
    if [[ "$mux" == "session" ]]; then
        target="${session}:.{top-left}"
    else
        target="${parent}:${session}.{top-left}"
    fi
    tmux kill-pane -a -t "$target" 2>/dev/null
    tmux send-keys -t "$target" 'nvim .' Enter

    # workmux switches the client to a new window automatically; for a new
    # session switch to it so creating lands you inside it.
    [[ "$mux" == "session" ]] && attach_or_switch "$session"
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

# A quick nvim window on a repo's main checkout, in the current session. Unlike
# create_nvim_only there is no @wmm tag and no worktree, so this menu does not
# track it — close the window to dismiss it.
create_nvim_window() {
    local name="$1" dir="$2"
    local parent
    parent="$(tmux display-message -p '#{session_name}')"
    tmux new-window -t "$parent" -n "$name" -c "$dir"
    tmux send-keys -t "${parent}:${name}" 'nvim .' Enter
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
        # A worktree already living in its own tmux session (it was created in
        # session mode) is named after its handle, so switch the client to it.
        # Reopening it instead would make workmux tear that session down and
        # re-materialize the worktree as a window in the current session. Plain
        # nvim sessions are always reached the same way.
        if [[ "$kind" == "nvim" ]] || tmux has-session -t "=$session" 2>/dev/null; then
            tmux switch-client -c "$client" -t "=$session"
        else
            cd "$path" 2>/dev/null || cd "$root" 2>/dev/null || exit 0
            # No --parent-session: workmux lowercases it and would spawn a
            # detached holder session. With just --mode window it reopens the
            # window in the current session and switches the client to it.
            exec workmux open "$session" --mode window
        fi
        ;;

    # Create: show the single-screen form, then open the selection. The form
    # prints "<dir>\t<name>\t<worktree:yes|no>\t<mode:window|session>"; an abort
    # or empty name yields no output.
    --new)
        client="$2"
        repos=()
        while IFS= read -r r; do repos+=("$r"); done \
            < <(fd --max-depth 1 --type d . "${PROJECT_ROOTS[@]}" 2>/dev/null)
        [[ ${#repos[@]} -eq 0 ]] && exit 0

        sel="$(workmux-new-form "${repos[@]}")" || exit 0
        [[ -z "$sel" ]] && exit 0
        IFS=$'\t' read -r dir name worktree mux <<< "$sel"
        [[ -z "$dir" || -z "$name" ]] && exit 0
        dir="${dir%/}"

        # tmux session/window names cannot contain "." or ":".
        repo_san="$(basename "$dir" | tr '.:' '__')"
        name_san="$(printf '%s' "$name" | tr ' .:/' '____')"
        session="${repo_san}-${name_san}"

        cd "$dir" 2>/dev/null || exit 0
        case "$worktree/$mux" in
            yes/window)  add_worktree "$name_san" "$session" window ;;
            yes/session) add_worktree "$name_san" "$session" session ;;
            no/window)   create_nvim_window "$session" "$dir" ;;
            no/session)  create_nvim_only "$session" "$dir" ;;
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

# A roomy popup so the form and workmux's create output fit.
menu+=( "#[fg=cyan]+#[default] New session…" "n" \
        "display-popup -E -w 80% -h 70% -T ' New Session ' \"$0 --new '$client'\"" )

[[ -n "$have_sessions" ]] && menu+=( "#[fg=red]x#[default] Delete session…" "d" \
        "run-shell \"$0 --delete-menu '$client'\"" )

tmux display-menu -c "$client" -x C -y C -T " Workmux Sessions " "${menu[@]}"
