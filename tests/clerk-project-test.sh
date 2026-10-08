#!/usr/bin/env bash
# Fixture-repo tests for `clerk project`. No framework: each case builds a throwaway git
# repo with a stories file and plans under tasks/, and asserts on the JSON.
# Run with: tests/clerk-project-test.sh
set -uo pipefail
BIN="$(cd "$(dirname "$0")/.." && pwd)/link/common/dot-local/bin"
CLERK="$BIN/clerk"
export PATH="$BIN:$PATH"
PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has()  { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "text containing: $2" "$3" ;; esac; }

new_repo() {
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$d" init -q -b main
  git -C "$d" config user.email clerk@test
  git -C "$d" config user.name  Clerk
  git -C "$d" config commit.gpgsign false
  printf 'seed\n' > "$d/README.md"
  git -C "$d" add -A && git -C "$d" commit -qm "Seed"
  printf '%s' "$d"
}

run() { (cd "$1" && shift && "$CLERK" "$@"); }

# story <id> <ticket> <depends on> <title>
story() {
  printf '### %s: %s\n\n' "$1" "$4"
  [ -n "$2" ] && printf '**Ticket:** %s\n\n' "$2"
  printf '**Description:** As a user, I want %s.\n\n' "$4"
  [ -n "$3" ] && printf '**Depends on:** %s\n\n' "$3"
  return 0
}

# deliverable <repo> <plan slug> <id> <total> <done>
deliverable() {
  local dir="$1/tasks/$2/$3" i=1 body=
  mkdir -p "$dir"
  printf '# %s\n' "$3" > "$dir/tasks.md"
  while [ "$i" -le "$4" ]; do
    body="$body{\"n\":$i,\"title\":\"t$i\",\"depends_on\":[],\"done\":$([ "$i" -le "$5" ] && echo true || echo false)},"
    i=$((i + 1))
  done
  printf '{"tasks":[%s]}\n' "${body%,}" > "$dir/tasks.json"
}

# plan <repo> <slug> <ticket> <approved date or ""> <deliverable id>...
plan() {
  local r=$1 slug=$2 ticket=$3 approved=$4 id
  shift 4
  mkdir -p "$r/tasks/$slug"
  { printf 'story: "%s"\nstory_slug: %s\nticket: "%s"\n' "$slug" "$slug" "$ticket"
    [ -n "$approved" ] && printf 'approved: %s\n' "$approved"
    printf 'deliverables:\n'
    for id in "$@"; do
      printf '  - id: %s\n    branch: br-%s-%s\n    base: main\n    wave: 1\n    depends_on: []\n    tasks: tasks/%s/%s/tasks.md\n' \
        "$id" "$slug" "$id" "$slug" "$id"
    done
  } > "$r/tasks/$slug/plan.yaml"
}

commit_on() {  # repo branch file message
  git -C "$1" checkout -q -B "$2"
  printf '%s\n' "$2" > "$1/$3"
  git -C "$1" add -A && git -C "$1" commit -qm "$4"
  git -C "$1" checkout -q main
}

# --------------------------------------------------------------------------------
printf '\nthe stories file\n'

V=$(new_repo)
{ story US-001 "" "" "One"; } > "$V/no-ticket.md"
eq "a story with no ticket is refused, because its plan is found by its ticket" "2" \
   "$(run "$V" project no-ticket.md >/dev/null 2>&1; echo $?)"
has "and the refusal names the story" "US-001" "$(run "$V" project no-ticket.md 2>&1)"

{ story US-001 T-1 "US-404" "One"; } > "$V/unknown.md"
has "a dependency on a story the file does not hold is refused" "US-001 -> US-404" \
   "$(run "$V" project unknown.md 2>&1)"

{ story US-001 T-1 "US-002" "One"; story US-002 T-2 "US-001" "Two"; } > "$V/cycle.md"
has "a dependency cycle is refused, with the cycle named" "US-001 -> US-002 -> US-001" \
   "$(run "$V" project cycle.md 2>&1)"

{ story US-001 T-1 "" "One"; story US-002 T-1 "" "Two"; } > "$V/shared.md"
has "two stories with one ticket are refused" "gives T-1 to more than one story" \
   "$(run "$V" project shared.md 2>&1)"

