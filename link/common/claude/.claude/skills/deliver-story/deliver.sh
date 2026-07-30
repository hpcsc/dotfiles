#!/usr/bin/env bash
# deliver-story — the automated form of workmux-new-form, driven by a plan.yaml.
#
# Reads a decompose-to-prs delivery plan and, for every slice that is ready,
# creates a git worktree + tmux session via `workmux` and launches
# `implement-flow` inside it against that slice's task file. Independent slices
# fire in parallel (own worktree each); dependent slices wait for their
# prerequisites to merge (base: master) or stack on the prerequisite's branch
# (base: <slice-id>). Watch progress with `workmux dashboard`.
#
# Usage:
#   deliver.sh [PLAN] [--wave N] [--only id[,id...]] [--mode session|window] [--dry-run]
#
#   PLAN        path to plan.yaml (auto-discovered under tasks/ if a single one exists)
#   --wave N    only fire slices in wave N (default: every ready slice)
#   --only ids  comma-separated slice ids to restrict to
#   --mode      workmux target mode (default: window, falls back to session
#               when not running inside tmux)
#   --dry-run   print the workmux commands and status changes without running them
#
# Ready = status pending AND either (base is the default branch and every
# depends_on slice is merged) OR (base is a sibling slice whose branch carries
# commits of its own).
# A ready slice is launched and its status set to running. Before launching,
# running/in-review slices whose branch has merged into the default branch are
# advanced to merged (best-effort, no gh dependency), so the next wave unlocks.
#
# Each slice gets a single agent pane. The shared workmux config asks for an
# agent pane plus a shell pane below it; the extra pane is collapsed here rather
# than in that config, which every other workmux entry point still relies on.
set -euo pipefail

die() { printf 'deliver-story: %s\n' "$1" >&2; exit 1; }
say() { printf 'deliver-story: %s\n' "$1"; }

MODE=window
WAVE=""
ONLY=""
DRY=0
PLAN=""

while [ $# -gt 0 ]; do
  case "$1" in
    --wave)    WAVE="$2"; shift 2 ;;
    --only)    ONLY="$2"; shift 2 ;;
    --mode)    MODE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    --*)       die "unknown option: $1" ;;
    *)         PLAN="$1"; shift ;;
  esac
done

command -v workmux >/dev/null 2>&1 || die "workmux not found on PATH"
command -v yq      >/dev/null 2>&1 || die "yq not found on PATH"
command -v git     >/dev/null 2>&1 || die "git not found on PATH"

# Window mode puts each slice in a window of the session this runs from, so it
# needs a session to attach to. Resolve it from tmux rather than passing
# --parent-session, which workmux lowercases (a capitalised "Work" would spawn a
# detached "work" holder session).
PARENT=""
if [ "$MODE" = "window" ]; then
  PARENT=$(tmux display-message -p '#{session_name}' 2>/dev/null || true)
  if [ -z "$PARENT" ]; then
    say "not inside tmux — falling back to --mode session"
    MODE=session
  fi
fi

# Locate the plan: explicit arg, else the single tasks/**/plan.yaml under cwd.
if [ -z "$PLAN" ]; then
  count=0; found=""
  while IFS= read -r f; do found="$f"; count=$((count + 1)); done \
    < <(find tasks -name plan.yaml 2>/dev/null)
  [ "$count" -eq 1 ] || die "specify the plan.yaml path (found $count under tasks/)"
  PLAN="$found"
fi
[ -f "$PLAN" ] || die "plan not found: $PLAN"

MAIN_ROOT=$(git rev-parse --show-toplevel) || die "not in a git repo"
REPO=$(basename "$MAIN_ROOT")
STORY_SLUG=$(yq -r '.story_slug // ""' "$PLAN")
[ -n "$STORY_SLUG" ] || die "plan has no story_slug: $PLAN"

# Default branch: origin/HEAD, then a local main/master.
DEFAULT=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
[ -n "$DEFAULT" ] || DEFAULT=$(git branch --list main master | head -1 | tr -d ' *')
[ -n "$DEFAULT" ] || DEFAULT=master
git fetch --quiet origin "$DEFAULT" 2>/dev/null || true

status_of() { yq -r ".slices[] | select(.id==\"$1\") | .status" "$PLAN"; }
branch_of() { yq -r ".slices[] | select(.id==\"$1\") | .branch" "$PLAN"; }
is_slice()  { yq -e ".slices[] | select(.id==\"$1\")" "$PLAN" >/dev/null 2>&1; }
set_status() {
  if [ "$DRY" -eq 1 ]; then say "would set $1 -> $2"; return; fi
  yq -i "(.slices[] | select(.id==\"$1\").status) = \"$2\"" "$PLAN"
}

