#!/usr/bin/env bash
# deliver-story — the automated form of workmux-new-form, driven by a plan.yaml.
#
# Reads a decompose-to-deliverables delivery plan and, for every deliverable that is ready,
# creates a git worktree + tmux session via `workmux` and launches
# `implement` inside it against that deliverable's task file. Independent deliverables
# fire in parallel (own worktree each); dependent deliverables wait for their
# prerequisites to merge (base: master) or stack on the prerequisite's branch
# (base: <deliverable-id>). Watch progress with `workmux dashboard`.
#
# Usage:
#   deliver.sh [PLAN] [--wave N] [--only id[,id...]] [--wave-size N] [--gears]
#              [--mode session|window] [--dry-run]
#
#   PLAN          path to plan.yaml (auto-discovered under tasks/ if a single one exists)
#   --wave N      only fire deliverables in wave N (default: every ready deliverable)
#   --only ids    comma-separated deliverable ids to restrict to
#   --wave-size N launch at most N deliverables this pass; the rest stay pending for the
#                 next run. Default: no cap, which is every ready deliverable at once.
#                 The scarce resource is not review time but how much a reader can hold
#                 at once, and the DAG knows nothing about that.
#   --gears       hold back deliverables the plan marked blast_radius: high rather than
#                 firing them into a pane nobody is watching. Off by default: every
#                 deliverable launches as it always has, with its assessment printed.
#   --mode        workmux target mode (default: window, falls back to session
#                 when not running inside tmux)
#   --dry-run     print the workmux commands and status changes without running them
#
# The plan's certainty and blast_radius are reported on every launch line regardless of
# --gears. The flag decides whether the driver acts on them, never whether they are
# visible — a wave whose riskiest deliverable is only identifiable by reading plan.yaml
# is one where nobody will identify it.
#
# Ready = status pending AND either (base is the default branch and every
# depends_on deliverable is merged) OR (base is a sibling deliverable whose branch carries
# commits of its own).
# A ready deliverable is launched and its status set to running. Before launching,
# running/in-review deliverables whose branch has merged into the default branch are
# advanced to merged (best-effort, no gh dependency), so the next wave unlocks.
#
# Each deliverable gets a single agent pane. The shared workmux config asks for an
# agent pane plus a shell pane below it; the extra pane is collapsed here rather
# than in that config, which every other workmux entry point still relies on.
set -euo pipefail

die() { printf 'deliver-story: %s\n' "$1" >&2; exit 1; }
say() { printf 'deliver-story: %s\n' "$1"; }

MODE=window
WAVE=""
ONLY=""
WAVE_SIZE=""
GEARS=0
DRY=0
PLAN=""

while [ $# -gt 0 ]; do
  case "$1" in
    --wave)      WAVE="$2"; shift 2 ;;
    --only)      ONLY="$2"; shift 2 ;;
    --wave-size) WAVE_SIZE="$2"; shift 2 ;;
    --gears)     GEARS=1; shift ;;
    --no-gears)  GEARS=0; shift ;;
    --mode)      MODE="$2"; shift 2 ;;
    --dry-run)   DRY=1; shift ;;
    -h|--help)   sed -n '2,34p' "$0"; exit 0 ;;
    --*)         die "unknown option: $1" ;;
    *)           PLAN="$1"; shift ;;
  esac
done

case "$WAVE_SIZE" in
  ''|*[!0-9]*) [ -z "$WAVE_SIZE" ] || die "--wave-size takes a number, got '$WAVE_SIZE'" ;;
  0) die "--wave-size 0 would launch nothing; omit it for no cap" ;;
esac

command -v workmux >/dev/null 2>&1 || die "workmux not found on PATH"
command -v yq      >/dev/null 2>&1 || die "yq not found on PATH"
command -v git     >/dev/null 2>&1 || die "git not found on PATH"

# Window mode puts each deliverable in a window of the session this runs from, so it
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

status_of() { yq -r ".deliverables[] | select(.id==\"$1\") | .status" "$PLAN"; }
branch_of() { yq -r ".deliverables[] | select(.id==\"$1\") | .branch" "$PLAN"; }
is_deliverable()  { yq -e ".deliverables[] | select(.id==\"$1\")" "$PLAN" >/dev/null 2>&1; }
set_status() {
  if [ "$DRY" -eq 1 ]; then say "would set $1 -> $2"; return; fi
  yq -i "(.deliverables[] | select(.id==\"$1\").status) = \"$2\"" "$PLAN"
}

