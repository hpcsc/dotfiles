#!/usr/bin/env bash
# Tests for tmux-deliver, without fzf and without a tmux server. Each case fills the
# popup's state folder with a fixed `clerk project` result and calls one re-entry point.
# tmux, deliverable-open and clerk are stubs on PATH that write what they get to a log.
# The script runs under /bin/bash, because a tmux key binding can start it with the bash
# 3.2 that macOS ships. Run with: tests/tmux-deliver-test.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/link/common/dot-local/bin/tmux-deliver"
PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "text containing: $2" "$3" ;; esac; }
plain() { sed $'s/\x1b\\[[0-9;]*m//g'; }

STUBS=$(mktemp -d)
LOG="$STUBS/log"
cat > "$STUBS/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  display-message) echo Work ;;
  list-windows)    printf '%s\n' "${WINDOWS:-}" ;;
  *)               { printf 'tmux'; printf ' %s' "$@"; printf '\n'; } >> "$LOG" ;;
esac
EOF
cat > "$STUBS/deliverable-open" <<'EOF'
#!/usr/bin/env bash
args=()
for a in "$@"; do case "$a" in "{"*) args+=("$(jq -r '.id' <<<"$a")") ;; *) args+=("$a") ;; esac; done
printf 'deliverable-open %s\n' "${args[*]}" >> "$LOG"
echo "started ${args[${#args[@]}-1]}"
EOF
cat > "$STUBS/clerk" <<'EOF'
#!/usr/bin/env bash
echo "clerk $*" >> "$LOG"
exit 1
EOF
chmod +x "$STUBS/tmux" "$STUBS/deliverable-open" "$STUBS/clerk"
export LOG

ROOT=$(cd "$(mktemp -d)" && pwd -P)
mkdir -p "$ROOT/.scratches/write-user-story/feat" "$ROOT/.scratches/write-user-story/other"
printf '# Feature\n\n### US-001: Root\n\n**Ticket:** T-1\n' > "$ROOT/.scratches/write-user-story/feat/feat.md"
printf '# Other\n\n### US-001: No ticket yet\n' > "$ROOT/.scratches/write-user-story/other/other.md"

S=$(mktemp -d)
export TMUX_DELIVER_STATE=$S
fresh_state() {
  rm -rf "$S"; mkdir -p "$S"; : > "$LOG"
  printf '%s' "$ROOT" > "$S/root"
  printf '%s' .scratches/write-user-story/feat/feat.md > "$S/feature"
  printf story > "$S/preview"
  cat > "$S/data.json" <<'EOF'
{"running": ["s3/c"], "stories": [
 {"id": "US-001", "title": "Root", "ticket": "T-1", "depends_on": [], "blocked_by": [], "unblocks": 3,
  "dependents": ["US-002", "US-003"], "step": 1, "critical": true, "state": "merged",
  "evidence": "commits on main that name T-1: 1", "plans": [], "deliverables": []},
 {"id": "US-002", "title": "Planned", "ticket": "T-2", "depends_on": ["US-001"], "blocked_by": [], "unblocks": 1,
  "dependents": ["US-004"], "step": 2, "critical": true, "state": "planned", "evidence": "no approved: line",
  "plans": ["/p/s2/plan.yaml"], "deliverables": [
   {"plan": "/p/s2/plan.yaml", "story_slug": "s2", "id": "a", "state": "ready", "wave": 1, "done": 0, "total": 2,
    "branch": "br-s2-a", "branch_alias": null, "tasks_file": "/p/s2/a/tasks.md", "blocked_by": []}]},
 {"id": "US-003", "title": "Under way", "ticket": "T-3", "depends_on": ["US-001"], "blocked_by": [], "unblocks": 0,
  "dependents": [], "step": 2, "critical": false, "state": "in-progress", "evidence": "1 in-progress, 1 ready",
  "plans": ["/p/s3/plan.yaml"], "deliverables": [
   {"plan": "/p/s3/plan.yaml", "story_slug": "s3", "id": "c", "state": "in-progress", "wave": 1, "done": 1, "total": 2,
    "branch": "br-s3-c", "branch_alias": null, "tasks_file": "/p/s3/c/tasks.md", "blocked_by": []},
   {"plan": "/p/s3/plan.yaml", "story_slug": "s3", "id": "d", "state": "ready", "wave": 1, "done": 0, "total": 1,
    "branch": "br-s3-d", "branch_alias": null, "tasks_file": "/p/s3/d/tasks.md", "blocked_by": []}]},
 {"id": "US-004", "title": "Last", "ticket": "T-4", "depends_on": ["US-002"], "blocked_by": ["US-002"], "unblocks": 0,
  "dependents": [], "step": 3, "critical": true, "state": "blocked", "evidence": "US-002 not merged",
  "plans": [], "deliverables": []},
 {"id": "US-005", "title": "Alone", "ticket": "T-5", "depends_on": [], "blocked_by": [], "unblocks": 0,
  "dependents": [], "step": 1, "critical": false, "state": "ready", "evidence": "no plan names T-5",
  "plans": [], "deliverables": []}]}
EOF
  printf '[{"branch": "br-s3-c", "status": "done"}, {"branch": "br-s3-c", "status": "working"}]\n' > "$S/agents.json"
}
deliver() { PATH="$STUBS:$PATH" /bin/bash "$SCRIPT" "$@"; }