# Reconcile: advance running/in-review slices whose branch is now an ancestor of
# origin/DEFAULT (i.e. their PR merged) to merged, so dependents can unlock.
while IFS='|' read -r id branch status; do
  case "$status" in running|in-review) ;; *) continue ;; esac
  git rev-parse --verify --quiet "$branch" >/dev/null 2>&1 || continue
  # A branch that has not committed anything yet is trivially an ancestor of the default branch.
  # Without this guard a slice still being worked on reconciles to merged and unlocks dependents.
  [ -n "$(git rev-list -n1 "origin/$DEFAULT..$branch" 2>/dev/null)" ] || continue
  if git merge-base --is-ancestor "$branch" "origin/$DEFAULT" 2>/dev/null; then
    say "reconcile: $id merged into $DEFAULT"
    set_status "$id" merged
  fi
done < <(yq -r '.slices[] | [.id, .branch, .status] | join("|")' "$PLAN")

# A slice's base commit: a sibling slice id -> that branch's tip (stacked);
# otherwise the default/remote branch tip.
base_commit() {
  local base="$1"
  if is_slice "$base"; then
    git rev-parse --verify "$(branch_of "$base")^{commit}"
  else
    git rev-parse --verify "origin/$base^{commit}" 2>/dev/null \
      || git rev-parse --verify "$base^{commit}"
  fi
}

# Ready to launch now?
ready() {
  local base="$1" deps="$2"
  if is_slice "$base"; then
    # stacked: the prerequisite branch must exist AND carry work of its own. A branch created
    # earlier in this same pass still points at the default branch, so stacking on it would
    # branch off the default branch and the prerequisite's code would be absent.
    local bb ref
    bb=$(branch_of "$base")
    git rev-parse --verify --quiet "$bb" >/dev/null 2>&1 || return 1
    # Compare against the same ref base_commit() branches from — origin/DEFAULT when it exists.
    # Local and origin DEFAULT can diverge, and comparing against the wrong one reports work
    # that is really just the gap between them.
    ref=$(git rev-parse --verify --quiet "origin/$DEFAULT^{commit}" 2>/dev/null) \
      || ref=$(git rev-parse --verify --quiet "$DEFAULT^{commit}" 2>/dev/null) \
      || return 1
    [ -n "$(git rev-list -n1 "$ref..$bb" 2>/dev/null)" ]
    return
  fi
  # off the default branch: ready once every dependency has merged
  [ -z "$deps" ] && return 0
  local d
  for d in $(printf '%s' "$deps" | tr ',' ' '); do
    [ "$(status_of "$d")" = "merged" ] || return 1
  done
  return 0
}

in_only() {
  [ -z "$ONLY" ] && return 0
  local x
  for x in $(printf '%s' "$ONLY" | tr ',' ' '); do
    [ "$x" = "$1" ] && return 0
  done
  return 1
}

LEARN_DIR="$HOME/.claude/implement-learnings/$REPO/$STORY_SLUG"
launched=0
waiting=0

while IFS='|' read -r id branch base wave deps tasks status; do
  [ "$status" = "pending" ] || continue
  in_only "$id" || continue
  [ -n "$WAVE" ] && [ "$wave" != "$WAVE" ] && continue

  if ! ready "$base" "$deps"; then
    say "waiting: $id (base=$base deps=[${deps}] not satisfied)"
    waiting=$((waiting + 1))
    continue
  fi

  tasks_abs="$MAIN_ROOT/$tasks"
  [ -f "$tasks_abs" ] || die "slice $id: task file missing: $tasks_abs"
  bc=$(base_commit "$base") || die "slice $id: cannot resolve base '$base'"

  learnings="$LEARN_DIR/$id.md"
  handle="$STORY_SLUG-$id"
  prompt="/implement-flow $tasks_abs (adopt this task file; persist run learnings to $learnings; leave the branch for review, do not integrate)"

  # The agent pane workmux focuses; killing every other pane in that window
  # leaves the slice with a single pane. In window mode the slice is a window of
  # the session this runs from; in session mode it is its own session.
  if [ "$MODE" = "window" ]; then
    pane_target="$PARENT:$handle.{top-left}"
  else
    pane_target="$handle:.{top-left}"
  fi

  say "launch: $id  branch=$branch  base=$base@${bc%${bc#??????????}}  handle=$handle"
  if [ "$DRY" -eq 1 ]; then
    printf '  workmux add %q --name %q --base %q --mode %q --background --prompt %q\n' \
      "$branch" "$handle" "$bc" "$MODE" "$prompt"
    printf '  tmux kill-pane -a -t %q\n' "$pane_target"
    set_status "$id" running
  else
    mkdir -p "$LEARN_DIR"
    # stdin is the slice-list pipe feeding this loop; workmux reads a non-tty stdin as a
    # worktree list and then rejects --name as multi-worktree generation.
    if workmux add "$branch" --name "$handle" --base "$bc" --mode "$MODE" --background --prompt "$prompt" </dev/null; then
      tmux kill-pane -a -t "$pane_target" 2>/dev/null || true
      set_status "$id" running
      launched=$((launched + 1))
    else
      say "workmux add failed for $id — left pending"
    fi
  fi
done < <(yq -r '.slices[] | [.id, .branch, .base, (.wave | tostring), (.depends_on | join(",")), .tasks, .status] | join("|")' "$PLAN")

say "done: $launched launched, $waiting waiting. Watch with: workmux dashboard"
