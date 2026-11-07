#!/usr/bin/env bash
# Fixture-repo tests for `feature`. No framework: each case builds a throwaway git repo
# with a proposal, stories files and plans under tasks/, and asserts on the JSON.
# Run with: tests/feature-test.sh
set -uo pipefail
BIN="$(cd "$(dirname "$0")/.." && pwd)/link/common/dot-local/bin"
FEATURE="$BIN/feature"
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

run() { (cd "$1" && shift && "$FEATURE" "$@"); }

# story <id> <ticket> <depends on> <title> [goals]
story() {
  printf '### %s: %s\n\n' "$1" "$4"
  [ -n "$2" ] && printf '**Ticket:** %s\n\n' "$2"
  printf '**Description:** As a user, I want %s.\n\n' "$4"
  [ -n "$3" ] && printf '**Depends on:** %s\n\n' "$3"
  [ -n "${5:-}" ] && printf '**Goals:** %s\n\n' "$5"
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

# plan <repo> <slug> <ticket or ""> <approved date or ""> <deliverable id>...
# A plan with no ticket names its story by STORY_ID, when the caller sets it.
plan() {
  local r=$1 slug=$2 ticket=$3 approved=$4 id
  shift 4
  mkdir -p "$r/tasks/$slug"
  { printf 'story: "%s"\nstory_slug: %s\n' "$slug" "$slug"
    [ -n "$ticket" ] && printf 'ticket: "%s"\n' "$ticket"
    [ -n "${STORY_ID:-}" ] && printf 'story_id: %s\n' "$STORY_ID"
    [ -n "$approved" ] && printf 'approved: %s\n' "$approved"
    printf 'deliverables:\n'
    for id in "$@"; do
      printf '  - id: %s\n    branch: br-%s-%s\n    base: main\n    wave: 1\n    depends_on: []\n    tasks: tasks/%s/%s/tasks.md\n' \
        "$id" "$slug" "$id" "$slug" "$id"
    done
  } > "$r/tasks/$slug/plan.yaml"
}

# defer <repo> <slug> <id>: the plan defers that deliverable
defer() {
  local f="$1/tasks/$2/plan.yaml"
  awk -v t="    tasks: tasks/$2/$3/tasks.md" '{ print } $0 == t { print "    status: deferred" }' "$f" > "$f.new" && /bin/mv -f "$f.new" "$f"
}

commit_on() {  # repo branch file message
  git -C "$1" checkout -q -B "$2"
  printf '%s\n' "$2" > "$1/$3"
  git -C "$1" add -A && git -C "$1" commit -qm "$4"
  git -C "$1" checkout -q main
}

# merge_ticket <repo> <ticket>: a commit on main that names the ticket
merge_ticket() {
  git -C "$1" commit -q --allow-empty -m "$(printf 'Do %s\n\nInitiative: [%s] Done' "$2" "$2")"
}

# --------------------------------------------------------------------------------
printf '\nthe stories file\n'

V=$(new_repo)
{ story US-001 "" "" "One"; } > "$V/no-ticket.md"
J=$(run "$V" no-ticket.md)
eq "a story with no ticket is keyed by the name of its file and its ID" "no-ticket/US-001|" \
   "$(printf '%s' "$J" | jq -r '.stories[0] | "\(.key)|\(.ticket // "")"')"
eq "and with no plan it is ready, and the evidence names its key" "ready|no plan names no-ticket/US-001" \
   "$(printf '%s' "$J" | jq -r '.stories[0] | "\(.state)|\(.evidence)"')"

{ story US-001 T-1 "US-404" "One"; } > "$V/unknown.md"
has "a dependency on a story the feature does not hold is refused" "unknown/US-001 -> unknown/US-404" \
   "$(run "$V" unknown.md 2>&1)"

{ story US-001 T-1 "US-002" "One"; story US-002 T-2 "US-001" "Two"; } > "$V/cycle.md"
has "a dependency cycle is refused, with the cycle named" "cycle/US-001 -> cycle/US-002 -> cycle/US-001" \
   "$(run "$V" cycle.md 2>&1)"

{ story US-001 T-1 "" "One"; story US-002 T-1 "" "Two"; } > "$V/shared.md"
has "two stories with one ticket are refused" "gives T-1 to more than one story" \
   "$(run "$V" shared.md 2>&1)"

{ printf '## Delivery Order\n\n```mermaid\n### US-009: Not a story\n```\n\n'
  story US-001 "[AGE-969](https://linear.app/x/issue/AGE-969/ask)" "None" "One"
  printf '## Non-Goals\n\n**Depends on:** US-404\n'
} > "$V/shape.md"
J=$(run "$V" shape.md)
eq "a heading inside a code block is not a story" "US-001" "$(printf '%s' "$J" | jq -r '[.stories[].id] | join(",")')"
eq "a ticket written as a link reads as its ID" "AGE-969" "$(printf '%s' "$J" | jq -r '.stories[0].ticket')"
eq "a section after the stories ends the last story" "" "$(printf '%s' "$J" | jq -r '.stories[0].depends_on | join(",")')"
eq "a repository with no plans reads every story without a plan" "ready" "$(printf '%s' "$J" | jq -r '.stories[0].state')"
eq "a stories file that names no proposal is a feature of its own, with no goals" "shape.md||0" \
   "$(printf '%s' "$J" | jq -r '"\(.feature)|\(.proposal // "")|\(.goals | length)"')"

eq "next refuses a limit below 1" "2" "$(run "$V" next shape.md --limit 0 >/dev/null 2>&1; echo $?)"
printf '# Notes\n\nNothing here.\n' > "$V/notes.md"
has "a file with no goal lines and no stories is refused" "neither a proposal" "$(run "$V" notes.md 2>&1)"

# --------------------------------------------------------------------------------
printf '\nthe delivery steps\n'

{ story US-001 T-1 ""               "Root"
  story US-002 T-2 "US-001"         "Left"
  story US-003 T-3 "US-001"         "Right"
  story US-004 T-4 "US-002, US-003" "Join"
  story US-005 T-5 ""               "Alone"
} > "$V/graph.md"
G=$(run "$V" graph.md)
eq "a story's step is one more than the step of its deepest dependency" "1,2,2,3,1" \
   "$(printf '%s' "$G" | jq -r '[.stories[].step] | map(tostring) | join(",")')"
eq "the stories on a longest chain are critical" "US-001,US-002,US-003,US-004" \
   "$(printf '%s' "$G" | jq -r '[.stories[] | select(.critical) | .id] | join(",")')"
eq "each story names the stories that wait on it directly, by key" "graph/US-002,graph/US-003" \
   "$(printf '%s' "$G" | jq -r '.stories[0].dependents | join(",")')"
GRAPH=$(run "$V" graph.md --graph)
eq "--graph puts the stories of each step together, with the critical ones marked" \
   "step 3  * graph/US-004  T-4       blocked        <- graph/US-002, graph/US-003" "$(grep 'US-004' <<<"$GRAPH")"
eq "and a story off the critical path has no mark" \
   "          graph/US-005  T-5       ready" "$(grep 'US-005' <<<"$GRAPH")"
eq "and it ends with the length of the critical path" "* critical path: 3 steps" "$(tail -1 <<<"$GRAPH")"

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

S=$(run "$P" stories.md)
st() { printf '%s' "$S" | jq -r --arg i "$1" '.stories[] | select(.id == $i) | .state'; }
field() { printf '%s' "$S" | jq -r --arg i "$1" --arg f "$2" '.stories[] | select(.id == $i) | .[$f] | if type == "array" then join(",") else tostring end'; }

eq "a story with no plan whose ticket is named on the default branch is merged" "merged" "$(st US-001)"
has "and the evidence says so" "name T-1" "$(field US-001 evidence)"
eq "a story whose dependencies are merged and that has no plan is ready" "ready" "$(st US-002)"
eq "a story whose dependency is not merged is blocked" "blocked|stories/US-002" "$(st US-003)|$(field US-003 blocked_by)"
eq "a plan made before its dependency merged still reads as blocked" "blocked" "$(st US-004)"
eq "a plan with no approved: line is planned" "planned" "$(st US-005)"
eq "a plan with an approved: line is approved" "approved" "$(st US-006)"
has "and the evidence gives the date" "2026-10-08" "$(field US-006 evidence)"
eq "a plan with a deliverable under way is in-progress" "in-progress" "$(st US-007)"
eq "and each deliverable carries what clerk story says of it, with its story slug" "s7|1|1/2|br-s7-x|tasks/s7/x/tasks.md" \
   "$(printf '%s' "$S" | jq -r '.stories[] | select(.id == "US-007") | .deliverables[] | select(.id == "x") |
      "\(.story_slug)|\(.wave)|\(.done)/\(.total)|\(.branch)|\(.tasks_file | sub(".*/tasks/s7/"; "tasks/s7/"))"')"
eq "a branch named after the ticket, with no plan, is in-progress" "in-progress" "$(st US-008)"
has "and the evidence names the branch" "t-8-by-hand" "$(field US-008 evidence)"
eq "a plan whose deliverables all merged is merged" "merged" "$(st US-010)"
eq "and the story that waits on it is ready" "ready|" "$(st US-011)|$(field US-011 blocked_by)"
eq "a plan whose deliverables are all built and not merged is awaiting-merge" "awaiting-merge" "$(st US-012)"
eq "unblocks counts the stories that wait directly and through another story" "3|2|0" \
   "$(field US-001 unblocks)|$(field US-002 unblocks)|$(field US-009 unblocks)"
eq "running counts the deliverables under way in every plan, also outside the feature" "other/y,s7/x" \
   "$(printf '%s' "$S" | jq -r '.running | sort | join(",")')"
eq "the stories keep the order of the file" "US-001,US-009,US-002" \
   "$(printf '%s' "$S" | jq -r '[.stories[:3][].id] | join(",")')"

O=$(new_repo)
{ story US-002 T-2 "US-001" "Listed first"; story US-001 T-1 "" "Listed second"; } > "$O/stories.md"
merge_ticket "$O" T-1
eq "a story whose dependency comes later in the file reads that dependency's state" "merged|ready" \
   "$(run "$O" stories.md | jq -r '[.stories[] | select(.id == "US-001", .id == "US-002") | .state] | reverse | join("|")')"
eq "--table gives one row for each story" "12" "$(run "$P" stories.md --table | grep -cE '^  stories/US-')"

D=$(new_repo)
{ story US-001 T-1 ""       "Merged but for a deferred deliverable"
  story US-002 T-2 ""       "Built but for a deferred deliverable"
  story US-003 T-3 "US-001" "Waits on a story whose rest is deferred"
} > "$D/stories.md"
plan "$D" s1 T-1 2026-10-01 m p; deliverable "$D" s1 m 1 1; deliverable "$D" s1 p 1 1; defer "$D" s1 p
plan "$D" s2 T-2 2026-10-01 f p; deliverable "$D" s2 f 1 1; deliverable "$D" s2 p 1 0; defer "$D" s2 p
git -C "$D" add -A && git -C "$D" commit -qm "Plan the stories"
commit_on "$D" br-s1-p p.txt "All of p, never merged"
commit_on "$D" br-s2-f f.txt "All of f"

SD=$(run "$D" stories.md)
sd() { printf '%s' "$SD" | jq -r --arg i "$1" '.stories[] | select(.id == $i) | .state'; }
eq "a plan whose deliverables merged but for a deferred one is merged" "merged" "$(sd US-001)"
has "and the evidence counts the deferred one" "except 1 deferred" \
    "$(printf '%s' "$SD" | jq -r '.stories[] | select(.id == "US-001") | .evidence')"
eq "a plan whose deliverables are built but for a deferred one is awaiting-merge" "awaiting-merge" "$(sd US-002)"
eq "and the story that waits on the merged one is ready" "ready" "$(sd US-003)"

# --------------------------------------------------------------------------------
printf '\na story with no ticket\n'

K=$(new_repo)
{ story US-001 "" "" "Planned by its key"; story US-002 "" "" "Done and archived"; story US-003 T-3 "" "Ticket and key"; } > "$K/stories.md"
STORY_ID=stories/US-001 plan "$K" s1 "" 2026-10-08 a; deliverable "$K" s1 a 1 0
STORY_ID=stories/US-003 plan "$K" s3 "" "" c;         deliverable "$K" s3 c 1 0
mkdir -p "$K/tasks/completed"
printf '# Done and archived\n' > "$K/tasks/completed/quick.md"
printf '{"story":"US-002: Done and archived","story_id":"stories/US-002","tasks":[{"n":1,"title":"t","depends_on":[],"done":true}]}\n' \
  > "$K/tasks/completed/quick.json"
git -C "$K" add -A && git -C "$K" commit -qm "Plan, and archive one"
SK=$(run "$K" stories.md --no-fetch)
sk() { printf '%s' "$SK" | jq -r --arg i "$1" '.stories[] | select(.id == $i) | .state'; }
eq "a plan that names the story_id of a story is the plan of that story" "approved" "$(sk US-001)"
eq "an archived breakdown that names the story_id makes its story merged" "merged" "$(sk US-002)"
eq "a story with a ticket also takes a plan that names its key" "planned" "$(sk US-003)"

R=$(new_repo)
mkdir -p "$R/user-stories/completed"
{ story US-001 "" "" "Done long ago"; story US-002 "" "" "Planned and not built"; story US-003 T-41 "US-001" "Started by hand"; } \
  > "$R/user-stories/completed/old.md"
{ story US-001 "" "" "Live"; } > "$R/user-stories/live.md"
STORY_ID=old/US-002 plan "$R" s2 "" 2026-10-08 a; deliverable "$R" s2 a 1 0
git -C "$R" add -A && git -C "$R" commit -qm "Archive the old stories"
commit_on "$R" t-41-by-hand h.txt "Started without a plan"
SR=$(run "$R" user-stories/completed/old.md --no-fetch)
sr() { printf '%s' "$SR" | jq -r --arg i "$1" '.stories[] | select(.id == $i) | "\(.state)|\(.evidence)"'; }
eq "a story with no plan in an archived stories file is merged, because the move says it is done" \
   "merged|user-stories/completed/old.md is archived, and no plan names old/US-001" "$(sr US-001)"
eq "a plan of a story in an archived stories file still decides its state" "approved" "$(sr US-002 | cut -d'|' -f1)"
eq "and so does a branch named after its ticket" "in-progress" "$(sr US-003 | cut -d'|' -f1)"
eq "a story with no plan in a live stories file stays ready" "ready" \
   "$(run "$R" user-stories/live.md --no-fetch | jq -r '.stories[0].state')"

# --------------------------------------------------------------------------------
printf '\ngoals\n'

Q=$(new_repo)
mkdir -p "$Q/docs/proposals" "$Q/user-stories"
cat > "$Q/docs/proposals/search.md" <<'EOF'
# Search

## Goals

- **G1:** Search answers in a second
- **G2:** Search covers the archive,
  and the old messages too
- **G3:** Search by voice (deferred)
- **G4:** Search in the app (moved to `docs/proposals/app.md`)
- **G5:** Nobody writes a story for this

```text
- **G9:** A goal inside a code block is not a goal
```
EOF
{ printf '# Search stories\n\n**Proposal:** `docs/proposals/search.md`\n\n## User Stories\n\n'
  story US-001 T-1 ""       "Fast"     "G1"
  story US-002 T-2 "US-001" "Archive"  "G1, G2"
  story US-003 T-3 ""       "Polish"
} > "$Q/user-stories/search.md"
git -C "$Q" add -A && git -C "$Q" commit -qm "Propose search"
merge_ticket "$Q" T-1
SQ=$(run "$Q" docs/proposals/search.md --no-fetch)
goal() { printf '%s' "$SQ" | jq -r --arg i "$1" --arg f "$2" '.goals[] | select(.id == $i) | .[$f] | if type == "array" then join(",") else tostring end'; }
eq "the goals are the G lines of the proposal, outside code blocks" "G1,G2,G3,G4,G5" \
   "$(printf '%s' "$SQ" | jq -r '[.goals[].id] | join(",")')"
eq "a goal goes on over its indented lines" "Search covers the archive, and the old messages too" "$(goal G2 text)"
eq "a goal that ends with (deferred) is deferred" "deferred|Search by voice" "$(goal G3 state)|$(goal G3 text)"
eq "a goal that ends with (moved to <path>) is moved, and names the path" "moved|docs/proposals/app.md|Search in the app" \
   "$(goal G4 state)|$(goal G4 moved_to)|$(goal G4 text)"
eq "a goal that no story names has no story" "no-story" "$(goal G5 state)"
eq "a goal names the stories that serve it" "search/US-001,search/US-002" "$(goal G1 stories)"
eq "and its state is the least advanced state of those stories" "ready" "$(goal G1 state)"
eq "a story that names no goal is outside the proposal" "search/US-003" \
   "$(printf '%s' "$SQ" | jq -r '.outside | join(",")')"
eq "the feature is named by its proposal and holds its stories files" "docs/proposals/search.md|user-stories/search.md|Search" \
   "$(printf '%s' "$SQ" | jq -r '"\(.feature)|\(.stories_files | join(","))|\(.title)"')"
eq "one merged story makes the feature in-progress" "in-progress" "$(printf '%s' "$SQ" | jq -r '.state')"
eq "and the evidence counts the stories and the goals, and names the gaps" \
   "1/3 stories merged; 2/5 goals done; G5 has no story; search/US-003 serves no goal" \
   "$(printf '%s' "$SQ" | jq -r '.evidence')"
eq "a stories file that names a proposal opens the feature of that proposal" "docs/proposals/search.md" \
   "$(run "$Q" user-stories/search.md --no-fetch | jq -r '.feature')"
has "--table lists the goals with the stories that serve them" "G1   ready          Search answers in a second  <- search/US-001, search/US-002" \
   "$(run "$Q" docs/proposals/search.md --table --no-fetch)"

{ printf '# More\n\n**Proposal:** `docs/proposals/search.md`\n\n'; story US-001 "" "" "Unknown goal" "G9"; } > "$Q/user-stories/more.md"
has "a story that names a goal the proposal does not have is refused" "more/US-001 names G9, and docs/proposals/search.md has no such goal" \
   "$(run "$Q" docs/proposals/search.md --no-fetch 2>&1)"
rm "$Q/user-stories/more.md"

{ story US-001 "" "" "Goal with no proposal" "G1"; } > "$Q/lonely.md"
has "a story that names a goal in a file with no proposal is refused" "lonely/US-001 names G1, and lonely.md names no proposal" \
   "$(run "$Q" lonely.md --no-fetch 2>&1)"
rm "$Q/lonely.md"

printf '# Twice\n\n- **G1:** One\n- **G1:** One again\n' > "$Q/docs/proposals/twice.md"
has "a proposal that names a goal twice is refused" "names G1 more than once" "$(run "$Q" docs/proposals/twice.md --no-fetch 2>&1)"
rm "$Q/docs/proposals/twice.md"

# --------------------------------------------------------------------------------
printf '\nthe state of a feature\n'

F=$(new_repo)
mkdir -p "$F/docs/proposals" "$F/user-stories"
printf '# Proposed\n\n- **G1:** Something\n' > "$F/docs/proposals/proposed.md"
eq "a proposal that no stories file names is proposed" "proposed|no stories file names docs/proposals/proposed.md; 0/1 goals done" \
   "$(run "$F" docs/proposals/proposed.md --no-fetch | jq -r '"\(.state)|\(.evidence)"')"

printf '# Ready\n\n- **G1:** Something\n' > "$F/docs/proposals/ready.md"
{ printf '# Ready stories\n\n**Proposal:** docs/proposals/ready.md\n\n'; story US-001 "" "" "One" "G1"; story US-002 "" "US-001" "Two" "G1"; } \
  > "$F/user-stories/ready.md"
eq "a feature whose stories are all ready or blocked is ready" "ready" \
   "$(run "$F" docs/proposals/ready.md --no-fetch | jq -r '.state')"

printf '# Gap\n\n- **G1:** Something\n- **G2:** Something more\n' > "$F/docs/proposals/gap.md"
{ printf '# Gap stories\n\n**Proposal:** docs/proposals/gap.md\n\n'; story US-001 T-21 "" "One" "G1"; } > "$F/user-stories/gap.md"
printf '# Done\n\n- **G1:** Something\n- **G2:** Not now (deferred)\n' > "$F/docs/proposals/done.md"
{ printf '# Done stories\n\n**Proposal:** docs/proposals/done.md\n\n'; story US-001 T-22 "" "One" "G1"; } > "$F/user-stories/done.md"
git -C "$F" add -A && git -C "$F" commit -qm "Propose"
merge_ticket "$F" T-21
merge_ticket "$F" T-22
eq "a feature whose stories are all merged, with a goal that has no story, is in-progress" "in-progress|G2 has no story" \
   "$(run "$F" docs/proposals/gap.md --no-fetch | jq -r '"\(.state)|\(.evidence | split("; ") | last)"')"
eq "a feature whose stories are merged, and whose other goals are deferred or moved, is merged" "merged" \
   "$(run "$F" docs/proposals/done.md --no-fetch | jq -r '.state')"

{ story US-001 T-23 "" "Alone"; } > "$F/user-stories/alone.md"
merge_ticket "$F" T-23
eq "a stories file with no proposal is merged when its stories are merged" "merged" \
   "$(run "$F" user-stories/alone.md --no-fetch | jq -r '.state')"

# --------------------------------------------------------------------------------
printf '\ntwo stories files for one proposal\n'

T=$(new_repo)
mkdir -p "$T/docs/proposals" "$T/user-stories"
printf '# Two phases\n\n- **G1:** First\n- **G2:** Second\n' > "$T/docs/proposals/phases.md"
{ printf '# Phase one\n\n**Proposal:** [the proposal](../docs/proposals/phases.md)\n\n'; story US-001 "" "" "First" "G1"; } > "$T/user-stories/one.md"
{ printf '# Phase two\n\n**Proposal:** `docs/proposals/phases.md`\n\n'; story US-001 "" "one/US-001" "Second" "G2"; } > "$T/user-stories/two.md"
ST=$(run "$T" docs/proposals/phases.md --no-fetch)
eq "both files hold a US-001, and the keys keep them apart" "one/US-001,two/US-001" \
   "$(printf '%s' "$ST" | jq -r '[.stories[].key] | join(",")')"
eq "a link in the **Proposal:** line reads from the folder of the stories file" "user-stories/one.md,user-stories/two.md" \
   "$(printf '%s' "$ST" | jq -r '.stories_files | join(",")')"
eq "a story can depend on a story in the other file of the feature" "blocked|one/US-001" \
   "$(printf '%s' "$ST" | jq -r '.stories[1] | "\(.state)|\(.blocked_by | join(","))"')"

{ printf '# Lost\n\n**Proposal:** docs/proposals/gone.md\n\n'; story US-001 "" "" "Lost"; } > "$T/user-stories/lost.md"
has "a stories file that names a proposal that does not exist is refused" "user-stories/lost.md names docs/proposals/gone.md, and that file does not exist" \
   "$(run "$T" user-stories/lost.md --no-fetch 2>&1)"

# --------------------------------------------------------------------------------
printf '\nlist\n'

L=$(run "$T" list --no-fetch)
eq "list names each feature: each proposal, and each stories file that names no proposal" \
   "docs/proposals/gone.md,docs/proposals/phases.md" "$(printf '%s' "$L" | jq -r '[.[].feature] | join(",")')"
eq "a feature that a check refuses is listed as refused, with the reason" "refused" \
   "$(printf '%s' "$L" | jq -r '.[] | select(.feature == "docs/proposals/gone.md") | .state')"
eq "each entry counts the stories and the goals" "phases.md|0/2|0/2" \
   "$(printf '%s' "$L" | jq -r '.[] | select(.feature == "docs/proposals/phases.md") | "phases.md|\(.stories_merged)/\(.stories_total)|\(.goals_done)/\(.goals_total)"')"
rm "$T/user-stories/lost.md"
mkdir -p "$T/docs/proposals/completed"
printf '# Old\n\n- **G1:** Old work\n' > "$T/docs/proposals/completed/old.md"
eq "a proposal under a completed/ folder is left out" "docs/proposals/phases.md" \
   "$(run "$T" list --no-fetch | jq -r '[.[].feature] | join(",")')"
eq "and --archived lists it" "docs/proposals/completed/old.md,docs/proposals/phases.md" \
   "$(run "$T" list --archived --no-fetch | jq -r '[.[].feature] | join(",")')"
eq "--table gives one row for each feature" \
   "ready          stories 0/2    goals 0/2   docs/proposals/phases.md  Two phases" "$(run "$T" list --table --no-fetch)"

# --------------------------------------------------------------------------------
printf '\narchive\n'

A=$(new_repo)
mkdir -p "$A/docs/proposals" "$A/user-stories"
printf '# Finished\n\n- **G1:** Something\n' > "$A/docs/proposals/finished.md"
{ printf '# Finished stories\n\n**Proposal:** `docs/proposals/finished.md`\n\n'; story US-001 T-31 "" "One" "G1"; } > "$A/user-stories/finished.md"
printf '# Open\n\n- **G1:** Something\n' > "$A/docs/proposals/open.md"
{ printf '# Open stories\n\n**Proposal:** `docs/proposals/open.md`\n\n'; story US-001 T-32 "" "One" "G1"; } > "$A/user-stories/open.md"
git -C "$A" add -A && git -C "$A" commit -qm "Propose"
merge_ticket "$A" T-31
eq "a feature that is not merged is not archived" "2" \
   "$(run "$A" archive docs/proposals/open.md --no-fetch >/dev/null 2>&1; echo $?)"
has "and the refusal gives its state" "the feature is ready" "$(run "$A" archive docs/proposals/open.md --no-fetch 2>&1)"
printf 'other work\n' > "$A/other.txt"; git -C "$A" add other.txt
AR=$(run "$A" archive docs/proposals/finished.md --no-fetch)
eq "a merged feature moves its proposal and its stories files to the completed/ folder beside each" \
   "docs/proposals/completed/finished.md,user-stories/completed/finished.md" \
   "$(printf '%s' "$AR" | jq -r '.archived | join(",")')"
eq "the **Proposal:** line names the proposal where it is now" "**Proposal:** \`docs/proposals/completed/finished.md\`" \
   "$(grep '^\*\*Proposal' "$A/user-stories/completed/finished.md")"
eq "one commit holds the move" "Archive feature: Finished" "$(git -C "$A" log -1 --format=%s)"
eq "and other staged work stays out of it" "A  other.txt" "$(git -C "$A" status --short)"
eq "the feature reads merged at its new path" "merged" \
   "$(run "$A" docs/proposals/completed/finished.md --no-fetch | jq -r '.state')"
has "and a second archive is refused" "archived already" \
   "$(run "$A" archive docs/proposals/completed/finished.md --no-fetch 2>&1)"

# --------------------------------------------------------------------------------
printf '\nnext\n'

N=$(run "$P" next stories.md)
eq "the default limit is 2, and two runs are under way, so nothing starts" "2|0|0" \
   "$(printf '%s' "$N" | jq -r '[.limit, .budget, (.start | length)] | join("|")')"
eq "the stories to plan come first by the stories that wait on them, then in file order" "US-002,US-009,US-011" \
   "$(printf '%s' "$N" | jq -r '[.plan[].id] | join(",")')"
eq "each one names its key and its stories file" "stories/US-002|stories.md" \
   "$(printf '%s' "$N" | jq -r '.plan[0] | "\(.key)|\(.stories_file)"')"
eq "the plans to approve are the planned stories that are not blocked" "US-005" \
   "$(printf '%s' "$N" | jq -r '[.approve[].id] | join(",")')"

N=$(run "$P" next stories.md --limit 4)
eq "the budget is the limit less the runs under way" "2" "$(printf '%s' "$N" | jq -r '.budget')"
eq "and the deliverables to start fill the budget in priority order" "US-006:a,b" \
   "$(printf '%s' "$N" | jq -r '[.start[] | "\(.id):\(.deliverables | join(","))"] | join(" ")')"

N=$(run "$P" next stories.md --limit 9)
eq "a story under way starts its next deliverable, and a blocked plan starts nothing" "US-006:a,b,c US-007:z" \
   "$(printf '%s' "$N" | jq -r '[.start[] | "\(.id):\(.deliverables | join(","))"] | join(" ")')"
eq "each start names the plan to pass to the driver" "$P/tasks/s6/plan.yaml" \
   "$(printf '%s' "$N" | jq -r '.start[0].plan')"

E=$(new_repo)
{ story US-001 T-1 "" "Not merged"; story US-002 T-2 "US-001" "Started early"; } > "$E/stories.md"
plan "$E" s2 T-2 2026-10-08 x z; deliverable "$E" s2 x 2 1; deliverable "$E" s2 z 1 0
git -C "$E" add -A && git -C "$E" commit -qm "Plan the story"
commit_on "$E" br-s2-x x.txt "Half of x"
eq "a story under way whose dependency is not merged starts nothing more" "in-progress|0" \
   "$(run "$E" stories.md | jq -r '.stories[1].state')|$(run "$E" next stories.md --limit 9 | jq -r '.start | length')"

H=$(new_repo)
{ story US-001 T-1 "" "Planned"; story US-002 T-2 "" "Approved"; story US-003 T-3 "" "Merged"; } > "$H/stories.md"
plan "$H" s1 T-1 ""         a
plan "$H" s2 T-2 2026-10-08 b m
plan "$H" s3 T-3 2026-10-01 c
affected() {  # repo slug id done files...
  local r=$1 slug=$2 id=$3 done=$4; shift 4
  mkdir -p "$r/tasks/$slug/$id"; printf '# %s\n' "$id" > "$r/tasks/$slug/$id/tasks.md"
  jq -n --argjson done "$done" '{tasks: [{n: 1, title: "t", depends_on: [], done: $done, affected_files: $ARGS.positional}]}' \
    --args "$@" > "$r/tasks/$slug/$id/tasks.json"
}
affected "$H" s1 a false shared.go one.go landed.go
affected "$H" s2 b false two.go shared.go
affected "$H" s2 m true  landed.go
affected "$H" s3 c true  shared.go
eq "next names the files that two stories in flight both plan to change, and leaves out merged deliverables" \
   '[{"stories":["stories/US-001","stories/US-002"],"files":["shared.go"]}]' \
   "$(run "$H" next stories.md | jq -c '.shared_files')"

# --------------------------------------------------------------------------------
rm -rf "$V" "$P" "$O" "$D" "$K" "$R" "$Q" "$F" "$T" "$A" "$E" "$H" 2>/dev/null
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