# Reconcile: advance running/in-review deliverables whose work is now in the default
# branch to merged, so dependents unlock.
#
# `--is-ancestor` asks whether the branch TIP is in the default branch's history, which
# is false for every rebase- or squash-merged branch: the work landed under new SHAs and
# the branch still points at the originals. A whole wave stays "running" forever and the
# next wave never fires. `git cherry` compares patch ids instead, marking `+` only for
# commits with no counterpart upstream — none of those means everything here has landed,
# however it got there.
while IFS='|' read -r id branch status; do
  case "$status" in running|in-review) ;; *) continue ;; esac
  git rev-parse --verify --quiet "$branch" >/dev/null 2>&1 || continue
  # A branch that has committed nothing yet has no patches to be missing, so it would
  # reconcile to merged while the deliverable is still being worked on.
  [ -n "$(git rev-list -n1 "origin/$DEFAULT..$branch" 2>/dev/null)" ] || continue
  if ! git cherry "origin/$DEFAULT" "$branch" 2>/dev/null | grep -q '^+'; then
    say "reconcile: $id merged into $DEFAULT (every commit patch-present)"
    set_status "$id" merged
  fi
done < <(yq -r '.deliverables[] | [.id, .branch, .status] | join("|")' "$PLAN")

# A deliverable's base commit: a sibling deliverable id -> that branch's tip (stacked);
# otherwise the default/remote branch tip.
base_commit() {
  local base="$1"
  if is_deliverable "$base"; then
    git rev-parse --verify "$(branch_of "$base")^{commit}"
  else
    git rev-parse --verify "origin/$base^{commit}" 2>/dev/null \
      || git rev-parse --verify "$base^{commit}"
  fi
}