# --------------------------------------------------------------------------------
printf '\nthe screens\n'
fresh_state

eq "the features are the stories files with tickets, and every plan" \
   "Feature  .scratches/write-user-story/feat/feat.md|every plan in tasks/  clerk story" \
   "$(deliver --rows features | plain | cut -f1 | paste -sd'|' -)"
eq "a story row has its state, ID, ticket, the stories it unblocks, title and blockers" \
   "blocked        US-004  T-4       ↑0   Last  [blocked by US-002]	US-004" \
   "$(deliver --rows stories | plain | grep US-004)"
printf US-003 > "$S/story"
eq "a deliverable row shows its agent at work, from the agent states of its branch" \
   "in-progress    w1  1/2    🤖 c	/p/s3/plan.yaml	c	/p/s3/c/tasks.md" \
   "$(deliver --rows deliverables | plain | grep $'\tc\t')"
eq "and a deliverable with no agent shows none" \
   "ready          w1  0/1       d" "$(deliver --rows deliverables | plain | grep $'\td\t' | cut -f1)"
has "the header names the feature and the runs against the limit" \
   "deliver · Feature · runs 1 (limit 2)" "$(deliver --header stories)"
eq "nothing here asks clerk again while the data is in the state folder" "" "$(cat "$LOG")"

PREVIEW=$(deliver --preview story US-002 | plain)
has "the story preview names the stories it waits on, with their state" "waits on:      US-001 merged" "$PREVIEW"
has "and the stories that wait on it" "waited on by:  US-004 blocked" "$PREVIEW"
has "and its deliverables" "ready          w1  0/2  a" "$PREVIEW"

deliver --toggle-preview
GRAPH=$(deliver --preview story US-002 | plain)
has "ctrl-t turns the preview into the graph of the feature, by step" \
   "step 3  * US-004  blocked        <- US-002" "$GRAPH"
has "with the length of the critical path" "* critical path: 3 steps" "$GRAPH"
deliver --toggle-preview
has "and back" "waits on:      US-001 merged" "$(deliver --preview story US-002 | plain)"

# --------------------------------------------------------------------------------
printf '\nthe next step of each story\n'
fresh_state

TARGETS=$(deliver --next-step US-005 US-002 US-003 US-004 US-001)
eq "it prints the windows it opened, for the popup to switch to" "Work:t-5-plan|Work:t-2-gate" \
   "$(paste -sd'|' - <<<"$TARGETS")"
has "a ready story gets a Claude window in the main checkout" "tmux new-window -d -t Work: -n t-5-plan -c $ROOT" "$(cat "$LOG")"
has "that plans it with /deliver-story, from its section of the stories file" \
   "tmux send-keys -t Work:t-5-plan -l claude '/deliver-story T-5: deliver story US-005 of $ROOT/.scratches/write-user-story/feat/feat.md." \
   "$(cat "$LOG")"
has "a planned story gets a window that adopts its plan for the gate" \
   "tmux send-keys -t Work:t-2-gate -l claude '/deliver-story /p/s2/plan.yaml'" "$(cat "$LOG")"
eq "a story under way starts its ready deliverables only, in the background" \
   "deliverable-open --window --background s3 d" "$(grep '^deliverable-open' "$LOG")"
has "a blocked story says so" "US-004 is blocked: no next step here" "$(cat "$S/message")"
has "and so does a merged one" "US-001 is merged: no next step here" "$(cat "$S/message")"
eq "the data is read again after the step" "missing" "$( [ -e "$S/data.json" ] && echo present || echo missing)"
eq "clerk is not asked again during the step" "" "$(grep '^clerk' "$LOG")"

fresh_state
WINDOWS=t-2-gate deliver --next-step US-002 >/dev/null
eq "a window that exists already is used again, not opened twice" "" "$(grep 'new-window' "$LOG")"

# --------------------------------------------------------------------------------
printf '\nstart\n'
fresh_state
deliver --start $'x\t/p/s3/plan.yaml\td' $'x\t/p/s2/plan.yaml\ta'
eq "ctrl-s starts each marked deliverable in a background window" \
   "deliverable-open --window --background s3 d|deliverable-open --window --background s2 a" \
   "$(grep '^deliverable-open' "$LOG" | paste -sd'|' -)"
eq "and the header shows what each start said" "started d;started a" "$(cat "$S/message")"
fresh_state
deliver --start --gears $'x\t/p/s3/plan.yaml\td'
eq "ctrl-g starts it with --gears" "deliverable-open --window --background --gears s3 d" "$(grep '^deliverable-open' "$LOG")"

# --------------------------------------------------------------------------------
rm -rf "$STUBS" "$ROOT" "$S"
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
