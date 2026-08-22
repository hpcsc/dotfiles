#!/usr/bin/env bash
# Fixture-repo tests for `clerk step` and `clerk audit`. No framework: each case builds a
# throwaway git repo, runs the command, and asserts on its JSON. Run with:
# tests/clerk-step-test.sh
#
# The property under test is the one the step table claims: no step is reachable without
# the evidence of the step before it. Each row of the table gets at least one case that
# shows what holds it closed and what opens it.
set -uo pipefail
BIN="$(cd "$(dirname "$0")/.." && pwd)/link/common/dot-local/bin"
CLERK="$BIN/clerk"
# The dispatcher finds clerk-step on PATH; a fresh checkout has not stowed it yet.
export PATH="$BIN:$PATH"
# The worktree directory depends on this; the assertions read paths from output, but a
# deterministic run is easier to read when it fails.
unset CLAUDECODE
export CLERK_HARNESS=claude
PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

new_repo() {
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$d" init -q -b main
  git -C "$d" config user.email clerk@test
  git -C "$d" config user.name  Clerk
  git -C "$d" config commit.gpgsign false
  git -C "$d" config tag.gpgsign false
  printf 'seed\n' > "$d/README.md"
  git -C "$d" add -A && git -C "$d" commit -qm "Seed"
  printf '%s' "$d"
}
run() { (cd "$1" && shift && "$CLERK" "$@"); }
# Exit code of a command whose output is not wanted.
rc() { run "$@" >/dev/null 2>&1; printf '%s' $?; }
field() { jq -r "$1"; }

# A two-task breakdown whose sidecar takes extra per-task fields as a JSON object.
seed() {  # repo slug t1-extra t2-extra
  local repo=$1 slug=$2 x1=${3:-{\}} x2=${4:-{\}}
  mkdir -p "$repo/tasks"
  printf '# %s\n\n## Tasks\n\n### Task 1: One\n- [ ] a\n\n### Task 2: Two\n- [ ] b\n' "$slug" > "$repo/tasks/$slug.md"
  jq -n --arg s "$slug" --argjson x1 "$x1" --argjson x2 "$x2" \
    '{story: $s, tasks_file: ("tasks/" + $s + ".md"), tasks: [
       ({n: 1, title: "One", language: "Go", depends_on: [], affected_files: ["a.go"], done: false} + $x1),
       ({n: 2, title: "Two", language: "Go", depends_on: [1], affected_files: ["b.go"], done: false} + $x2)]}' \
    > "$repo/tasks/$slug.json"
}
commit_all() { git -C "$1" add -A && git -C "$1" commit -qm "$2"; }
# Walk a run to the point where every task is done and committed.
build_tasks() {  # dir
  printf 'a\n' > "$1/a.go"; run "$1" finish 1 -- a.go >/dev/null; commit_all "$1" "Task 1"
  printf 'b\n' > "$1/b.go"; run "$1" finish 2 -- b.go >/dev/null; commit_all "$1" "Task 2"
}

# --------------------------------------------------------------------------------
printf '\nstart — a run is opened with the request, once\n'

R=$(new_repo)
eq "a fresh repo has no run, and step says so" "start|null" \
   "$(run "$R" step | jq -r '[.step, (.run|tostring)] | join("|")')"
eq "and exits 0 — asking what to do is never an error" "0" "$(rc "$R" step)"
eq "--start without a request is a usage error" "2" "$(rc "$R" step --start w1)"
eq "the default branch is not a slug" "2" "$(rc "$R" step --start main --request x)"
eq "a name git would refuse is refused" "2" "$(rc "$R" step --start 'bad name' --request x)"
S=$(run "$R" step --start w1 --request "Add a widget --gears")
eq "--start opens the run" "true|w1" "$(printf '%s' "$S" | jq -r '[(.started|tostring), .run] | join("|")')"
eq "and returns the first step under next" "ground" "$(printf '%s' "$S" | jq -r '.next.step')"
eq "the ledger lives under the common git dir" "$R/.git/clerk/runs/w1" "$(printf '%s' "$S" | field .ledger)"
eq "the request is kept verbatim" "Add a widget --gears" "$(jq -r .request "$R/.git/clerk/runs/w1/run.json")"
eq "a second --start on an open run is refused" "3" "$(rc "$R" step --start w1 --request again)"
eq "and names the run it would have clobbered" "w1" \
   "$(run "$R" step --start w1 --request again 2>/dev/null | field .run.slug)"
eq "the first step is ground" "ground|derived" "$(run "$R" step | jq -r '[.step, .kind] | join("|")')"
eq "and its facts are clerk prepare, with the request's flags applied" "true|request" \
   "$(run "$R" step | jq -r '[(.facts.flags.gears|tostring), .facts.flag_sources.gears] | join("|")')"
eq "without a method step file the instructions say so and defer to done_by" "true|true" \
   "$(CLERK_METHOD_DIR="$R/no-method" run "$R" step --full | jq -r '[(.instructions | contains("no method text")), (.done_by | contains("clerk guidelines"))] | map(tostring) | join("|")')"

