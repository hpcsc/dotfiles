#!/usr/bin/env bash
# Fixture-repo tests for clerk. No framework: each case builds a throwaway git repo,
# runs the command, and asserts on its JSON. Run with: tests/clerk-test.sh
#
# These exist because the two defects clerk replaces were mechanical rules stated
# correctly in prose and simply never enforced. A rule with no test is the same shape.

set -uo pipefail

CLERK="$(cd "$(dirname "$0")/.." && pwd)/link/common/dot-local/bin/clerk"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

# A repo with a deterministic identity, so commits do not depend on the caller's config.
new_repo() {
  local d
  # pwd -P because macOS symlinks /var -> /private/var: mktemp hands back the symlinked
  # path and git resolves the real one, so every path assertion would differ by prefix.
  d=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$d" init -q -b main
  git -C "$d" config user.email clerk@test
  git -C "$d" config user.name  Clerk
  # The caller's global config may sign commits; a fixture repo has no key and every
  # commit would fail silently into a cascade of unrelated assertion failures.
  git -C "$d" config commit.gpgsign false
  git -C "$d" config tag.gpgsign false
  printf 'seed\n' > "$d/README.md"
  git -C "$d" add -A && git -C "$d" commit -qm "Seed"
  printf '%s' "$d"
}

run() { (cd "$1" && shift && "$CLERK" "$@"); }

# --------------------------------------------------------------------------------
printf '\nprepare\n'

R=$(new_repo)
printf 'module x\n' > "$R/go.mod"
printf '{}\n' > "$R/package.json"
J=$(run "$R" prepare)
eq "detects every language, not just the first" \
   "Go JavaScript/TypeScript" "$(printf '%s' "$J" | jq -r '.languages | join(" ")')"
eq "falls back to detection when no config exists" \
   "go test ./...|detected: go.mod" \
   "$(printf '%s' "$J" | jq -r '.test_command')|$(printf '%s' "$J" | jq -r '.test_commands._source')"
eq "an untracked marker file leaves the tree dirty" "false" "$(printf '%s' "$J" | jq -r '.clean')"

git -C "$R" add -A && git -C "$R" commit -qm "Add markers"
eq "reports clean once committed" "true" "$(run "$R" prepare | jq -r '.clean')"

mkdir -p "$R/tasks"
cat > "$R/tasks/test-commands.json" <<'EOF'
{"default": "task test:all", "Go": "task test:unit"}
EOF
J=$(run "$R" prepare)
eq "committed config beats detection" "task test:all" "$(printf '%s' "$J" | jq -r '.test_command')"
eq "per-language entries survive"    "task test:unit" "$(printf '%s' "$J" | jq -r '.test_commands.Go')"

cat > "$R/tasks/.environment" <<'EOF'
{"test_command": "cached-and-should-lose", "go_tool_prefix": "mise exec -- "}
EOF
eq "a machine cache never shadows the team's config" \
   "task test:all" "$(run "$R" prepare | jq -r '.test_command')"
eq "but go_tool_prefix is read regardless of which won" \
   "mise exec -- " "$(run "$R" prepare | jq -r '.go_tool_prefix')"

rm "$R/tasks/test-commands.json"
eq "the cache is used when no config exists" \
   "cached-and-should-lose" "$(run "$R" prepare | jq -r '.test_command')"

# --------------------------------------------------------------------------------
printf '\nlearnings path\n'

R2=$(new_repo)
eq "in-tree when tasks/ is not ignored" \
   "$R2/tasks/learnings.md" "$(run "$R2" prepare | jq -r '.learnings_path')"