{ printf '## Delivery Order\n\n```mermaid\n### US-009: Not a story\n```\n\n'
  story US-001 "[AGE-969](https://linear.app/x/issue/AGE-969/ask)" "None" "One"
  printf '## Non-Goals\n\n**Depends on:** US-404\n'
} > "$V/shape.md"
J=$(run "$V" project shape.md)
eq "a heading inside a code block is not a story" "US-001" "$(printf '%s' "$J" | jq -r '[.stories[].id] | join(",")')"
eq "a ticket written as a link reads as its ID" "AGE-969" "$(printf '%s' "$J" | jq -r '.stories[0].ticket')"
eq "a section after the stories ends the last story" "" "$(printf '%s' "$J" | jq -r '.stories[0].depends_on | join(",")')"
eq "a repository with no plans reads every story without a plan" "ready" "$(printf '%s' "$J" | jq -r '.stories[0].state')"

eq "next refuses a limit below 1" "2" "$(run "$V" project next shape.md --limit 0 >/dev/null 2>&1; echo $?)"

# --------------------------------------------------------------------------------
printf '\nthe state of each story\n'

P=$(new_repo)
{ story US-001 T-1  ""       "Merged by hand"
  story US-009 T-9  ""       "Ready and blocks nothing"
  story US-002 T-2  "US-001" "Ready and blocks two"
  story US-003 T-3  "US-002" "Blocked"
  story US-004 T-4  "US-003" "Planned early"
  story US-005 T-5  ""       "Planned"
  story US-006 T-6  ""       "Approved"
  story US-007 T-7  ""       "Started"
  story US-008 T-8  ""       "Started by hand"
  story US-010 T-10 ""       "Merged through its plan"
  story US-011 T-11 "US-010" "Waits on a merged plan"
  story US-012 T-12 ""       "Built"
} > "$P/stories.md"
plan "$P" s4  T-4  2026-10-08 a;      deliverable "$P" s4 a 1 0
plan "$P" s5  T-5  ""         a;      deliverable "$P" s5 a 1 0
plan "$P" s6  T-6  2026-10-08 a b c;  for d in a b c; do deliverable "$P" s6 "$d" 1 0; done
plan "$P" s7  T-7  ""         x z;    deliverable "$P" s7 x 2 1; deliverable "$P" s7 z 1 0
plan "$P" s10 T-10 2026-10-01 m;      deliverable "$P" s10 m 1 1
plan "$P" s12 T-12 2026-10-01 f;      deliverable "$P" s12 f 1 1
plan "$P" other X-99 ""       y;      deliverable "$P" other y 2 1
git -C "$P" add -A && git -C "$P" commit -qm "Plan the stories"
printf 'done\n' > "$P/by-hand.txt"; git -C "$P" add -A
git -C "$P" commit -qm "$(printf 'Do it by hand\n\nInitiative: [T-1] Merged by hand')"
commit_on "$P" br-s7-x     x.txt "Half of x"
commit_on "$P" br-other-y  y.txt "Half of y"
commit_on "$P" br-s12-f    f.txt "All of f"
commit_on "$P" t-8-by-hand h.txt "Started without a plan"

S=$(run "$P" project stories.md)
st() { printf '%s' "$S" | jq -r --arg i "$1" '.stories[] | select(.id == $i) | .state'; }
field() { printf '%s' "$S" | jq -r --arg i "$1" --arg f "$2" '.stories[] | select(.id == $i) | .[$f] | if type == "array" then join(",") else tostring end'; }