# --------------------------------------------------------------------------------
printf '\nground — the guidelines are recorded as read; a dirty tree stops the run\n'

printf 'loose\n' > "$R/loose.txt"
G=$(run "$R" step)
eq "a dirty tree at ground is blocked, not skipped" "ground|true|true" \
   "$(printf '%s' "$G" | jq -r '[.step, (.blocked|tostring), (.stop|tostring)] | join("|")')"
rm "$R/loose.txt"
eq "--done ground needs a known caller pattern" "2" "$(rc "$R" step --done ground --caller sideways)"
eq "--done ground with one is recorded" "ground|ui" \
   "$(run "$R" step --done ground --caller ui | jq -r '[.done, .caller] | join("|")')"
eq "--done returns the step that follows under next, as clerk step would print it" "isolate|worktree" \
   "$(run "$R" step --done ground --caller ui | jq -r '[.next.step, .next.action] | join("|")')"
eq "and the run moves to isolate" "isolate" "$(run "$R" step | field .step)"

# --------------------------------------------------------------------------------
printf '\nisolate — the run gets a branch of its own, and step follows it there\n'

I=$(run "$R" step)
eq "with in_place off the action is a worktree, named with the slug" "worktree|true" \
   "$(printf '%s' "$I" | jq -r '[.action, (.done_by | contains("clerk worktree w1") | tostring)] | join("|")')"
WT=$(run "$R" worktree w1 | field .path)
I=$(run "$R" step)
eq "once the worktree exists, step from the main checkout says enter it" "enter|$WT" \
   "$(printf '%s' "$I" | jq -r '[.action, .path] | join("|")')"
eq "inside the worktree the run is found by its branch" "w1|plan" \
   "$(run "$WT" step | jq -r '[.run, .step] | join("|")')"
eq "--status reports isolate as a worktree" "true|worktree" \
   "$(run "$WT" step --status | jq -r '.rows[] | select(.step == "isolate") | [(.done|tostring), .mode] | join("|")')"

# Two open runs from the main checkout is an ambiguity to name, not a guess.
run "$R" step --start w2 --request "Second" >/dev/null
eq "two open runs from the default branch is refused" "3" "$(rc "$R" step)"
eq "and both are listed" "w1 w2" "$(run "$R" step 2>/dev/null | jq -r '[.open_runs[].slug] | join(" ")')"
eq "--run names the one meant" "w2" "$(run "$R" step --run w2 | field .run)"
eq "a feature branch with no run of its own is a fresh start, with the open runs listed" "start|2" \
   "$(git -C "$R" checkout -q -b stray && run "$R" step | jq -r '[.step, (.open_runs|length|tostring)] | join("|")'; git -C "$R" checkout -q main)"
run "$R" step --rm w2 >/dev/null
eq "--rm removes a ledger" "false" "$([ -d "$R/.git/clerk/runs/w2" ] && echo true || echo false)"

RI=$(new_repo)
mkdir -p "$RI/tasks" && printf '{"in_place": true}\n' > "$RI/tasks/clerk.json" && commit_all "$RI" "Config"
run "$RI" step --start ip --request "In place" >/dev/null
run "$RI" step --done ground --caller inbound >/dev/null
eq "with in_place on the action is a branch" "branch" "$(run "$RI" step | field .action)"
run "$RI" branch ip >/dev/null
eq "on that branch isolate is done in place" "true|in-place|false" \
   "$(run "$RI" step --status | jq -r '.rows[] | select(.step == "isolate") | [(.done|tostring), .mode, (.fallback|tostring)] | join("|")')"

# --------------------------------------------------------------------------------
printf '\nplan — a breakdown is bound, and its assessments are linted before it counts\n'

eq "--done plan needs --tasks-file" "2" "$(rc "$WT" step --done plan)"
mkdir -p "$WT/tasks" && printf '### Task 1: Only\n' > "$WT/tasks/w1.md"
eq "a breakdown without a sidecar is refused" "1" "$(rc "$WT" step --done plan --tasks-file tasks/w1.md)"
eq "and says what recovers one" "true" \
   "$(run "$WT" step --done plan --tasks-file tasks/w1.md 2>/dev/null | jq -r '.reason | contains("clerk sidecar")')"
seed "$WT" w1 '{"certainty": "high", "blast_radius": "low", "patterns_to_follow": []}'
eq "a high certainty with no precedent is refused by the lint" "1" "$(rc "$WT" step --done plan --tasks-file tasks/w1.md)"
eq "with the findings in the reply" "1" \
   "$(run "$WT" step --done plan --tasks-file tasks/w1.md 2>/dev/null | jq -r '.findings | length')"
