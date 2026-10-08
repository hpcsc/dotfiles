#!/usr/bin/env bash
# Tests for deliverable-open. workmux and tmux are stubs on PATH that print the command they
# get, so this checks the decision for each deliverable state without creating a worktree or
# a tmux window. Run with: tests/deliverable-open-test.sh
#
# The decision worth pinning is the third one: a deliverable already under way must be
# opened rather than started, or a second worktree gets scaffolded for it and the first
# one's commits are stranded on a branch nobody is watching.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/link/common/dot-local/bin/deliverable-open"
PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

STUBS=$(mktemp -d)
cat > "$STUBS/workmux" <<'EOF'
#!/usr/bin/env bash
printf 'workmux'; printf ' %s' "$@"; printf '\n'
EOF
# PANES is what `tmux list-panes -a` would report; set per case to say whether a window is
# already showing the worktree.
cat > "$STUBS/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)      printf '%s\n' "${PANES:-}" ;;
  display-message) echo Work ;;
  *)               printf 'tmux'; printf ' %s' "$@"; printf '\n' ;;
esac
EOF
chmod +x "$STUBS/workmux" "$STUBS/tmux"

deliverable() {  # id state worktree base blocked_by tasks
  jq -cn --arg id "$1" --arg state "$2" --arg wt "$3" --arg base "$4" --arg blocked "$5" --arg tasks "$6" \
    '{id: $id, state: $state, worktree: (if $wt == "" then null else $wt end), base_commit: $base,
      blocked_by: ($blocked | split(",") | map(select(. != ""))), tasks_file: $tasks}'
}
DONE_ONE=$(deliverable done-one merged    ""        aaa1111111 ""   /t/a.md)
HELD=$(deliverable     held     blocked    ""        bbb2222222 live /t/b.md)
LIVE=$(deliverable     live     in-progress /wt/live ccc3333333 ""   /t/c.md)
FRESH=$(deliverable    fresh    ready      ""        ddd4444444 ""   /t/d.md)
EMPTY=$(deliverable    empty    scaffolded /wt/empty eee5555555 ""   /t/e.md)

PANES=""
open_it() { PATH="$STUBS:$PATH" PANES="$PANES" "$SCRIPT" "$@" 2>&1; }

printf '\ndeliverable-open\n'
eq "a merged deliverable offers nothing to start" \
   "done-one is merged — nothing to start. Review or land it instead." "$(open_it s "$DONE_ONE")"
eq "a blocked one names what it waits on" \
   "held is blocked by live — finish those first, or start one of them." "$(open_it s "$HELD")"

# The window already showing that worktree. workmux identifies a target by NAME and keeps
# no worktree-to-target registry, so a window named anything else is invisible to it and
# `workmux open` would start a second session beside the running work.
PANES='Work:2|/wt/live
Work:3|/elsewhere'
out=$(TMUX=/tmp/fake open_it s "$LIVE")
eq "one already running is switched to, not reopened" \
   "live is already running in Work:2 — switching to it" "$(sed -n 1p <<<"$out")"
eq "selecting the window that holds it"  "tmux select-window -t Work:2" "$(sed -n 2p <<<"$out")"
eq "and switching the client to its session" "tmux switch-client -t Work" "$(sed -n 3p <<<"$out")"

# A subdirectory of the worktree counts: a pane's cwd drifts as the run works.
PANES='Work:5|/wt/live/internal/api'
eq "a pane deeper in the tree still identifies the window" \
   "live is already running in Work:5 — switching to it" "$(TMUX=/tmp/fake open_it s "$LIVE" | sed -n 1p)"

# A sibling path that merely starts with the same characters is not the same worktree.
PANES='Work:9|/wt/live-something-else'
out=$(open_it s "$LIVE")
eq "a path that only shares a prefix is not mistaken for it" \
   "live has a worktree at /wt/live but nothing running in it — opening it" "$(sed -n 1p <<<"$out")"
# One with commits behind it is opened bare: a fresh /implement would restart its story.
eq "and a worktree with work in it is opened without a prompt" "workmux open live" "$(tail -1 <<<"$out")"

PANES=""
out=$(open_it s "$FRESH")
eq "a ready one launches implement against its absolute task file" \
   "starting fresh on ddd4444444 — /implement /t/d.md" "$(sed -n 1p <<<"$out")"
eq "on the resolved base, leaving mode to the global config" \
   "workmux add s-fresh --name s-fresh --base ddd4444444 --prompt /implement /t/d.md --in-place" \
   "$(tail -1 <<<"$out")"

# A worktree a dead launch left behind: right branch, right base, nothing built. It needs
# the prompt that starts the run, which an open alone would never deliver.
out=$(open_it s "$EMPTY")
eq "an empty worktree is started in place, not left sitting" \
   "empty has an empty worktree at /wt/empty — starting the run in it" "$(sed -n 1p <<<"$out")"
eq "opening it with the prompt that begins the work" \
   "workmux open empty --prompt /implement /t/e.md --in-place" "$(tail -1 <<<"$out")"

eq "a call without a deliverable is a usage error" "2" "$(open_it s >/dev/null; echo $?)"

rm -rf "$STUBS"
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