eq "a story with no plan whose ticket is named on the default branch is merged" "merged" "$(st US-001)"
has "and the evidence says so" "name T-1" "$(field US-001 evidence)"
eq "a story whose dependencies are merged and that has no plan is ready" "ready" "$(st US-002)"
eq "a story whose dependency is not merged is blocked" "blocked|US-002" "$(st US-003)|$(field US-003 blocked_by)"
eq "a plan made before its dependency merged still reads as blocked" "blocked" "$(st US-004)"
eq "a plan with no approved: line is planned" "planned" "$(st US-005)"
eq "a plan with an approved: line is approved" "approved" "$(st US-006)"
has "and the evidence gives the date" "2026-10-08" "$(field US-006 evidence)"
eq "a plan with a deliverable under way is in-progress" "in-progress" "$(st US-007)"
eq "a branch named after the ticket, with no plan, is in-progress" "in-progress" "$(st US-008)"
has "and the evidence names the branch" "t-8-by-hand" "$(field US-008 evidence)"
eq "a plan whose deliverables all merged is merged" "merged" "$(st US-010)"
eq "and the story that waits on it is ready" "ready|" "$(st US-011)|$(field US-011 blocked_by)"
eq "a plan whose deliverables are all built and not merged is awaiting-merge" "awaiting-merge" "$(st US-012)"
eq "unblocks counts the stories that wait directly and through another story" "3|2|0" \
   "$(field US-001 unblocks)|$(field US-002 unblocks)|$(field US-009 unblocks)"
eq "running counts the deliverables under way in every plan, also outside the file" "other/y,s7/x" \
   "$(printf '%s' "$S" | jq -r '.running | sort | join(",")')"
eq "the stories keep the order of the file" "US-001,US-009,US-002" \
   "$(printf '%s' "$S" | jq -r '[.stories[:3][].id] | join(",")')"

O=$(new_repo)
{ story US-002 T-2 "US-001" "Listed first"; story US-001 T-1 "" "Listed second"; } > "$O/stories.md"
git -C "$O" commit -q --allow-empty -m "$(printf 'Do one\n\nInitiative: [T-1] Listed second')"
eq "a story whose dependency comes later in the file reads that dependency's state" "merged|ready" \
   "$(run "$O" project stories.md | jq -r '[.stories[] | select(.id == "US-001", .id == "US-002") | .state] | reverse | join("|")')"
eq "--table gives one row for each story" "12" "$(run "$P" project stories.md --table | grep -cE '^US-')"

# --------------------------------------------------------------------------------
printf '\nnext\n'

N=$(run "$P" project next stories.md)
eq "the default limit is 2, and two runs are under way, so nothing starts" "2|0|0" \
   "$(printf '%s' "$N" | jq -r '[.limit, .budget, (.start | length)] | join("|")')"
eq "the stories to plan come first by the stories that wait on them, then in file order" "US-002,US-009,US-011" \
   "$(printf '%s' "$N" | jq -r '[.plan[].id] | join(",")')"
eq "the plans to approve are the planned stories that are not blocked" "US-005" \
   "$(printf '%s' "$N" | jq -r '[.approve[].id] | join(",")')"

N=$(run "$P" project next stories.md --limit 4)
eq "the budget is the limit less the runs under way" "2" "$(printf '%s' "$N" | jq -r '.budget')"
eq "and the deliverables to start fill the budget in priority order" "US-006:a,b" \
   "$(printf '%s' "$N" | jq -r '[.start[] | "\(.id):\(.deliverables | join(","))"] | join(" ")')"

N=$(run "$P" project next stories.md --limit 9)
eq "a story under way starts its next deliverable, and a blocked plan starts nothing" "US-006:a,b,c US-007:z" \
   "$(printf '%s' "$N" | jq -r '[.start[] | "\(.id):\(.deliverables | join(","))"] | join(" ")')"
eq "each start names the plan to pass to the driver" "$P/tasks/s6/plan.yaml" \
   "$(printf '%s' "$N" | jq -r '.start[0].plan')"

Q=$(new_repo)
{ story US-001 T-1 "" "Not merged"; story US-002 T-2 "US-001" "Started early"; } > "$Q/stories.md"
plan "$Q" s2 T-2 2026-10-08 x z; deliverable "$Q" s2 x 2 1; deliverable "$Q" s2 z 1 0
git -C "$Q" add -A && git -C "$Q" commit -qm "Plan the story"
commit_on "$Q" br-s2-x x.txt "Half of x"
eq "a story under way whose dependency is not merged starts nothing more" "in-progress|0" \
   "$(run "$Q" project stories.md | jq -r '.stories[1].state')|$(run "$Q" project next stories.md --limit 9 | jq -r '.start | length')"

# --------------------------------------------------------------------------------
rm -rf "$V" "$P" "$O" "$Q" 2>/dev/null
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