eq "and the run stays at plan" "plan" "$(run "$WT" step | field .step)"
seed "$WT" w1 '{"certainty": "low", "blast_radius": "low"}' '{"certainty": "high", "blast_radius": "high", "patterns_to_follow": ["task:1"]}'
B=$(run "$WT" step --done plan --tasks-file tasks/w1.md)
eq "--done plan returns the first task under next — here pausing for its tests" "tests|1" \
   "$(printf '%s' "$B" | jq -r '[.next.step, (.next.n|tostring)] | join("|")')"
eq "a clean sidecar binds" "true|2" "$(printf '%s' "$B" | jq -r '[(.bound|tostring), (.plan|length|tostring)] | join("|")')"
eq "and the reply is the plan table, certainty and blast radius included" "1:low/low 2:high/high" \
   "$(printf '%s' "$B" | jq -r '[.plan[] | "\(.n):\(.certainty)/\(.blast_radius)"] | join(" ")')"
eq "the bound path is absolute" "$WT/tasks/w1.md" "$(jq -r .tasks_file "$R/.git/clerk/runs/w1/breakdown.json")"
eq "--status shows plan done" "true" "$(run "$WT" step --status | jq -r '.rows[] | select(.step == "plan") | .done')"

# The lint is re-run when the sidecar changes under the binding.
jq '.tasks[1].patterns_to_follow = []' "$WT/tasks/w1.json" > "$WT/tasks/w1.tmp" && /bin/mv -f "$WT/tasks/w1.tmp" "$WT/tasks/w1.json"
eq "a sidecar edited into a finding reopens plan" "plan|1" \
   "$(run "$WT" step | jq -r '[.step, (.findings|length|tostring)] | join("|")')"
jq '.tasks[1].patterns_to_follow = ["task:1"]' "$WT/tasks/w1.json" > "$WT/tasks/w1.tmp" && /bin/mv -f "$WT/tasks/w1.tmp" "$WT/tasks/w1.json"
commit_all "$WT" "Breakdown"

RP=$(new_repo)
mkdir -p "$RP/tasks" && printf '{"review_plan": true, "in_place": true}\n' > "$RP/tasks/clerk.json" && commit_all "$RP" "Config"
run "$RP" step --start rp --request "Reviewed" >/dev/null; run "$RP" step --done ground --caller ui >/dev/null; run "$RP" branch rp >/dev/null
seed "$RP" rp
run "$RP" step --done plan --tasks-file tasks/rp.md >/dev/null
eq "with review_plan on the plan is a gate: bound but not approved" "plan|true" \
   "$(run "$RP" step | jq -r '[.step, (.stop|tostring)] | join("|")')"
run "$RP" step --done plan --tasks-file tasks/rp.md --approved >/dev/null
eq "--approved opens it" "task" "$(run "$RP" step | field .step)"

# --------------------------------------------------------------------------------
printf '\ntask — the first unblocked task, until none is open; gears pauses a hard one after its tests\n'

# w1 has --gears in its request and task 1 is low certainty.
T=$(run "$WT" step)
eq "a gears run pauses a low-certainty task before any code" "tests|1|true|asserted" \
   "$(printf '%s' "$T" | jq -r '[.step, (.n|tostring), (.stop|tostring), .kind] | join("|")')"
eq "--done tests needs the task number" "2" "$(rc "$WT" step --done tests)"
run "$WT" step --done tests 1 >/dev/null
T=$(run "$WT" step)
eq "shown, the same task is the step, and it says it paused" "task|1|true" \
   "$(printf '%s' "$T" | jq -r '[.step, (.n|tostring), (.pause_after_tests|tostring)] | join("|")')"
eq "with progress and its assessment on the task object" "0/2|low|low" \
   "$(printf '%s' "$T" | jq -r '[(.progress.done|tostring) + "/" + (.progress.total|tostring), .certainty, .blast_radius] | join("|")')"
eq "task 2 is blocked behind 1" "1" "$(printf '%s' "$T" | field .progress.blocked)"
printf 'a\n' > "$WT/a.go"
eq "a dirty tree mid-task is the task in flight, not a block" "task|true|false" \
   "$(run "$WT" step | jq -r '[.step, (.tree_dirty|tostring), (.blocked|tostring)] | join("|")')"
F=$(run "$WT" finish 1 -- a.go); commit_all "$WT" "Task 1"
eq "finish returns the step after the commit as after_commit — task 2, pausing for its tests" "tests|2" \
   "$(printf '%s' "$F" | jq -r '[.after_commit.step, (.after_commit.n|tostring)] | join("|")')"
T=$(run "$WT" step)
eq "once 1 is done and committed, 2 is next — and a high-blast task pauses too" "tests|2" \
   "$(printf '%s' "$T" | jq -r '[.step, (.n|tostring)] | join("|")')"
run "$WT" step --done tests 2 >/dev/null
printf 'b\n' > "$WT/b.go"; F=$(run "$WT" finish 2 -- b.go); commit_all "$WT" "Task 2"
eq "the last finish hands over the suite" "suite" "$(printf '%s' "$F" | jq -r '.after_commit.step')"
eq "every task done moves the run to suite" "suite" "$(run "$WT" step | field .step)"