# Ready to launch now?
ready() {
  local base="$1" deps="$2"
  if is_deliverable "$base"; then
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
chosen=0
deferred=0
held=""
launched_handles=""

# The plan's `status` is a latch this script sets; it is not evidence. A run started by
# hand, or one whose worktree took a different branch name than the plan chose, leaves
# the latch on `pending` while the work is well under way — and launching then scaffolds
# a second worktree for a deliverable someone is already building. `clerk story` derives
# state from the sidecar, the branch and the worktree list, so ask it before firing.
CLERK_STATE=""
if command -v clerk >/dev/null 2>&1; then
  CLERK_STATE=$(clerk story "$PLAN" 2>/dev/null |
    jq -r '.[0].deliverables[]? | [.id, .state, (.worktree // .branch_alias // "")] | join("|")' 2>/dev/null) || CLERK_STATE=""
fi
clerk_state_of() { printf '%s\n' "$CLERK_STATE" | awk -F'|' -v i="$1" '$1 == i {print $2; exit}'; }
clerk_where_of() { printf '%s\n' "$CLERK_STATE" | awk -F'|' -v i="$1" '$1 == i {print $3; exit}'; }

# Whether anything is still sitting in that worktree. clerk answers what the WORK looks
# like — commits, ticked tasks, a branch — and cannot answer whether a process is alive,
# which is not a fact about the repository. Without asking, a run that died after three of
# seven tasks looks exactly like one still working through task four, and gets skipped
# forever. A pane's cwd drifts into subdirectories as a run works, so match those too.
agent_running_in() {
  local wt="$1"
  [ -n "$wt" ] || return 1
  tmux list-panes -a -F '#{pane_current_path}' 2>/dev/null |
    awk -v w="$wt" '$0 == w || index($0, w "/") == 1 { found = 1 } END { exit !found }'
}

while IFS='|' read -r id branch base wave deps tasks status certainty blast; do
  [ "$status" = "pending" ] || continue
  in_only "$id" || continue
  [ -n "$WAVE" ] && [ "$wave" != "$WAVE" ] && continue

  cs=$(clerk_state_of "$id")
  resume=""
  case "$cs" in
    awaiting-merge|merged)
      where=$(clerk_where_of "$id")
      say "skip: $id is already $cs${where:+ at $where} — the plan still says pending, clerk is right"
      continue ;;
    in-progress)
      where=$(clerk_where_of "$id")
      if [ -z "$where" ]; then
        say "skip: $id has commits but no worktree to resume in — check out its branch yourself"
        continue
      fi
      if agent_running_in "$where"; then
        say "skip: $id is being worked on at $where — the plan still says pending, clerk is right"
        continue
      fi
      # Resuming is safe because the run reads its own sidecar: `clerk next` hands back the
      # first unblocked task that is not already done, so the same prompt continues from
      # where it stopped instead of rebuilding what landed. A tree left dirty mid-task
      # stops it again on arrival, which is the report you want rather than a run that
      # builds on top of someone else's half-finished edit.
      resume="$where"
      say "resume: $id stopped partway at $where with nothing running — restarting the run there"
      ;;
    scaffolded)
      # A worktree standing at its base with no commits is a launch that died before doing
      # anything. Its worktree is fine — right branch, right base, clean — so open it and
      # start the run inside it. Creating a second one would strand this one, and skipping
      # it outright leaves a deliverable nothing can ever pick up.
      resume=$(clerk_where_of "$id")
      say "resume: $id has an empty worktree at $resume — starting the run in it"
      ;;
  esac

  if ! ready "$base" "$deps"; then
    say "waiting: $id (base=$base deps=[${deps}] not satisfied)"
    waiting=$((waiting + 1))
    continue
  fi

  # The plan assessed how sure it is of the method and what being wrong would cost. Both
  # are printed on every launch line below; only --gears makes the driver act on one.
  #
  # High blast radius is held rather than merely flagged because of what a launch is: an
  # unattended run in a background pane, finishing hours later into a pull request. That
  # is the right shape for work whose failure is a bad diff and the wrong one for work
  # whose failure is a permission check that now passes for everyone. Held, not skipped —
  # the deliverable stays pending and the operator runs it in front of themselves.
  if [ "$GEARS" -eq 1 ] && [ "$blast" = "high" ]; then
    say "hold: $id is blast_radius=high — not firing it unattended (--gears). Run it yourself: --only $id --no-gears"
    held="$held $id"
    continue
  fi

  # A cap on how many land in one pass, because the DAG decides what CAN run in parallel
  # and nothing decides how much a person can read. Deferred deliverables stay pending and
  # are picked up by the next run, exactly like ones whose dependencies had not merged.
  if [ -n "$WAVE_SIZE" ] && [ "$chosen" -ge "$WAVE_SIZE" ]; then
    say "defer: $id is ready but the wave is capped at $WAVE_SIZE — re-run to deliver it"
    deferred=$((deferred + 1))
    continue
  fi

  tasks_abs="$MAIN_ROOT/$tasks"
  [ -f "$tasks_abs" ] || die "deliverable $id: task file missing: $tasks_abs"
  bc=$(base_commit "$base") || die "deliverable $id: cannot resolve base '$base'"

  learnings="$LEARN_DIR/$id.md"
  handle="$STORY_SLUG-$id"
  # --in-place because workmux already made the worktree and started this agent inside it;
  # without it the run would scaffold a second one for work it is already standing in.
  # No --review-plan: a wave fires many of these at once and nobody is reading the panes,
  # so each one builds against the breakdown it was handed rather than holding a plan up.
  # --no-integrate as a flag rather than only as prose: a repo may set integrate=true, and
  # `clerk land` honours that in code, which would merge each deliverable into the default
  # branch — dismantling the stack these runs exist to produce before anyone reviews it.
  prompt="/implement $tasks_abs --in-place --no-integrate (adopt this task file; persist run learnings to $learnings; leave the branch for review)"

  # The agent pane workmux focuses; killing every other pane in that window
  # leaves the deliverable with a single pane. In window mode the deliverable is a window of
  # the session this runs from; in session mode it is its own session.
  if [ "$MODE" = "window" ]; then
    pane_target="$PARENT:$handle.{top-left}"
  else
    pane_target="$handle:.{top-left}"
  fi

  chosen=$((chosen + 1))
  say "launch: $id  branch=$branch  base=$base@${bc%${bc#??????????}}  handle=$handle  certainty=$certainty  blast=$blast"
  # `open` for a worktree that already exists, `add` for one that does not. `add` on an
  # existing worktree would make a second, and `open` on a missing one has nothing to open.
  if [ -n "$resume" ]; then
    set -- open "$(basename -- "$resume")" --prompt "$prompt"
  else
    set -- add "$branch" --name "$handle" --base "$bc" --mode "$MODE" --background --prompt "$prompt"
  fi

  if [ "$DRY" -eq 1 ]; then
    printf '  workmux'; printf ' %q' "$@"; printf '\n'
    printf '  tmux kill-pane -a -t %q\n' "$pane_target"
    set_status "$id" running
    launched_handles="$launched_handles $handle"
  else
    mkdir -p "$LEARN_DIR"
    # stdin is the deliverable-list pipe feeding this loop; workmux reads a non-tty stdin as a
    # worktree list and then rejects --name as multi-worktree generation.
    if workmux "$@" </dev/null; then
      tmux kill-pane -a -t "$pane_target" 2>/dev/null || true
      set_status "$id" running
      launched=$((launched + 1))
      launched_handles="$launched_handles $handle"
    else
      say "workmux add failed for $id — left pending"
    fi
  fi
done < <(yq -r '.deliverables[] | [.id, .branch, .base, (.wave | tostring), (.depends_on | join(",")), .tasks, .status, (.certainty // "unassessed"), (.blast_radius // "unassessed")] | join("|")' "$PLAN")

say "done: $launched launched, $waiting waiting. Watch with: workmux dashboard"
if [ "$deferred" -gt 0 ]; then
  say "$deferred deferred by --wave-size $WAVE_SIZE — re-run this to deliver them"
fi
if [ -n "$held" ]; then
  say "held back as blast_radius=high:$held"
  say "  each needs a run you are watching — see the deliver-story skill's by-hand path"
fi

# Run in the background so the dispatcher is woken instead of polling. This is an
# early wake, not a completion signal: workmux reports "done" whenever the agent
# goes idle, which happens between turns, while a workflow of its own runs, and
# after a crash that committed nothing. Verify commits and the task file's
# checkboxes on wake before calling a deliverable deliverable.
if [ -n "$launched_handles" ]; then
  say "wake when a deliverable goes idle (run in the background, then verify):"
  printf '  workmux wait%s --any --status done --timeout 5400\n' "$launched_handles"
fi