printf 'tasks/\n' > "$R2/.gitignore"
git -C "$R2" add -A && git -C "$R2" commit -qm "Ignore tasks"
case "$(run "$R2" prepare | jq -r '.learnings_path')" in
  "$HOME"/.claude/implement-learnings/*/learnings.md) ok "out-of-tree when tasks/ is gitignored" ;;
  *) bad "out-of-tree when tasks/ is gitignored" "under ~/.claude/implement-learnings" \
         "$(run "$R2" prepare | jq -r '.learnings_path')" ;;
esac

# --------------------------------------------------------------------------------
printf '\nworktree\n'

R3=$(new_repo)
WT="$R3/../wt-$(basename "$R3")"
git -C "$R3" worktree add -q -b feature "$WT" >/dev/null 2>&1
J=$(run "$WT" prepare)
eq "knows it is in a worktree"                "true"  "$(printf '%s' "$J" | jq -r '.in_worktree')"
eq "resolves the work tree it stands in"      "$(cd "$WT" && pwd -P)" "$(printf '%s' "$J" | jq -r '.work_tree')"
eq "resolves the main repo root separately"   "$(cd "$R3" && pwd -P)" "$(printf '%s' "$J" | jq -r '.repo_root')"
eq "reports the worktree's own branch"        "feature" "$(printf '%s' "$J" | jq -r '.branch')"

# --------------------------------------------------------------------------------
printf '\nnext and complete\n'

R5=$(new_repo)
mkdir -p "$R5/tasks"
cat > "$R5/tasks/story.md" <<'EOF'
### Task 1: Add the type
### Task 2: Wire the handler
### Task 3: Document it
EOF
cat > "$R5/tasks/story.json" <<'EOF'
{"story":"demo","tasks_file":"tasks/story.md","tasks":[
 {"n":1,"title":"Add the type","language":"Go","testable":true,"depends_on":[],"affected_files":["a.go"]},
 {"n":2,"title":"Wire the handler","language":"Go","testable":true,"depends_on":[1],"affected_files":["b.go"]},
 {"n":3,"title":"Document it","language":"Generic","testable":false,"depends_on":[2],"affected_files":["README.md"]}]}
EOF
printf 'package a\n' > "$R5/a.go"; printf 'package b\n' > "$R5/b.go"
git -C "$R5" add -A && git -C "$R5" commit -qm "Add plan"

J=$(run "$R5" next)
eq "picks the only unblocked task"        "1" "$(printf '%s' "$J" | jq -r '.task.n')"
eq "counts the blocked ones separately"   "2" "$(printf '%s' "$J" | jq -r '.blocked')"
eq "is not done while tasks remain"       "false" "$(printf '%s' "$J" | jq -r '.done')"

printf 'edit\n' >> "$R5/a.go"
run "$R5" next >/dev/null 2>&1
eq "refuses to start a task while one is in flight" "3" "$?"
eq "unless explicitly allowed" "1" "$(run "$R5" next --allow-dirty | jq -r '.task.n')"

C=$(run "$R5" finish 1 -- a.go)
eq "finish stages exactly the named files" "a.go" "$(printf '%s' "$C" | jq -r '.staged | join(",")')"
eq "and marks it done in the sidecar"        "true" "$(jq -r '.tasks[0].done' "$R5/tasks/story.json")"
eq "and stages the sidecar with the code"    "2"    "$(git -C "$R5" diff --cached --name-only | wc -l | tr -d ' ')"

run "$R5" finish 1 -- a.go >/dev/null 2>&1
eq "a done task is never redone" "2" "$?"

run "$R5" finish 2 -- does-not-exist.go >/dev/null 2>&1
eq "refuses to stage a path that does not exist" "2" "$?"

run "$R5" finish 2 >/dev/null 2>&1
eq "refuses to run without an explicit file list" "2" "$?"

git -C "$R5" commit -qm "Task 1"
J=$(run "$R5" next)
eq "the dependency unblocks once its task is done" "2" "$(printf '%s' "$J" | jq -r '.task.n')"
eq "and blocked drops accordingly"                        "1" "$(printf '%s' "$J" | jq -r '.blocked')"

run "$R5" finish 2 -- b.go >/dev/null && git -C "$R5" commit -qm "Task 2"
run "$R5" finish 3 -- README.md >/dev/null && git -C "$R5" commit -qm "Task 3"
J=$(run "$R5" next)
eq "reports done when every task is done" "true" "$(printf '%s' "$J" | jq -r '.done')"
eq "and hands back no task"                  "null" "$(printf '%s' "$J" | jq -r '.task')"

R6=$(new_repo); mkdir -p "$R6/tasks"; printf -- '- [ ] Task 1: x\n' > "$R6/tasks/s.md"
git -C "$R6" add -A && git -C "$R6" commit -qm "No sidecar"
run "$R6" next >/dev/null 2>&1
eq "next refuses without a sidecar rather than parsing prose" "2" "$?"

# --------------------------------------------------------------------------------
printf '\nverify\n'

R7=$(new_repo)
printf 'module x\n' > "$R7/go.mod"; printf 'package x\n' > "$R7/x.go"
git -C "$R7" add -A && git -C "$R7" commit -qm "Seed go"
git -C "$R7" switch -qc feat
printf 'package x\n\nfunc Orphan() {}\n\nfunc Used() {}\n' > "$R7/y.go"
printf 'package x\n\nfunc call() { Used() }\n' > "$R7/z.go"
git -C "$R7" add -A && git -C "$R7" commit -qm "Add symbols"

# A repo with no remote must still resolve a default branch. Getting this wrong made
# base == HEAD, which made every base..HEAD diff empty and every scoped check vacuous.
eq "resolves a default branch without a remote" "main" "$(run "$R7" prepare | jq -r '.default_branch')"
eq "and a base that is not HEAD" "false" \
   "$(run "$R7" prepare | jq -r '.base == null or (.base == "'"$(git -C "$R7" rev-parse HEAD)"'")')"

V=$(run "$R7" verify --all-closed)
eq "flags an exported symbol with no non-test caller" "Orphan" \
   "$(printf '%s' "$V" | jq -r '[.findings[] | select(.check=="dead-code") | .detail | split(" ")[0]] | join(",")')"

run "$R7" receipt --command "go test ./..." --passed >/dev/null
V=$(run "$R7" verify)
eq "a fresh passing receipt is not vacuous" "0" \
   "$(printf '%s' "$V" | jq -r '[.findings[] | select(.check=="vacuous-receipt")] | length')"
eq "warns when the symbol may still be wired later" "warn" \
   "$(printf '%s' "$V" | jq -r '.findings[] | select(.check=="dead-code") | .severity' | head -1)"

printf 'runner: no files changed, skip running tests\n' > "$R7/out.txt"
run "$R7" receipt --command "task test" --passed --output-file "$R7/out.txt" >/dev/null
eq "a green receipt whose output shows nothing ran is vacuous" "block" \
   "$(run "$R7" verify | jq -r '.findings[] | select(.check=="vacuous-receipt") | .severity')"
rm -f "$R7/out.txt"

printf 'staged\n' > "$R7/tail.go"; git -C "$R7" add "$R7/tail.go"
eq "staged-but-uncommitted work blocks" "block" \
   "$(run "$R7" verify | jq -r '.findings[] | select(.check=="staged-tail") | .severity')"

# --------------------------------------------------------------------------------
printf '\nreceipt and gate\n'

R4=$(new_repo)
mkdir -p "$R4/tasks"
cat > "$R4/tasks/story.md" <<'EOF'
### Task 1: Done
### Task 2: Not done
EOF
printf '{"tasks":[{"n":1,"title":"Done","depends_on":[],"done":true},{"n":2,"title":"Not done","depends_on":[],"done":false}]}\n' > "$R4/tasks/story.json"
git -C "$R4" add -A && git -C "$R4" commit -qm "Add tasks"

G=$(run "$R4" gate); RC=$?
eq "gate refuses while a task is open" "false" "$(printf '%s' "$G" | jq -r '.checks[] | select(.name=="tasks-complete") | .ok')"
eq "gate exits non-zero when not ok"        "1"     "$RC"
eq "no receipt recorded is reported as such" "false" "$(printf '%s' "$G" | jq -r '.checks[] | select(.name=="receipt-fresh") | .ok')"

jq '.tasks |= map(.done = true)' "$R4/tasks/story.json" > "$R4/tasks/t" && mv -f "$R4/tasks/t" "$R4/tasks/story.json"
git -C "$R4" add -A && git -C "$R4" commit -qm "Finish task 2"
eq "gate accepts a fully done breakdown" "true" \
   "$(run "$R4" gate | jq -r '.checks[] | select(.name=="tasks-complete") | .ok')"

run "$R4" receipt --command "task test" --passed >/dev/null
eq "a receipt at HEAD is fresh" "true" \
   "$(run "$R4" gate | jq -r '.checks[] | select(.name=="receipt-fresh") | .ok')"

printf 'a fix applied after the suite ran\n' >> "$R4/README.md"
git -C "$R4" add -A && git -C "$R4" commit -qm "Apply an audit fix"
eq "a receipt from before a later commit is stale" "false" \
   "$(run "$R4" gate | jq -r '.checks[] | select(.name=="receipt-fresh") | .ok')"
case "$(run "$R4" gate | jq -r '.checks[] | select(.name=="receipt-fresh") | .detail')" in
  *"the tree changed after the suite ran"*) ok "and says why, in the terms that matter" ;;
  *) bad "and says why" "mentions the tree changing" "$(run "$R4" gate | jq -r '.checks[] | select(.name=="receipt-fresh") | .detail')" ;;
esac

run "$R4" receipt --command "task test" --passed >/dev/null
eq "re-running the suite clears it" "true" \
   "$(run "$R4" gate | jq -r '.checks[] | select(.name=="receipt-fresh") | .ok')"

printf 'loose\n' > "$R4/loose.txt"
eq "an untracked file blocks the gate" "false" \
   "$(run "$R4" gate | jq -r '.checks[] | select(.name=="tree-clean") | .ok')"
rm "$R4/loose.txt"

eq "the audit predicate is never inferred" "false" \
   "$(run "$R4" gate | jq -r '.checks[] | select(.name=="audit-accepted") | .ok')"

G=$(run "$R4" gate --audit-accepted); RC=$?
eq "all four pass once the audit is asserted" "true" "$(printf '%s' "$G" | jq -r '.ok')"
eq "and the gate exits zero"                  "0"    "$RC"

# --------------------------------------------------------------------------------
printf '\nreceipt guards\n'

run "$R4" receipt --command "task test" --failed >/dev/null
eq "a failed receipt does not satisfy the gate" "false" \
   "$(run "$R4" gate --audit-accepted | jq -r '.checks[] | select(.name=="receipt-fresh") | .ok')"

run "$R4" receipt >/dev/null 2>&1
eq "receipt requires --command" "2" "$?"


# --------------------------------------------------------------------------------
printf '\nland\n'

R8=$(new_repo)
mkdir -p "$R8/tasks"
printf -- '### Task 1: Only task\n' > "$R8/tasks/feature.md"
printf '{"tasks":[{"n":1,"title":"Only task","depends_on":[],"done":false}]}\n' > "$R8/tasks/feature.json"
git -C "$R8" add -A && git -C "$R8" commit -qm "Plan"
git -C "$R8" switch -qc feature

L=$(run "$R8" land); RC=$?
eq "land refuses while the gate is shut" "false" "$(printf '%s' "$L" | jq -r '.landed')"
eq "and says the gate is why"            "gate did not open" "$(printf '%s' "$L" | jq -r '.reason')"
eq "and exits non-zero"                  "1" "$RC"

run "$R8" finish 1 -- tasks/feature.md >/dev/null 2>&1
git -C "$R8" add -A && git -C "$R8" commit -qm "Do task 1"
run "$R8" receipt --command "go test ./..." --passed >/dev/null

L=$(run "$R8" land --audit-accepted)
eq "archives the breakdown onto the feature branch" "tasks/completed/feature.md" \
   "$(printf '%s' "$L" | jq -r '.archived')"
eq "the archive commit is on the branch, not the default one" "feature" \
   "$(git -C "$R8" rev-parse --abbrev-ref HEAD)"
eq "the sidecar is archived alongside it" "1" \
   "$(ls "$R8"/tasks/completed/feature.json 2>/dev/null | wc -l | tr -d ' ')"
eq "and it does not land without being asked" "false" "$(printf '%s' "$L" | jq -r '.landed')"
eq "but it says how to land it"               "true"  \
   "$(printf '%s' "$L" | jq -r '.to_land | test("merge --ff-only")')"

run "$R8" receipt --command "go test ./..." --passed >/dev/null
L=$(run "$R8" land --integrate --audit-accepted)
eq "lands with --integrate"          "true"    "$(printf '%s' "$L" | jq -r '.landed')"
eq "onto the default branch"         "main"    "$(printf '%s' "$L" | jq -r '.base_branch')"
eq "deletes the feature branch"      "0"       "$(git -C "$R8" branch --list feature | wc -l | tr -d ' ')"
eq "and never pushes"                "false"   "$(printf '%s' "$L" | jq -r '.pushed')"


# --------------------------------------------------------------------------------
printf '\nsidecar recovery\n'

R9=$(new_repo)
mkdir -p "$R9/tasks"
cat > "$R9/tasks/legacy.md" <<'EOF'
# Legacy breakdown

## Progress
- [ ] Task 1: Add the event type
- [ ] Task 2: Wire the handler
- [ ] Task 3: Update the docs

## Tasks

### Task 1: Add the event type

**Behavior:** A new event exists.

**Affected Files/Modules:**
- `internal/events/order.go` — add the type
- `internal/events/order_test.go` — cover it

**Testable:** Yes

**Depends on:** None

### Task 2: Wire the handler

**Behavior:** The handler dispatches it.

**Affected Files/Modules:**
- `internal/handler/order.go` — dispatch

**Testable:** Yes

**Depends on:** Task 1

### Task 3: Update the docs

**Behavior:** Docs mention it.

**Affected Files/Modules:**
- `README.md` — document

**Testable:** No

**Depends on:** Tasks 1, 2
EOF
git -C "$R9" add -A && git -C "$R9" commit -qm "Legacy plan"

run "$R9" next >/dev/null 2>&1
eq "next refuses a breakdown with no sidecar" "2" "$?"

S=$(run "$R9" sidecar)
eq "sidecar recovers every task"          "3" "$(printf '%s' "$S" | jq -r '.tasks')"
eq "and says it read the task sections"   "sections" "$(printf '%s' "$S" | jq -r '.recovered_from')"
eq "None becomes an empty dependency list" "0" "$(jq -r '.tasks[0].depends_on | length' "$R9/tasks/legacy.json")"
eq "a single dependency is recovered"      "1" "$(jq -r '.tasks[1].depends_on | join(",")' "$R9/tasks/legacy.json")"
eq "and so are several"                    "1,2" "$(jq -r '.tasks[2].depends_on | join(",")' "$R9/tasks/legacy.json")"
eq "testable No is honoured"               "false" "$(jq -r '.tasks[2].testable' "$R9/tasks/legacy.json")"
eq "language is inferred from the files"   "Go" "$(jq -r '.tasks[0].language' "$R9/tasks/legacy.json")"
eq "affected files come across"            "internal/events/order.go" "$(jq -r '.tasks[0].affected_files[0]' "$R9/tasks/legacy.json")"
eq "titles survive"                        "Wire the handler" "$(jq -r '.tasks[1].title' "$R9/tasks/legacy.json")"

case "$(run "$R9" sidecar --force | jq -r '.next_step')" in
  *"commit it alongside the breakdown"*) ok "and says to commit it before carrying on" ;;
  *) bad "and says to commit it before carrying on" "a note about committing" "$(run "$R9" sidecar --force | jq -r '.next_step')" ;;
esac

git -C "$R9" add -A && git -C "$R9" commit -qm "Recover sidecar"
eq "next works once the sidecar exists" "1" "$(run "$R9" next | jq -r '.task.n')"
eq "and the recovered edges block the rest" "2" "$(run "$R9" next | jq -r '.blocked')"

eq "it refuses to clobber an existing sidecar" "false" "$(run "$R9" sidecar | jq -r '.written')"
eq "unless forced"                             "true"  "$(run "$R9" sidecar --force | jq -r '.written')"

# A breakdown with only a checklist yields numbers and titles but no edges — safe,
# because a breakdown is emitted in dependency order, but it must say so.
R10=$(new_repo); mkdir -p "$R10/tasks"
printf -- '- [ ] Task 1: First\n- [ ] Task 2: Second\n' > "$R10/tasks/bare.md"
git -C "$R10" add -A && git -C "$R10" commit -qm "Bare plan"
S=$(run "$R10" sidecar)
eq "falls back to the checklist when there are no sections" "checklist" "$(printf '%s' "$S" | jq -r '.recovered_from')"
eq "recovering both entries"                                "2" "$(printf '%s' "$S" | jq -r '.tasks')"
case "$(printf '%s' "$S" | jq -r '.note')" in
  *"every depends_on is empty"*) ok "and warns that no edges were recovered" ;;
  *) bad "and warns that no edges were recovered" "a note about empty depends_on" "$(printf '%s' "$S" | jq -r '.note')" ;;
esac

R11=$(new_repo); mkdir -p "$R11/tasks"; printf 'no tasks here at all\n' > "$R11/tasks/empty.md"
git -C "$R11" add -A && git -C "$R11" commit -qm "Empty"
run "$R11" sidecar >/dev/null 2>&1
eq "fails loudly when nothing parses" "2" "$?"


# The shapes that make a **Depends on:** line prose rather than a field.
R12=$(new_repo); mkdir -p "$R12/tasks"
cat > "$R12/tasks/prose.md" <<'EOF'
### Task 1: Independent one

**Affected Files/Modules:**
- `a.go` — x

**Depends on:** None (US-006 is on main). Independent of Task 3 — different writers.

### Task 2: Cross-story only

**Affected Files/Modules:**
- `b.go` — x

**Depends on:** US-007 Task 1 (`ast.ThenView`) and US-007 Task 2 (the rest)

### Task 3: Local plus cross-story

**Affected Files/Modules:**
- `c.go` — x

**Depends on:** Task 2 (for the helper), and **US-009 Task 1**, which must be on main

### Task 4: A range

**Affected Files/Modules:**
- `d.go` — x

**Depends on:** Tasks 1-3, and **all upstream** — US-007 Task 5, US-009 Task 1

### Task 5: A list joined by and

**Affected Files/Modules:**
- `e.go` — x

**Depends on:** Tasks 1, 3 and 4 — the section states what each one produces
EOF
git -C "$R12" add -A && git -C "$R12" commit -qm "Prose deps"
run "$R12" sidecar --tasks-file "$R12/tasks/prose.md" >/dev/null
eq "None wins over a task named as NOT a dependency" "0" "$(jq -r '.tasks[0].depends_on | length' "$R12/tasks/prose.json")"
eq "a purely cross-story dependency is not a local edge" "0" "$(jq -r '.tasks[1].depends_on | length' "$R12/tasks/prose.json")"
eq "a local edge survives beside a cross-story one" "2" "$(jq -r '.tasks[2].depends_on | join(",")' "$R12/tasks/prose.json")"
eq "a range expands"                                "1,2,3" "$(jq -r '.tasks[3].depends_on | join(",")' "$R12/tasks/prose.json")"
eq "a list joined by and does not fuse its numbers" "1,3,4" "$(jq -r '.tasks[4].depends_on | join(",")' "$R12/tasks/prose.json")"


# --------------------------------------------------------------------------------
printf '\nthe whole flow inside a worktree\n'

# The skill's primary shape is a worktree, and every task-file command was resolving
# the breakdown against the MAIN repo root — so `git add` rejected it as outside the
# repository and the run died on the first commit.
R13=$(new_repo)
mkdir -p "$R13/tasks"
printf -- '### Task 1: Only task\n' > "$R13/tasks/wt.md"
printf '{"tasks":[{"n":1,"title":"Only task","depends_on":[],"done":false}]}\n' > "$R13/tasks/wt.json"
printf 'package a\n' > "$R13/a.go"
git -C "$R13" add -A && git -C "$R13" commit -qm "Plan"
WT2="$R13/../wtflow-$(basename "$R13")"
git -C "$R13" worktree add -q -b flow "$WT2" >/dev/null 2>&1

eq "prepare finds the breakdown in the worktree" "$(cd "$WT2" && pwd -P)/tasks/wt.md" \
   "$(run "$WT2" prepare | jq -r '.tasks_file')"
eq "next reads the worktree's sidecar" "1" "$(run "$WT2" next | jq -r '.task.n')"

printf 'edit\n' >> "$WT2/a.go"
C=$(run "$WT2" finish 1 -- a.go); RC=$?
eq "complete succeeds inside a worktree" "0" "$RC"
eq "and stages the worktree's sidecar" "2" "$(git -C "$WT2" diff --cached --name-only | wc -l | tr -d ' ')"
eq "and records its state under the worktree git dir" "1" \
   "$(ls "$(git -C "$WT2" rev-parse --absolute-git-dir)/clerk/tasks"/*.json 2>/dev/null | wc -l | tr -d ' ')"
eq "the main checkout's sidecar is untouched" "false" \
   "$(jq -r '.tasks[0].done' "$R13/tasks/wt.json")"

git -C "$WT2" commit -qm "Task 1"
run "$WT2" receipt --command "go test ./..." --passed >/dev/null
eq "gate reads the worktree breakdown" "true" \
   "$(run "$WT2" gate --audit-accepted | jq -r '.checks[] | select(.name=="tasks-complete") | .ok')"

L=$(run "$WT2" land --audit-accepted)
eq "land archives inside the worktree" "tasks/completed/wt.md" "$(printf '%s' "$L" | jq -r '.archived')"
eq "and the archive landed on the worktree branch" "1" \
   "$(git -C "$WT2" log --oneline -1 --name-only | grep -c 'tasks/completed/wt.md' | tr -d ' ')"

run "$WT2" receipt --command "go test ./..." --passed >/dev/null
L=$(run "$WT2" land --integrate --audit-accepted)
eq "integrating from inside a worktree stops before the merge" "false" "$(printf '%s' "$L" | jq -r '.landed')"
case "$(printf '%s' "$L" | jq -r '.next_step')" in
  *"merge --ff-only"*) ok "and prints the command to run in the main checkout" ;;
  *) bad "and prints the command to run in the main checkout" "a merge --ff-only hint" "$(printf '%s' "$L" | jq -r '.next_step')" ;;
esac

git -C "$R13" worktree remove --force "$WT2" 2>/dev/null


# --------------------------------------------------------------------------------
# --------------------------------------------------------------------------------

# --------------------------------------------------------------------------------
printf '\nprogress lives in one place\n'

R14=$(new_repo); mkdir -p "$R14/tasks"
printf -- '### Task 1: One\n\n**Depends on:** None\n\n### Task 2: Two\n\n**Depends on:** Task 1\n' > "$R14/tasks/one.md"
printf 'package a\n' > "$R14/a.go"
git -C "$R14" add -A && git -C "$R14" commit -qm Plan
run "$R14" sidecar >/dev/null
git -C "$R14" add -A && git -C "$R14" commit -qm Sidecar

eq "a breakdown with no checkboxes works end to end" "1" "$(run "$R14" next | jq -r '.task.n')"
eq "status counts what is left"                      "0|2" \
   "$(run "$R14" status | jq -r '.done')|$(run "$R14" status | jq -r '.remaining')"

printf 'edit\n' >> "$R14/a.go"
run "$R14" finish 1 -- a.go >/dev/null
eq "finish needs no checkbox to record progress" "true" "$(jq -r '.tasks[0].done' "$R14/tasks/one.json")"
eq "and status follows"                          "1|1" \
   "$(run "$R14" status | jq -r '.done')|$(run "$R14" status | jq -r '.remaining')"
eq "status names what still blocks a task"       "" \
   "$(run "$R14" status | jq -r '.progress[1].blocked_by | join(",")')"

# The markdown is never rewritten now, so a task commit carries only code and sidecar.
eq "the breakdown itself is not touched" "0" \
   "$(git -C "$R14" diff --cached --name-only | grep -c 'one.md' | tr -d ' ')"

# Formatting must match between the two writers or the first finish reformats the file.
eq "finish does not reformat what sidecar wrote" "2" \
   "$(git -C "$R14" diff --cached -- tasks/one.json | grep -cE '^[-+][^-+]' | tr -d ' ')"

# A breakdown from before the change carries ticks; recovery must pick them up.
R15=$(new_repo); mkdir -p "$R15/tasks"
printf -- '- [x] Task 1: One\n- [ ] Task 2: Two\n\n### Task 1: One\n\n**Depends on:** None\n\n### Task 2: Two\n\n**Depends on:** Task 1\n' > "$R15/tasks/old.md"
git -C "$R15" add -A && git -C "$R15" commit -qm Plan
run "$R15" sidecar >/dev/null
eq "recovery seeds done from a legacy checklist" "true" "$(jq -r '.tasks[0].done' "$R15/tasks/old.json")"
eq "and leaves the unticked one open"            "false" "$(jq -r '.tasks[1].done' "$R15/tasks/old.json")"
eq "so next resumes where the run left off"      "2" "$(run "$R15" next --allow-dirty | jq -r '.task.n')"


# --------------------------------------------------------------------------------
printf '\nresuming, and the breakdown a run edits\n'

R16=$(new_repo); mkdir -p "$R16/tasks"
printf -- '### Task 1: One\n\n**Acceptance Criteria:**\n- [ ] first\n- [ ] second\n\n**Depends on:** None\n\n### Task 2: Two\n\n**Depends on:** Task 1\n' > "$R16/tasks/r.md"
printf 'package a\n' > "$R16/a.go"
git -C "$R16" add -A && git -C "$R16" commit -qm Plan
run "$R16" sidecar >/dev/null && git -C "$R16" add -A && git -C "$R16" commit -qm Sidecar

# A task section's acceptance criteria are ticked by hand as they are verified, so the
# breakdown stays a file the run edits even though progress left it.
printf 'edit\n' >> "$R16/a.go"
sed -i.bak 's/- \[ \] first/- [x] first/' "$R16/tasks/r.md" && rm -f "$R16/tasks/r.md.bak"
F=$(run "$R16" finish 1 -- a.go)
eq "finish stages a breakdown the run modified" "true" "$(printf '%s' "$F" | jq -r '.breakdown_staged')"
eq "so nothing is left dirty behind it"        "0" \
   "$(cd "$R16" && git status --porcelain | grep -c '^ M' | tr -d ' ')"

# An untouched breakdown is not swept into the commit.
git -C "$R16" commit -qm "Task 1"
printf 'more\n' >> "$R16/a.go"
F=$(run "$R16" finish 2 -- a.go)
eq "an untouched breakdown is left alone" "false" "$(printf '%s' "$F" | jq -r '.breakdown_staged')"
git -C "$R16" reset -q --hard HEAD

# prepare gives a resuming run what it needs to avoid starting over.
P=$(run "$R16" prepare)
eq "prepare lists the repo's worktrees"     "main" "$(printf '%s' "$P" | jq -r '.worktrees[0].branch')"
eq "and every breakdown with its progress"  "1|2" \
   "$(printf '%s' "$P" | jq -r '.breakdowns[0].done')|$(printf '%s' "$P" | jq -r '.breakdowns[0].total')"
eq "flagging one that is part-built"        "true|false" \
   "$(printf '%s' "$P" | jq -r '.breakdowns[0].started')|$(printf '%s' "$P" | jq -r '.breakdowns[0].finished')"

WT3="$R16/../wtr-$(basename "$R16")"
git -C "$R16" worktree add -q -b resumed "$WT3" >/dev/null 2>&1
eq "a worktree created for the feature is visible to prepare" "resumed" \
   "$(run "$R16" prepare | jq -r '.worktrees[] | select(.branch == "resumed") | .branch')"
git -C "$R16" worktree remove --force "$WT3" 2>/dev/null

# --------------------------------------------------------------------------------
rm -rf "$R" "$R2" "$R3" "$R4" "$R5" "$R6" "$R7" "$R8" "$R9" "$R10" "$R11" "$R12" "$R13" "$R14" "$R15" "$R16" "$WT" 2>/dev/null
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