# Without gears the assessments are reported and nothing pauses.
eq "a run without gears never pauses, and says when a task was not assessed" "task|false|true" \
   "$(run "$RP" step | jq -r '[.step, (.pause_after_tests|tostring), (.unassessed|tostring)] | join("|")')"

RC=$(new_repo)
run "$RC" step --start cyc --request "Cycle" >/dev/null; run "$RC" step --done ground --caller ui >/dev/null
git -C "$RC" checkout -q -b cyc
seed "$RC" cyc '{"depends_on": [2]}'
run "$RC" step --done plan --tasks-file tasks/cyc.md >/dev/null
eq "a dependency cycle is a block with a reason, not a silent stall" "task|true" \
   "$(run "$RC" step | jq -r '[.step, (.blocked|tostring)] | join("|")')"

# --------------------------------------------------------------------------------
printf '\nsuite — the receipt must be green at this code tree; a tasks/-only commit keeps it\n'

eq "no receipt: suite, with the reason" "suite|no suite receipt recorded" \
   "$(run "$WT" step | jq -r '[.step, .why_not_done] | join("|")')"
run "$WT" receipt --command "go test ./..." --failed >/dev/null
eq "a failed receipt does not open it" "true" "$(run "$WT" step | jq -r '.why_not_done | contains("failed")')"
run "$WT" receipt --command "go test ./..." --passed >/dev/null
eq "a green receipt at HEAD moves to audit" "audit" "$(run "$WT" step | field .step)"
printf '\nnotes\n' >> "$WT/tasks/w1.md"; commit_all "$WT" "Breakdown notes"
eq "a commit touching only tasks/ leaves the receipt fresh" "audit" "$(run "$WT" step | field .step)"
eq "step's code tree is the one clerk prepare reports" \
   "$(run "$WT" prepare | field .code_tree)" "$(run "$WT" step | field .code_tree)"
printf 'c\n' > "$WT/c.go"; commit_all "$WT" "Code after the suite"
eq "a commit touching code sends the run back to suite" "suite|true" \
   "$(run "$WT" step | jq -r '[.step, (.why_not_done | contains("code changed") | tostring)] | join("|")')"
run "$WT" receipt --command "go test ./..." --passed >/dev/null

# --------------------------------------------------------------------------------
printf '\naudit — rounds are recorded against a fresh receipt and a clean tree; acceptance is asserted\n'

A=$(run "$WT" step)
eq "the audit step hands over the request verbatim as the story" "Add a widget --gears" "$(printf '%s' "$A" | field .story)"
eq "and the base ref the work started from" "$(git -C "$WT" merge-base HEAD main)" "$(printf '%s' "$A" | field .base)"
REP=$(mktemp); printf '{"findings": [1, 2], "refuted": [3], "coverage_gaps": ["docs"], "lenses": ["semantic:Go"]}' > "$REP"
eq "a round needs a report" "2" "$(rc "$WT" audit round)"
printf 'x\n' > "$WT/probe.txt"
eq "a round on a dirty tree is refused — a verifier's residue is not the branch" "3" "$(rc "$WT" audit round --report "$REP")"
rm "$WT/probe.txt"
printf 'd\n' > "$WT/d.go"; commit_all "$WT" "More code"
eq "a round on a stale receipt is refused — the suite comes first" "3" "$(rc "$WT" audit round --report "$REP")"
run "$WT" receipt --command "go test ./..." --passed >/dev/null
eq "accepting with no round recorded is refused" "3" "$(rc "$WT" audit accept)"
run "$WT" audit plan --rounds 1 >/dev/null
RD=$(run "$WT" audit round --report "$REP")
eq "a round records its counts against the code tree" "true|1|2|1|1" \
   "$(printf '%s' "$RD" | jq -r '[(.recorded|tostring), (.round.n|tostring), (.round.findings|tostring), (.round.refuted|tostring), (.round.coverage_gaps|tostring)] | join("|")')"
eq "a second round past the plan is refused" "3" "$(rc "$WT" audit round --report "$REP")"
eq "--replan lets it through, on purpose" "2" "$(run "$WT" audit round --report "$REP" --replan 2 | field .round.n)"
eq "status shows both rounds" "2|2" "$(run "$WT" audit status | jq -r '[(.rounds_planned|tostring), (.rounds|length|tostring)] | join("|")')"
A=$(run "$WT" audit accept)
eq "accept records the acceptance" "true|2" "$(printf '%s' "$A" | jq -r '[(.accepted|tostring), (.rounds|tostring)] | join("|")')"
eq "and returns the step that follows under next" "validate" "$(printf '%s' "$A" | jq -r '.next.step')"
eq "and the run moves to validate" "validate" "$(run "$WT" step | field .step)"
printf 'e\n' > "$WT/e.go"; commit_all "$WT" "Fix after acceptance"
run "$WT" receipt --command "go test ./..." --passed >/dev/null
eq "code changed after acceptance reopens the audit" "audit|true" \
   "$(run "$WT" step | jq -r '[.step, (.why_not_done | contains("earlier code tree") | tostring)] | join("|")')"
