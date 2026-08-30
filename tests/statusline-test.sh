#!/usr/bin/env bash
# Fixture tests for the Claude Code status line. It re-renders on every keystroke, so the
# property under test is as much what it does NOT do — fork a process per field — as what
# it prints. Run with: tests/statusline-test.sh
set -uo pipefail
SL="$(cd "$(dirname "$0")/.." && pwd)/link/common/claude/.claude/statusline-command.sh"
PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

CACHE=$(cd "$(mktemp -d)" && pwd -P)
export XDG_CACHE_HOME="$CACHE"
ACTIVE="$CACHE/clerk/active"

IN='{"workspace":{"current_dir":"/tmp/demo/repo"},"model":{"display_name":"Opus 5"},
     "effort":{"level":"high"},"context_window":{"used_percentage":41},
     "rate_limits":{"five_hour":{"used_percentage":12},"seven_day":{"used_percentage":30}},
     "cost":{"total_cost_usd":2.4}}'

render() { printf '%s' "$IN" | COLUMNS=110 bash "$SL" | sed 's/\x1b\[[0-9;]*m//g'; }
beat() {  # dir slug label done cost
  mkdir -p "$ACTIVE"
  printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f1788131158\n' "$1" "$2" "$3" "$4" "$5" >| "$ACTIVE/one"
}

printf '\nthe line without a run in flight\n'
rm -rf "$ACTIVE"
OUT=$(render)
eq "it still renders when nothing is running" "true" \
   "$(printf '%s' "$OUT" | grep -q 'Opus 5' && echo true || echo false)"
eq "and says nothing about a run" "0" "$(printf '%s' "$OUT" | grep -c 'task\|audit')"

printf '\na run building here\n'
beat /tmp/demo/repo "audit age-847" review 3 0.84
OUT=$(render)
eq "the run is named with what it is doing" "true" \
   "$(printf '%s' "$OUT" | grep -q 'audit age-847:review' && echo true || echo false)"
eq "with how much has landed and what it has cost" "true" \
   "$(printf '%s' "$OUT" | grep -q '3✓ \$0.84' && echo true || echo false)"
eq "and the rest of the line is untouched" "true" \
   "$(printf '%s' "$OUT" | grep -q 'ctx:41%' && printf '%s' "$OUT" | grep -q '5h:12%' && echo true || echo false)"

printf '\nwhich run is mine\n'
beat /tmp/other/repo "audit elsewhere" review 9 9.99
eq "a run in another repository is not reported here" "0" "$(render | grep -c 'elsewhere')"
# The session's cwd is as often the worktree the run builds in as the checkout it was
# launched from, so the match has to hold in both directions.
beat /tmp/demo/repo/.worktrees/x story-x "task 2/5" 4 1.20
eq "a run in a worktree below this directory is" "true" \
   "$(render | grep -q 'story-x:task 2/5' && echo true || echo false)"
beat /tmp/demo story-up ground 1 0.10
eq "and so is one launched from the checkout above it" "true" \
   "$(render | grep -q 'story-up:ground' && echo true || echo false)"

printf '\nwhat it must not cost\n'
# Every field arrives in one jq pass and the heartbeat is read with builtins. A second
# fork here is paid on every keystroke, which is why the file lives at a fixed path
# instead of behind a `git rev-parse`.
beat /tmp/demo/repo "audit age-847" review 3 0.84
eq "the line forks once, for jq, however many runs are active" "1" \
   "$(printf '%s' "$IN" | COLUMNS=110 bash -x "$SL" 2>&1 >/dev/null | grep -cE '^\+* *jq ')"
eq "no git, no stat, no cat" "0" \
   "$(printf '%s' "$IN" | COLUMNS=110 bash -x "$SL" 2>&1 >/dev/null | grep -cE '^\+* *(git|stat|cat|date|find) ')"

printf '\na file left by a run that was killed\n'
beat /tmp/demo/repo "audit age-847" review 3 0.84
eq "is still shown — presence is the signal, and clerk sweeps its own cache" "true" \
   "$(render | grep -q 'audit age-847' && echo true || echo false)"
rm -rf "$ACTIVE"
eq "and once removed, the line is quiet again" "0" "$(render | grep -c 'age-847')"

rm -rf "$CACHE"
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