eq "accept with no round at this tree needs --early and a reason" "3" "$(rc "$WT" audit accept)"
eq "given one, it is recorded" "trivial fix" "$(run "$WT" audit accept --early "trivial fix" | field .early)"

# --------------------------------------------------------------------------------
printf '\nvalidate — the request is re-read against the branch; a mismatch parks the run\n'

V=$(run "$WT" step)
eq "validate hands over the story and the log" "Add a widget --gears|true" \
   "$(printf '%s' "$V" | jq -r '[.story, ((.log|length) > 3 | tostring)] | join("|")')"
eq "and the four questions" "4" "$(printf '%s' "$V" | jq -r '.questions | length')"
eq "--resolved with nothing recorded is refused" "1" "$(rc "$WT" step --done validate --resolved)"
run "$WT" step --done validate --mismatch "no widget colour" >/dev/null
eq "a recorded mismatch blocks the run until the user decides" "validate|true|true" \
   "$(run "$WT" step | jq -r '[.step, (.blocked|tostring), (.stop|tostring)] | join("|")')"
run "$WT" step --done validate --resolved >/dev/null
eq "resolved, the run moves to theory" "theory" "$(run "$WT" step | field .step)"

# --------------------------------------------------------------------------------
printf '\ntheory — the breakdown carries a Theory section, committed when tracked\n'

eq "no section: the reason names the file" "true" "$(run "$WT" step | jq -r '.why_not_done | contains("## Theory")')"
printf '## Theory\n\nOne abstraction.\n\n' | cat - "$WT/tasks/w1.md" > "$WT/tasks/w1.tmp" && /bin/mv -f "$WT/tasks/w1.tmp" "$WT/tasks/w1.md"
eq "written but not committed is not done" "true" "$(run "$WT" step | jq -r '.why_not_done | contains("not committed")')"
commit_all "$WT" "Theory"
eq "committed, the run moves on" "verify" "$(run "$WT" step | field .step)"

# --------------------------------------------------------------------------------
printf '\nverify — clerk verify runs; blocks hold, residue is asserted reviewed\n'

eq "verify is reached with the receipt still fresh — the Theory commit touched only tasks/" "verify|true" \
   "$(run "$WT" step | jq -r '[.step, (.verify.clean | tostring)] | join("|")')"
Y=$(run "$WT" step)
eq "clean with residue is asserted: not_checked is non-empty" "verify|asserted|true" \
   "$(printf '%s' "$Y" | jq -r '[.step, .kind, ((.verify.not_checked|length) > 0 | tostring)] | join("|")')"
run "$WT" step --done verify-residue >/dev/null
eq "--done verify-residue opens it" "land" "$(run "$WT" step | field .step)"

# --------------------------------------------------------------------------------
printf '\nland — archive, then integrate only when asked; step follows the run to the main checkout\n'

eq "not archived: land, with the command" "true" "$(run "$WT" step | jq -r '.done_by | contains("clerk land")')"
eq "the gate opens on the acceptance clerk audit recorded — no flag needed" "true|true" \
   "$(run "$WT" gate | jq -r '[(.checks[] | select(.name == "audit-accepted") | .ok | tostring), (.ok|tostring)] | join("|")')"
run "$WT" land >/dev/null
eq "archived without integration: the run is landed on its branch" "learn" "$(run "$WT" step | field .step)"
eq "--done learn needs nothing else when there is nothing to record" "learn|true" \
   "$(run "$WT" step --done learn --none | jq -r '[.done, (.none|tostring)] | join("|")')"
eq "and the run is finished" "finished" "$(run "$WT" step | field .step)"
eq "which the ledger records" "true" "$(jq -r .finished "$R/.git/clerk/runs/w1/run.json")"
eq "a finished slug can be started again" "true" "$(run "$WT" step --start w1 --request "Round two" | field .started)"
run "$WT" step --rm w1 >/dev/null

# Integration from a worktree finishes in the main checkout, and step follows.
RL=$(new_repo)
run "$RL" step --start lz --request "Land it" >/dev/null; run "$RL" step --done ground --caller ui >/dev/null
WL=$(run "$RL" worktree lz | field .path)
seed "$WL" lz; run "$WL" step --done plan --tasks-file tasks/lz.md >/dev/null; commit_all "$WL" "Breakdown"
build_tasks "$WL"
run "$WL" receipt --command true --passed >/dev/null
run "$WL" audit round --report "$REP" >/dev/null; run "$WL" audit accept >/dev/null
run "$WL" step --done validate >/dev/null
printf '## Theory\n\nX.\n\n' | cat - "$WL/tasks/lz.md" > "$WL/tasks/lz.tmp" && /bin/mv -f "$WL/tasks/lz.tmp" "$WL/tasks/lz.md"; commit_all "$WL" "Theory"
run "$WL" receipt --command true --passed >/dev/null
run "$WL" step --done verify-residue >/dev/null
eq "the worktree run reaches land" "land" "$(run "$WL" step | field .step)"
eq "land --integrate inside a worktree stops before the fast-forward" "3" "$(rc "$WL" land --audit-accepted --integrate)"
eq "its stamp records that integration was asked for, by the request" "true|false|request" \
   "$(jq -r '[(.integrate|tostring), (.landed|tostring), .integrate_source] | join("|")' "$RL/.git/clerk/runs/lz/land.json")"
eq "and step reads the stamp — no config says integrate — and says to finish from the main checkout" "true" \
   "$(run "$WL" step | jq -r '.done_by | contains("leave the worktree")')"
L=$(run "$RL" step)
eq "from the main checkout the same run is found, at land" "lz|land" "$(printf '%s' "$L" | jq -r '[.run, .step] | join("|")')"
eq "with the fast-forward command" "true" "$(printf '%s' "$L" | jq -r '.done_by | contains("merge --ff-only lz")')"
git -C "$RL" merge -q --ff-only lz && git -C "$RL" worktree remove "$WL" && git -C "$RL" branch -qd lz
eq "merged and gone, the run moves to learn in the main checkout" "learn" "$(run "$RL" step | field .step)"
eq "whose learnings path is reported" "$RL/tasks/learnings.md" "$(run "$RL" step | field .learnings_path)"

# --------------------------------------------------------------------------------
printf '\ninstructions — the method step file is printed when it exists, seams resolved per harness\n'

MD=$(mktemp -d); mkdir -p "$MD/implement/steps" "$MD/implement/seams/claude" "$MD/implement/seams/opencode" "$MD/shared"
printf 'Ground yourself.\n{{seam:enter}}\n{{include:shared/note.md}}\n' > "$MD/implement/steps/ground.md"
printf 'EnterWorktree\n' > "$MD/implement/seams/claude/enter.md"
printf 'cd into it\n' > "$MD/implement/seams/opencode/enter.md"
printf 'shared note\n' > "$MD/shared/note.md"
RM=$(new_repo); run "$RM" step --start m --request "Method" >/dev/null
eq "the step file replaces the built-in text, with the claude seam" "Ground yourself.|EnterWorktree|shared note" \
   "$(CLERK_METHOD_DIR="$MD/implement" run "$RM" step --full | jq -r '.instructions | split("\n") | join("|")')"
# The text travels once per step per session; the same step asked again is a pointer.
eq "the same step asked again is a pointer that names --full" "true|true" \
   "$(CLERK_METHOD_DIR="$MD/implement" run "$RM" step | jq -r '[(.instructions_elided|tostring), (.instructions | contains("clerk step --full") | tostring)] | join("|")')"
eq "another session is sent the text" "false|Ground yourself." \
   "$(CLAUDE_CODE_SESSION_ID=elsewhere CLERK_METHOD_DIR="$MD/implement" run "$RM" step | jq -r '[(.instructions_elided|tostring), (.instructions | split("\n") | .[0])] | join("|")')"
eq "and the opencode seam when asked" "cd into it" \
   "$(CLERK_METHOD_DIR="$MD/implement" run "$RM" step --harness opencode --full | jq -r '.instructions | split("\n") | .[1]')"

# The real method: the step files the generator concatenates are the ones step prints.
REAL="$(cd "$BIN/../dot-config/.config/ai/method/implement" && pwd -P)"
eq "ground prints Phase 0 of the method, with the shared prepare fragment resolved" "true|true" \
   "$(CLERK_METHOD_DIR="$REAL" run "$RM" step --full | jq -r '[(.instructions | contains("## Phase 0: Ground yourself") | tostring), (.instructions | contains("clerk prepare --request") | tostring)] | join("|")')"
eq "a step change prints the new step's text in full, unasked" "isolate|false" \
   "$(CLERK_METHOD_DIR="$REAL" run "$RM" step --done ground --caller ui | jq -r '[.next.step, (.next.instructions_elided|tostring)] | join("|")')"
eq "isolate prints the claude worktree seam" "true" \
   "$(CLERK_METHOD_DIR="$REAL" run "$RM" step --full | jq -r '.instructions | contains("### Set up an isolated worktree")')"
eq "or the opencode one" "true" \
   "$(CLERK_METHOD_DIR="$REAL" run "$RM" step --harness opencode --full | jq -r '.instructions | contains("### Isolate the work")')"

# --------------------------------------------------------------------------------
printf '\nevents — the commands that produce evidence log their run to the ledger on the way out\n'

RE=$(new_repo)
run "$RE" receipt --command x --passed >/dev/null
eq "without a run, nothing is logged and nothing is created" "false" "$([ -d "$RE/.git/clerk/runs" ] && echo true || echo false)"
run "$RE" step --start ev --request "Events" >/dev/null
run "$RE" receipt --command "go test ./..." --passed >/dev/null
EV="$RE/.git/clerk/runs/ev/events.jsonl"
eq "from the default branch, the one open run is the ledger" "receipt|--command go test ./... --passed|0" \
   "$(tail -1 "$EV" | jq -r '[.cmd, (.argv | join(" ")), (.exit|tostring)] | join("|")')"
eq "and the event carries the HEAD it ran at" "$(git -C "$RE" rev-parse HEAD)" "$(tail -1 "$EV" | jq -r .head)"
run "$RE" lint --rule certainty-unevidenced --json README.md >/dev/null 2>&1
eq "a logged plugin is recorded too" "lint|0" "$(tail -1 "$EV" | jq -r '[.cmd, (.exit|tostring)] | join("|")')"
eq "an exit other than 0 is recorded as it happened" "land|1" \
   "$(run "$RE" land >/dev/null 2>&1; tail -1 "$EV" | jq -r '[.cmd, (.exit|tostring)] | join("|")')"
eq "a usage error dies before the log and is not evidence" "land|1" \
   "$(run "$RE" finish 9 -- nope >/dev/null 2>&1; tail -1 "$EV" | jq -r '[.cmd, (.exit|tostring)] | join("|")')"
eq "reads are not logged" "3" "$(run "$RE" prepare >/dev/null; run "$RE" status >/dev/null 2>&1; run "$RE" step >/dev/null; wc -l < "$EV" | tr -d ' ')"
WE=$(run "$RE" worktree ev | field .path)
eq "worktree is logged against the run it isolates" "worktree|ev" "$(tail -1 "$EV" | jq -r '[.cmd, .argv[0]] | join("|")')"
run "$WE" receipt --command inner --passed >/dev/null
eq "inside the worktree the branch names the ledger" "receipt|inner" "$(tail -1 "$EV" | jq -r '[.cmd, .argv[1]] | join("|")')"
run "$RE" step --start ev2 --request "Second" >/dev/null
run "$RE" receipt --command ambiguous --passed >/dev/null
eq "two open runs from the default branch: nothing is logged rather than the wrong ledger" "0" \
   "$(cat "$EV" "$RE/.git/clerk/runs/ev2/events.jsonl" 2>/dev/null | grep -c ambiguous)"

# land leaves a stamp with what it decided, before and after integration.
RJ=$(new_repo)
mkdir -p "$RJ/tasks" && printf '{"in_place": true, "integrate": true}\n' > "$RJ/tasks/clerk.json" && commit_all "$RJ" "Config"
run "$RJ" step --start ij --request "In place, integrated" >/dev/null; run "$RJ" step --done ground --caller ui >/dev/null
run "$RJ" branch ij >/dev/null
seed "$RJ" ij; run "$RJ" step --done plan --tasks-file tasks/ij.md >/dev/null; commit_all "$RJ" "Breakdown"
build_tasks "$RJ"
run "$RJ" receipt --command true --passed >/dev/null
run "$RJ" audit round --report "$REP" >/dev/null; run "$RJ" audit accept >/dev/null
run "$RJ" step --done validate >/dev/null
printf '## Theory\n\nX.\n\n' | cat - "$RJ/tasks/ij.md" > "$RJ/tasks/ij.tmp" && /bin/mv -f "$RJ/tasks/ij.tmp" "$RJ/tasks/ij.md"; commit_all "$RJ" "Theory"
run "$RJ" receipt --command true --passed >/dev/null
run "$RJ" step --done verify-residue >/dev/null
eq "the in-place run reaches land" "land" "$(run "$RJ" step | field .step)"
LJ=$(run "$RJ" land --audit-accepted)
eq "land --integrate in place fast-forwards and deletes the branch" "true|ij" \
   "$(printf '%s' "$LJ" | jq -r '[(.landed|tostring), .deleted_branch] | join("|")')"
eq "and the stamp says so, with where integration was decided" "true|true|tasks/clerk.json|true" \
   "$(jq -r '[(.landed|tostring), (.integrate|tostring), .integrate_source, (.deleted_branch|tostring)] | join("|")' "$RJ/.git/clerk/runs/ij/land.json")"
eq "the land event is logged to the run although it ended on main" "land|0" \
   "$(tail -1 "$RJ/.git/clerk/runs/ij/events.jsonl" | jq -r '[.cmd, (.exit|tostring)] | join("|")')"
eq "and step, from main, moves the run to learn" "learn" "$(run "$RJ" step | field .step)"
eq "the learn step carries what the run observed about the plan" "0|0" \
   "$(run "$RJ" step | jq -r '[(.plan_signals.fixup_ambiguous|tostring), (.plan_signals.high_certainty_but_hard|length|tostring)] | join("|")')"
LN=$(run "$RJ" learn --type convention --title "Keep it" --learning "A fact." --apply-when "Always." --feature ij --path "$RJ/learned.md")
eq "a clerk learn write is the evidence: no --done needed, and learn hands over the end" "finished" \
   "$(printf '%s' "$LN" | jq -r '.next.step')"
eq "which stamps the run finished" "true" "$(jq -r '.finished' "$RJ/.git/clerk/runs/ij/run.json")"

# --------------------------------------------------------------------------------
printf '\nsignals — ground is the guidelines run; gears shifts on what the run observed\n'

GD=$(mktemp -d)
RG=$(new_repo)
run "$RG" step --start g --request "Guided" >/dev/null
run "$RG" guidelines --guidelines-dir "$GD" --language Go >/dev/null 2>&1
eq "clerk guidelines without a caller pattern does not ground the run" "ground" "$(run "$RG" step | field .step)"
run "$RG" guidelines --guidelines-dir "$GD" --language Go --caller async >/dev/null 2>&1
eq "with one, the run is grounded by the event — no --done" "isolate" "$(run "$RG" step | field .step)"
eq "and --status names the source" "true" "$(run "$RG" step --status | jq -r '.rows[] | select(.step == "ground") | .done')"

# Five unassessed tasks in a chain, gears on: nothing pauses until the run observes a signal.
seed_chain() {  # repo slug n
  local repo=$1 slug=$2 n=$3 i
  mkdir -p "$repo/tasks"
  { printf '# %s\n\n## Tasks\n\n' "$slug"; for i in $(seq 1 "$n"); do printf '### Task %s: T%s\n- [ ] c\n\n' "$i" "$i"; done; } > "$repo/tasks/$slug.md"
  jq -n --arg s "$slug" --argjson n "$n" \
    '{story: $s, tasks_file: ("tasks/" + $s + ".md"),
      tasks: [range(1; $n + 1) | {n: ., title: ("T" + tostring), language: "Go", depends_on: (if . == 1 then [] else [. - 1] end), affected_files: [], done: false}]}' \
    > "$repo/tasks/$slug.json"
}
RS=$(new_repo)
mkdir -p "$RS/tasks" && printf '{"in_place": true, "gears": true}\n' > "$RS/tasks/clerk.json" && commit_all "$RS" "Config"
run "$RS" step --start sg --request "Shifting" >/dev/null; run "$RS" step --done ground --caller ui >/dev/null; run "$RS" branch sg >/dev/null
seed_chain "$RS" sg 5; run "$RS" step --done plan --tasks-file tasks/sg.md >/dev/null; commit_all "$RS" "Breakdown"
eq "an unassessed task in a gears run builds straight through, gear normal" "task|1|normal|false" \
   "$(run "$RS" step | jq -r '[.step, (.n|tostring), .gear, (.pause_after_tests|tostring)] | join("|")')"
printf 'a\n' > "$RS/a.go"; run "$RS" finish 1 --retried -- a.go >/dev/null; commit_all "$RS" "T1"
eq "a retried task downshifts the run: the next task pauses" "tests|2|low|true" \
   "$(run "$RS" step | jq -r '[.step, (.n|tostring), .gear, (.why_not_done | contains("downshifted") | tostring)] | join("|")')"
eq "and the signal that did it is reported" "true|false" \
   "$(run "$RS" step | jq -r '[(.last_task_signals.retried|tostring), (.last_task_signals.lint_findings|tostring)] | join("|")')"
run "$RS" step --done tests 2 >/dev/null
printf 'b\n' > "$RS/b.go"; run "$RS" finish 2 -- b.go >/dev/null; commit_all "$RS" "T2"
eq "one clean task is not enough to upshift" "tests|3|low" "$(run "$RS" step | jq -r '[.step, (.n|tostring), .gear] | join("|")')"
run "$RS" step --done tests 3 >/dev/null
printf 'c\n' > "$RS/c.go"; run "$RS" finish 3 -- c.go >/dev/null; commit_all "$RS" "T3"
eq "two clean tasks in a row upshift: the next builds straight through" "task|4|normal|false" \
   "$(run "$RS" step | jq -r '[.step, (.n|tostring), .gear, (.pause_after_tests|tostring)] | join("|")')"
printf 'package d\n\n// Fixes ABC-123\nvar D = 1\n' > "$RS/d.go"
eq "a finish whose staged set has a lint finding is refused, and that refusal is on the record" "1" "$(rc "$RS" finish 4 -- d.go)"
printf 'package d\n\nvar D = 1\n' > "$RS/d.go"; run "$RS" finish 4 -- d.go >/dev/null; commit_all "$RS" "T4"
eq "and it downshifts again, naming the lint" "tests|5|low|true" \
   "$(run "$RS" step | jq -r '[.step, (.n|tostring), .gear, (.last_task_signals.lint_findings|tostring)] | join("|")')"

# --------------------------------------------------------------------------------
rm -rf "$R" "$RI" "$RP" "$RC" "$RL" "$RM" "$RE" "$RJ" "$RG" "$RS" "$GD" "$MD" "$REP" 2>/dev/null
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
