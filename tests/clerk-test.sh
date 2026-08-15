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
printf '\ndangling flags\n'

# `shift 2` with one argument left does nothing and returns 1, and nothing here runs
# under `set -e` — so an unguarded value flag loops forever rather than erroring, and
# the caller sees a timeout with no reason to suspect its own command line.
RD=$(new_repo)
for flag in "prepare --request" "next --tasks-file" "status --tasks-file" \
            "receipt --command" "gate --tasks-file" "land --tasks-file" \
            "verify --tasks-file" "worktree w --base"; do
  # `exec` so the subshell is REPLACED by clerk and $! is clerk's own pid. Backgrounding
  # a subshell that then runs clerk makes $! the subshell, and killing that orphans the
  # spinning child onto pid 1 — where, this being a test for an infinite loop, it sits at
  # 100% of a core until someone notices.
  # shellcheck disable=SC2086
  ( cd "$RD" && exec "$CLERK" $flag ) >/dev/null 2>&1 &
  pid=$!
  waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 30 ]; do
    sleep 0.1; waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    bad "clerk $flag refuses instead of spinning" "an exit" "still running after 3s"
  else
    wait "$pid"; ok "clerk $flag refuses instead of spinning"
  fi
done

# --------------------------------------------------------------------------------
printf '\nrun flags\n'

RF=$(new_repo)
J=$(run "$RF" prepare)
eq "every flag is off with nothing set" "false false false" \
   "$(printf '%s' "$J" | jq -r '[.flags.in_place, .flags.integrate, .flags.review_plan] | join(" ")')"
eq "and the source says so" "default" "$(printf '%s' "$J" | jq -r '.flag_sources.integrate')"

mkdir -p "$RF/tasks"
printf '{"integrate": true}\n' > "$RF/tasks/clerk.json"
J=$(run "$RF" prepare)
eq "a tracked config switches one on" "true" "$(printf '%s' "$J" | jq -r '.flags.integrate')"
eq "and is named as the source" "tasks/clerk.json" "$(printf '%s' "$J" | jq -r '.flag_sources.integrate')"

J=$(run "$RF" prepare --request 'add a widget --no-integrate')
eq "the request turns off what the config turned on" \
   "false" "$(printf '%s' "$J" | jq -r '.flags.integrate')"
eq "and takes the credit for it" "request" "$(printf '%s' "$J" | jq -r '.flag_sources.integrate')"

J=$(run "$RF" prepare --request 'add a widget --in-place --review-plan')
eq "several flags resolve from one request" "true true" \
   "$(printf '%s' "$J" | jq -r '[.flags.in_place, .flags.review_plan] | join(" ")')"
eq "a flag the request omits still falls through to the config" \
   "tasks/clerk.json" "$(printf '%s' "$J" | jq -r '.flag_sources.integrate')"

# Prose is the bulk of a request. A substring match here would read the sentence as an
# instruction, which is the one way this parse can turn integration on by accident.
J=$(run "$RF" prepare --request 'make the --no-integrate path integrate cleanly with sso')
eq "a flag word in prose is not a flag" "false" "$(printf '%s' "$J" | jq -r '.flags.integrate')"
eq "and neither is one embedded in a longer token" "false" \
   "$(run "$RF" prepare --request 'rename --in-place-editing' | jq -r '.flags.in_place')"

eq "a request saying both reads as off" "false" \
   "$(run "$RF" prepare --request 'x --integrate --no-integrate' | jq -r '.flags.integrate')"
eq "however it is ordered" "false" \
   "$(run "$RF" prepare --request 'x --no-integrate --integrate' | jq -r '.flags.integrate')"

# A description is arbitrary text: a glob in it must never reach the shell as a pattern.
eq "a glob in the description is inert" "true" \
   "$(run "$RF" prepare --request 'touch *.go and ./** --in-place' | jq -r '.flags.in_place')"
eq "and so is an empty request" "false" \
   "$(run "$RF" prepare --request '' | jq -r '.flags.in_place')"

eq "an unknown argument is refused rather than ignored" "2" \
   "$(run "$RF" prepare --nonsense >/dev/null 2>&1; printf '%s' $?)"

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
eq "and says it resolved the path itself" "resolved" \
   "$(run "$R2" prepare | jq -r '.learnings_path_source')"

# A caller fanning runs over one story gives each its own file; they share a git-common
# dir, so the resolved path would have them all appending to one.
J=$(run "$R2" prepare --request 'build it --learnings-path /tmp/run-3.md')
eq "the request names the learnings file" "/tmp/run-3.md" "$(printf '%s' "$J" | jq -r '.learnings_path')"
eq "and is named as the source" "request" "$(printf '%s' "$J" | jq -r '.learnings_path_source')"
eq "the = spelling works too" "/tmp/run-4.md" \
   "$(run "$R2" prepare --request 'build it --learnings-path=/tmp/run-4.md' | jq -r '.learnings_path')"
eq "a relative path resolves against the repo root, not the cwd" \
   "$R2/notes/run.md" \
   "$(run "$R2" prepare --request '--learnings-path notes/run.md' | jq -r '.learnings_path')"
eq "a dangling --learnings-path falls back rather than eating the next flag" \
   "resolved|true" \
   "$(J=$(run "$R2" prepare --request 'x --learnings-path --in-place'); \
      printf '%s|%s' "$(printf '%s' "$J" | jq -r '.learnings_path_source')" \
                     "$(printf '%s' "$J" | jq -r '.flags.in_place')")"

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
printf '\nworktree creation\n'

RW=$(new_repo)
W=$(run "$RW" worktree add-widget)
eq "lands under .worktrees, beside the git dir" "$RW/.worktrees/add-widget" \
   "$(printf '%s' "$W" | jq -r '.path')"
eq "on a branch named for the feature" "add-widget" "$(printf '%s' "$W" | jq -r '.branch')"
eq "and says it made it" "true" "$(printf '%s' "$W" | jq -r '.created')"
eq "the checkout is real" "true" \
   "$([ -f "$RW/.worktrees/add-widget/README.md" ] && echo true || echo false)"

# The line the prose existed to defend: .worktrees/ is inside the repo, so without it
# `clean` goes false and the next run stops to ask about a directory clerk made.
eq "the exclude entry is written" "true" "$(printf '%s' "$W" | jq -r '.excluded')"
eq "so the main checkout still reads clean" "true" "$(run "$RW" prepare | jq -r '.clean')"
eq "and it goes in info/exclude, leaving no tracked file dirty" "1" \
   "$(grep -cxF '.worktrees/' "$RW/.git/info/exclude")"

W2=$(run "$RW" worktree add-widget)
eq "a second call adopts rather than creating another" "true" \
   "$(printf '%s' "$W2" | jq -r '.adopted')"
eq "and points at the one that already exists" "$RW/.worktrees/add-widget" \
   "$(printf '%s' "$W2" | jq -r '.path')"
eq "the repo still has exactly one" "1" \
   "$(git -C "$RW" worktree list | grep -c 'add-widget')"
eq "and the exclude line is not written twice" "1" \
   "$(grep -cxF '.worktrees/' "$RW/.git/info/exclude")"

# A branch whose worktree was removed still carries the run's commits.
git -C "$RW" worktree remove "$RW/.worktrees/add-widget"
W3=$(run "$RW" worktree add-widget)
eq "an orphaned branch is checked out, not branched over" "false|true" \
   "$(printf '%s|%s' "$(printf '%s' "$W3" | jq -r '.created')" "$(printf '%s' "$W3" | jq -r '.adopted')")"

RW2=$(new_repo)
git -C "$RW2" checkout -q -b other && printf 'x\n' > "$RW2/x.md" \
  && git -C "$RW2" add -A && git -C "$RW2" commit -qm "Other" && git -C "$RW2" checkout -q main
eq "--base branches from the ref it is given" "true" \
   "$(run "$RW2" worktree from-other --base other >/dev/null; \
      git -C "$RW2/.worktrees/from-other" log --oneline -1 --format=%s | grep -qx Other && echo true || echo false)"

eq "a name git would refuse is refused here, with a name in the message" "2" \
   "$(run "$RW2" worktree 'bad name' >/dev/null 2>&1; printf '%s' $?)"
eq "and so is no name at all" "2" "$(run "$RW2" worktree >/dev/null 2>&1; printf '%s' $?)"
eq "a branch checked out in the main tree cannot be worktreed over" "2" \
   "$(run "$RW2" worktree main >/dev/null 2>&1; printf '%s' $?)"

# --------------------------------------------------------------------------------
printf '\ncommit skill\n'

RC=$(new_repo)
eq "falls back to the personal skill" "pcommit" "$(run "$RC" prepare | jq -r '.commit_skill')"

mkdir -p "$RC/.claude/skills/commit"
printf -- '---\nname: commit\n---\n' > "$RC/.claude/skills/commit/SKILL.md"
eq "the project's own skill wins when it defines one" "commit" \
   "$(run "$RC" prepare | jq -r '.commit_skill')"

# A skill is a tracked file on the branch, so it is the worktree's copy the harness
# resolves once a run has entered one.
git -C "$RC" add -A && git -C "$RC" commit -qm "Add commit skill"
CWT="$RC/../wt-c-$(basename "$RC")"
git -C "$RC" worktree add -q -b feat "$CWT" >/dev/null 2>&1
eq "and is found from inside the worktree" "commit" "$(run "$CWT" prepare | jq -r '.commit_skill')"
rm -rf "$CWT/.claude"
eq "a branch without it falls back, whatever the main checkout has" "pcommit" \
   "$(run "$CWT" prepare | jq -r '.commit_skill')"

# --------------------------------------------------------------------------------
printf '\nresume\n'

# The sidecar carries `done`; a breakdown that has started and not finished is the run
# to adopt rather than decompose over.
seed_breakdown() {
  local repo=$1 slug=$2 d1=$3 d2=$4
  mkdir -p "$repo/tasks"
  printf '### Task 1: One\n### Task 2: Two\n' > "$repo/tasks/$slug.md"
  jq -n --arg s "$slug" --argjson d1 "$d1" --argjson d2 "$d2" \
    '{story: $s, tasks_file: ("tasks/" + $s + ".md"), tasks: [
       {n: 1, title: "One", language: "Go", testable: true, depends_on: [], affected_files: ["a.go"], done: $d1},
       {n: 2, title: "Two", language: "Go", testable: true, depends_on: [1], affected_files: ["b.go"], done: $d2}]}' \
    > "$repo/tasks/$slug.json"
}

RR=$(new_repo)
eq "nothing to resume in a fresh repo" "null" "$(run "$RR" prepare | jq -r '.resume')"

seed_breakdown "$RR" widget false false
eq "an untouched breakdown is not a resume" "null" "$(run "$RR" prepare | jq -r '.resume')"

seed_breakdown "$RR" widget true false
J=$(run "$RR" prepare)
eq "a part-built breakdown is the one to adopt" "$RR/tasks/widget.md" \
   "$(printf '%s' "$J" | jq -r '.resume.breakdown.path')"
eq "with its progress carried through" "1/2" \
   "$(printf '%s' "$J" | jq -r '.resume.breakdown | "\(.done)/\(.total)"')"
eq "and no worktree until one exists" "null" "$(printf '%s' "$J" | jq -r '.resume.worktree')"

# The branch is the breakdown's own slug, because `git worktree add -b` and
# tasks/<story>.md are given the same feature name.
RWT="$RR/../wt-$(basename "$RR")"
git -C "$RR" worktree add -q -b widget "$RWT" >/dev/null 2>&1
J=$(run "$RR" prepare)
eq "the worktree on the breakdown's slug is its home" "$(cd "$RWT" && pwd -P)" \
   "$(printf '%s' "$J" | jq -r '.resume.worktree.path')"
eq "and is paired by branch, not by position" "widget" \
   "$(printf '%s' "$J" | jq -r '.resume.worktree.branch')"

seed_breakdown "$RR" widget true true
eq "a finished breakdown is not resumed" "null" "$(run "$RR" prepare | jq -r '.resume')"

# A repo planned as deliverables has several in flight at once; picking one needs to know
# which run this is, so prepare reports them all and decides nothing.
seed_breakdown "$RR" widget true false
seed_breakdown "$RR" gadget true false
J=$(run "$RR" prepare)
eq "two part-built breakdowns is not a pick" "null" "$(printf '%s' "$J" | jq -r '.resume')"
eq "but both are still listed with their progress" "2" \
   "$(printf '%s' "$J" | jq -r '[.breakdowns[] | select(.started and (.finished | not))] | length')"

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
# deleted_branch is reported from what git actually did, not assumed from having asked.
eq "names the branch it deleted"     "feature" "$(printf '%s' "$L" | jq -r '.deleted_branch')"
eq "with nothing left behind to say" "null"    "$(printf '%s' "$L" | jq -r '.branch_left')"

# Landing from inside a worktree stops before the merge, and says what has to happen to
# the worktree first — `git worktree prune` leaves one whose directory still exists, so a
# next_step that ends at prune sends the caller into a branch delete git will refuse.
R23=$(new_repo)
mkdir -p "$R23/tasks"
printf '# S\n\n## Task 1: A\n' > "$R23/tasks/s.md"
printf '{"story":"s","tasks":[{"n":1,"title":"A","depends_on":[],"done":true}]}\n' > "$R23/tasks/s.json"
git -C "$R23" add -A && git -C "$R23" commit -qm "Plan"
WT5="$R23/.wt/feat"
git -C "$R23" worktree add -q -b feat "$WT5" >/dev/null 2>&1
printf 'x\n' > "$WT5/x.txt"; git -C "$WT5" add -A && git -C "$WT5" commit -qm "Work"
run "$WT5" receipt --command "true" --passed >/dev/null
L=$(run "$WT5" land --integrate --audit-accepted)
eq "landing from inside a worktree does not land"  "false" "$(printf '%s' "$L" | jq -r '.landed')"
eq "it names the worktree standing in the way"     "$WT5"  "$(printf '%s' "$L" | jq -r '.worktree')"
eq "and removes it before deleting the branch"     "true" \
   "$(printf '%s' "$L" | jq -r '.command | test("worktree remove.*branch -d")')"

# Run what it printed, rather than only matching its text. The order is the whole point,
# and an instruction that reads plausibly and fails on contact is the thing to catch.
CMD=$(printf '%s' "$L" | jq -r '.command')
(cd "$R23" && eval "$CMD") >/dev/null 2>&1
eq "running that command lands the work"     "1" "$(git -C "$R23" log --oneline main | rg -c 'Work')"
eq "removes the worktree"                    "1" "$(git -C "$R23" worktree list | wc -l | tr -d ' ')"
eq "and deletes the branch it was holding"   "0" "$(git -C "$R23" branch --list feat | wc -l | tr -d ' ')"


# The usage text promises every command takes --tasks-file. land did not, and its gate —
# which resolves the breakdown itself — failed asking to be passed the flag land refused.
# A dead end reached with the work finished and every other predicate green.
R25=$(new_repo)
mkdir -p "$R25/tasks"
printf '# A\n\n## Task 1: A\n' > "$R25/tasks/alpha.md"
printf '{"story":"alpha","tasks":[{"n":1,"title":"A","depends_on":[],"done":true}]}\n' > "$R25/tasks/alpha.json"
printf '# B\n\n## Task 1: B\n' > "$R25/tasks/beta.md"
printf '{"story":"beta","tasks":[{"n":1,"title":"B","depends_on":[],"done":false}]}\n' > "$R25/tasks/beta.json"
git -C "$R25" add -A && git -C "$R25" commit -qm "Two breakdowns"
git -C "$R25" switch -qc feat
printf 'x\n' > "$R25/x.txt"; git -C "$R25" add -A && git -C "$R25" commit -qm "Work"
run "$R25" receipt --command "true" --passed >/dev/null

run "$R25" land --audit-accepted --tasks-file tasks/alpha.md >/dev/null 2>&1
eq "land accepts --tasks-file like every other command" "0" "$?"
L=$(run "$R25" land --audit-accepted --tasks-file tasks/alpha.md)
eq "its gate resolves the breakdown it was named" "true" \
   "$(printf '%s' "$L" | jq -r '[.gate.checks[]? | select(.name=="tasks-complete") | .ok] | first // true')"
eq "and it archives that one"      "yes" "$([ -f "$R25/tasks/completed/alpha.md" ] && echo yes || echo no)"
eq "leaving the other where it was" "yes" "$([ -f "$R25/tasks/beta.md" ] && echo yes || echo no)"

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
case "$(printf '%s' "$L" | jq -r '.command')" in
  *"merge --ff-only"*) ok "and prints the command to run in the main checkout" ;;
  *) bad "and prints the command to run in the main checkout" "a merge --ff-only hint" "$(printf '%s' "$L" | jq -r '.command')" ;;
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
printf '\nacceptance criteria, reported not gated\n'

R17=$(new_repo); mkdir -p "$R17/tasks"
cat > "$R17/tasks/c.md" <<'EOF'
## Contents
1. Task 1: One
2. Task 2: Two

### Task 1: One

**Acceptance Criteria:**
- [x] first
- [x] second
- [ ] third

**Depends on:** None

### Task 2: Two

**Acceptance Criteria:**
- [ ] alpha

**Depends on:** Task 1
EOF
printf 'package a\n' > "$R17/a.go"
git -C "$R17" add -A && git -C "$R17" commit -qm Plan
run "$R17" sidecar >/dev/null && git -C "$R17" add -A && git -C "$R17" commit -qm Sidecar

S=$(run "$R17" status)
eq "counts criteria across the breakdown" "4|2|2" \
   "$(printf '%s' "$S" | jq -r '.criteria.total')|$(printf '%s' "$S" | jq -r '.criteria.ticked')|$(printf '%s' "$S" | jq -r '.criteria.unticked')"
eq "a contents list above the sections is not counted" "3" \
   "$(printf '%s' "$S" | jq -r '.progress[0].criteria.total')"

printf 'edit\n' >> "$R17/a.go"
run "$R17" finish 1 -- a.go >/dev/null
S=$(run "$R17" status)
eq "flags a task marked done with a criterion unwalked" "1" \
   "$(printf '%s' "$S" | jq -r '.done_with_unticked_criteria | join(",")')"

# Information only: it must not shut the gate.
git -C "$R17" commit -qm "Task 1"
printf 'more\n' >> "$R17/a.go"
run "$R17" finish 2 -- a.go >/dev/null && git -C "$R17" commit -qm "Task 2"
run "$R17" receipt --command "go test ./..." --passed >/dev/null
eq "an unticked criterion does not shut the gate" "true" \
   "$(run "$R17" gate --audit-accepted | jq -r '.ok')"
eq "though status still says so"                  "2" \
   "$(run "$R17" status | jq -r '.criteria.unticked')"


# --------------------------------------------------------------------------------
printf '\nstatus --all\n'

R18=$(new_repo); mkdir -p "$R18/tasks/completed" "$R18/tasks/big-story/slice-one"
printf -- '### Task 1: One\n\n**Depends on:** None\n\n### Task 2: Two\n\n**Depends on:** Task 1\n' > "$R18/tasks/live.md"
printf -- '### Task 1: Old\n\n**Depends on:** None\n' > "$R18/tasks/completed/past.md"
git -C "$R18" add -A && git -C "$R18" commit -qm Plan
run "$R18" sidecar --tasks-file "$R18/tasks/live.md" >/dev/null
run "$R18" sidecar --tasks-file "$R18/tasks/completed/past.md" >/dev/null
# decompose-to-prs puts one breakdown per slice under tasks/<story>/<slice>/tasks.md.
printf -- '### Task 1: Sliced\n\n**Depends on:** None\n' > "$R18/tasks/big-story/slice-one/tasks.md"
run "$R18" sidecar --tasks-file "$R18/tasks/big-story/slice-one/tasks.md" >/dev/null

A=$(run "$R18" status --all)
eq "walks every breakdown, in flight and archived" "3" "$(printf '%s' "$A" | jq -r '.breakdowns | length')"
eq "marking which are archived"                    "1" \
   "$(printf '%s' "$A" | jq -r '[.breakdowns[] | select(.archived)] | length')"
eq "and carries each task through"                 "4" \
   "$(printf '%s' "$A" | jq -r '[.breakdowns[].progress[]] | length')"
eq "with the sidecar it read"                      "true" \
   "$(printf '%s' "$A" | jq -r '.breakdowns[0].sidecar | endswith(".json")')"

# Paths must be work-tree relative. A consumer walking tasks/ has relative paths, and an
# absolute one silently fails to join — which reads as "this breakdown has no progress"
# rather than as an error, so the reporter falls back to whatever stale checklist is left.
eq "reports paths relative to the work tree" "tasks/live.md" \
   "$(printf '%s' "$A" | jq -r '[.breakdowns[].tasks_file | select(endswith("/live.md"))] | first')"
eq "and a slice nested under a story"        "tasks/big-story/slice-one/tasks.md" \
   "$(printf '%s' "$A" | jq -r '[.breakdowns[] | select(.tasks_file | contains("slice"))] | first | .tasks_file')"
eq "including archived ones"                 "tasks/completed/past.md" \
   "$(printf '%s' "$A" | jq -r '[.breakdowns[] | select(.archived) | .tasks_file] | first')"

# The shape the progress reporter consumes.
eq "flattens to one row per task" "4" \
   "$(printf '%s' "$A" | jq -r '.breakdowns[] | .tasks_file as $f | .progress[] | [$f, (.n|tostring)] | @tsv' | wc -l | tr -d ' ')"

# --------------------------------------------------------------------------------
printf '\na repo that keeps tasks/ out of history\n'

# The regime that sent a run into the main checkout: a fresh worktree only ever
# materialises tracked files, so an excluded breakdown is not in it, and resolving the
# breakdown against the work tree left the worktree the one place the run could not see
# its own plan. Every command has to find it at the main root instead.
R19=$(new_repo)
printf 'tasks\n' > "$R19/.gitignore"
git -C "$R19" add -A && git -C "$R19" commit -qm "Exclude tasks"
mkdir -p "$R19/tasks"
cat > "$R19/tasks/story.md" <<'EOF'
# Story

## Task 1: Add the type
**Depends on:** None
EOF
cat > "$R19/tasks/story.json" <<'EOF'
{"story":"story","tasks":[
 {"n":1,"title":"Add the type","language":"Go","testable":true,"depends_on":[],"affected_files":["a.go"]},
 {"n":2,"title":"Use it","language":"Go","testable":true,"depends_on":[1],"affected_files":["b.go"]}]}
EOF
printf 'package a\n' > "$R19/a.go"; printf 'package b\n' > "$R19/b.go"
git -C "$R19" add -A && git -C "$R19" commit -qm "Add code"

J=$(run "$R19" prepare)
eq "prepare says the breakdown is not tracked" "false" "$(printf '%s' "$J" | jq -r '.tasks_tracked')"
eq "and homes it at the main repo root"        "$R19" "$(printf '%s' "$J" | jq -r '.tasks_home')"
eq "and still finds it"                        "$R19/tasks/story.md" "$(printf '%s' "$J" | jq -r '.tasks_file')"

WT2="$R19/.wt/feature"
git -C "$R19" worktree add -q -b feature "$WT2" >/dev/null 2>&1
eq "a worktree does not contain the excluded breakdown" "" "$(ls "$WT2/tasks" 2>/dev/null)"
J=$(run "$WT2" prepare)
eq "yet prepare inside it resolves the breakdown anyway" "$R19/tasks/story.md" \
   "$(printf '%s' "$J" | jq -r '.tasks_file')"
eq "reporting the work tree it is standing in"          "$WT2" "$(printf '%s' "$J" | jq -r '.work_tree')"
eq "next picks up where the plan says"                  "1"    "$(run "$WT2" next | jq -r '.task.n')"

printf 'package a2\n' > "$WT2/a.go"
C=$(run "$WT2" finish 1 -- a.go)
eq "finish reports the breakdown as untracked" "false" "$(printf '%s' "$C" | jq -r '.breakdown_tracked')"
eq "still marks the task done"                 "true"  "$(jq -r '.tasks[0].done' "$R19/tasks/story.json")"
eq "and stages only the code, never the sidecar" "a.go" \
   "$(git -C "$WT2" diff --cached --name-only | tr '\n' ',' | sed 's/,$//')"

git -C "$WT2" commit -qm "Task 1" >/dev/null
printf 'package b2\n' > "$WT2/b.go"
run "$WT2" finish 2 -- b.go >/dev/null 2>&1
eq "a second task in the worktree also succeeds" "0" "$?"
git -C "$WT2" commit -qm "Task 2" >/dev/null
eq "status reads progress from the excluded sidecar" "2|2" \
   "$(run "$WT2" status | jq -r '[.total, .done] | join("|")')"

run "$WT2" receipt --command "true" --passed >/dev/null
L=$(run "$WT2" land --audit-accepted)
eq "land archives the breakdown by moving it, not committing it" \
   "$R19/tasks/completed/story.md" "$(printf '%s' "$L" | jq -r '.archived')"
eq "the archived breakdown is where it was moved to" "yes" \
   "$([ -f "$R19/tasks/completed/story.md" ] && echo yes || echo no)"
eq "its sidecar moved with it"                       "yes" \
   "$([ -f "$R19/tasks/completed/story.json" ] && echo yes || echo no)"
eq "and no archive commit was made"                  "Task 2" \
   "$(git -C "$WT2" log -1 --format=%s)"

# The tracked regime must keep staging the sidecar with the code — the guard against a
# progress record landing in a different commit from the work it stands for.
R20=$(new_repo)
mkdir -p "$R20/tasks"
printf '# Story\n\n## Task 1: Add it\n**Depends on:** None\n' > "$R20/tasks/story.md"
printf '{"story":"story","tasks":[{"n":1,"title":"Add it","language":"Go","testable":true,"depends_on":[],"affected_files":["a.go"]}]}\n' > "$R20/tasks/story.json"
printf 'package a\n' > "$R20/a.go"
git -C "$R20" add -A && git -C "$R20" commit -qm "Add plan"
printf 'package a2\n' > "$R20/a.go"
C=$(run "$R20" finish 1 -- a.go)
eq "a tracked breakdown is still reported as tracked" "true" "$(printf '%s' "$C" | jq -r '.breakdown_tracked')"
eq "and its sidecar still lands with the code"        "a.go,tasks/story.json" \
   "$(git -C "$R20" diff --cached --name-only | sort | tr '\n' ',' | sed 's/,$//')"

# A local default branch left unpulled sits behind the remote, and every branch cut from
# the remote measures as that many commits ahead of it. Counted against the wrong ref, a
# worktree nobody has built anything in reports as work under way and can never be resumed.
R24=$(new_repo)
ORIGIN=$(cd "$(mktemp -d)" && pwd -P)
git init -q --bare "$ORIGIN"
git -C "$R24" remote add origin "$ORIGIN"
mkdir -p "$R24/tasks/s/one"
printf '# D\n' > "$R24/tasks/s/one/tasks.md"
printf '{"story":"one","tasks":[{"n":1,"title":"A","depends_on":[],"done":false}]}\n' > "$R24/tasks/s/one/tasks.json"
cat > "$R24/tasks/s/plan.yaml" <<'EOF'
story: "S"
story_slug: s
deliverables:
  - id: one
    branch: s-one
    base: main
    wave: 1
    depends_on: []
    tasks: tasks/s/one/tasks.md
    status: pending
EOF
git -C "$R24" add -A && git -C "$R24" commit -qm "Plan"
printf 'moved on\n' > "$R24/moved.txt"
git -C "$R24" add -A && git -C "$R24" commit -qm "Work others pushed"
git -C "$R24" push -q origin main
git -C "$R24" reset -q --hard HEAD~1          # local main now trails origin/main
git -C "$R24" worktree add -q -b s-one "$R24/.wt/one" origin/main >/dev/null 2>&1
eq "fixture: the branch is ahead of the stale local default" "1" \
   "$(git -C "$R24" rev-list --count main..s-one)"
eq "but a worktree cut from the remote default is scaffolded, not in-progress" "scaffolded" \
   "$(run "$R24" story | jq -r '.[0].deliverables[0].state')"
eq "and carries no phantom commits of its own" "0" \
   "$(run "$R24" story | jq -r '.[0].deliverables[0].ahead')"
git -C "$R24" worktree remove --force "$R24/.wt/one" 2>/dev/null
rm -rf "$ORIGIN"

# --------------------------------------------------------------------------------
printf '\nnested breakdowns and the paths that reach them\n'

# decompose-to-deliverables writes tasks/<story>/<deliverable>/tasks.md. A flat glob over
# tasks/*.md sees none of them, which reads as "no breakdown" and sends a run off to
# decompose a story that was already decomposed.
R21=$(new_repo)
printf 'tasks\n' > "$R21/.gitignore"
git -C "$R21" add -A && git -C "$R21" commit -qm "Exclude tasks"
mkdir -p "$R21/tasks/the-story/first-deliverable"
printf '# D\n\n## Task 1: A\n**Depends on:** None\n' > "$R21/tasks/the-story/first-deliverable/tasks.md"
printf '{"story":"first","tasks":[{"n":1,"title":"A","language":"Go","testable":true,"depends_on":[],"affected_files":["a.go"]}]}\n' > "$R21/tasks/the-story/first-deliverable/tasks.json"
printf 'package a\n' > "$R21/a.go"
git -C "$R21" add -A && git -C "$R21" commit -qm "Add code"

eq "a breakdown nested under a story is found without being named" \
   "$R21/tasks/the-story/first-deliverable/tasks.md" "$(run "$R21" prepare | jq -r '.tasks_file')"
eq "and next resolves from it"     "1" "$(run "$R21" next | jq -r '.task.n')"
eq "prepare lists it as a breakdown" "1" "$(run "$R21" prepare | jq -r '.breakdowns | length')"

# Archiving must not make the repo look ambiguous. Archived breakdowns are still .md
# files under tasks/, so a recursive walk that counted them would refuse to resolve
# anything the moment a run had ever landed.
mkdir -p "$R21/tasks/completed"
printf '# Old\n' > "$R21/tasks/completed/older-story.md"
printf '{"story":"older","tasks":[{"n":1,"title":"X","depends_on":[],"done":true}]}\n' > "$R21/tasks/completed/older-story.json"
eq "an archived breakdown does not make the live one ambiguous" \
   "$R21/tasks/the-story/first-deliverable/tasks.md" "$(run "$R21" prepare | jq -r '.tasks_file')"
eq "though status --all still walks it" "2" \
   "$(run "$R21" status --all | jq -r '.breakdowns | length')"

# The path a person writes is relative to how the repo reads on disk. Inside a worktree
# that is not where an excluded breakdown lives, so the natural path missed and the error
# said the file did not exist — true of the path, false of the file.
WT3="$R21/.wt/feature"
git -C "$R21" worktree add -q -b feature "$WT3" >/dev/null 2>&1
eq "a relative --tasks-file resolves from inside a worktree" "1" \
   "$(run "$WT3" next --tasks-file tasks/the-story/first-deliverable/tasks.md | jq -r '.task.n')"
eq "an absolute one keeps working" "1" \
   "$(run "$WT3" next --tasks-file "$R21/tasks/the-story/first-deliverable/tasks.md" | jq -r '.task.n')"
eq "and no --tasks-file at all works too" "1" "$(run "$WT3" next | jq -r '.task.n')"

# --------------------------------------------------------------------------------
printf '\nstory — deliverable state derived, never read from the plan\n'

R22=$(new_repo)
mk_deliverable() {  # repo id total done
  local r=$1 id=$2 total=$3 done=$4 i body=
  mkdir -p "$r/tasks/story-a/$id"
  printf '# %s\n' "$id" > "$r/tasks/story-a/$id/tasks.md"
  i=1
  while [ "$i" -le "$total" ]; do
    body="$body{\"n\":$i,\"title\":\"t$i\",\"depends_on\":[],\"done\":$([ "$i" -le "$done" ] && echo true || echo false)},"
    i=$((i + 1))
  done
  printf '{"story":"%s","tasks":[%s]}\n' "$id" "${body%,}" > "$r/tasks/story-a/$id/tasks.json"
}
# plan_row <id> <wave> <deps> <status> [base]  — base defaults to the default branch
plan_row() { printf '  - id: %s\n    branch: br-%s\n    base: %s\n    wave: %s\n    depends_on: [%s]\n    tasks: tasks/story-a/%s/tasks.md\n    status: %s\n' "$1" "$1" "${5:-main}" "$2" "$3" "$1" "$4"; }

mkdir -p "$R22/tasks/story-a"
{ printf 'story: "A story"\nstory_slug: story-a\ndeliverables:\n'
  plan_row rebased   1 ''        merged
  plan_row gone      1 ''        pending
  plan_row building  1 ''        pending
  plan_row waiting   2 'rebased,building' pending
  plan_row unblocked 2 'rebased,gone'     pending
  plan_row finished  1 ''        pending
  plan_row stacked   2 'building'  pending   building
} > "$R22/tasks/story-a/plan.yaml"
mk_deliverable "$R22" rebased   3 3
mk_deliverable "$R22" gone      2 2
mk_deliverable "$R22" building  3 1
mk_deliverable "$R22" waiting   2 0
mk_deliverable "$R22" unblocked 2 0
mk_deliverable "$R22" finished  2 2
mk_deliverable "$R22" stacked   2 0
git -C "$R22" add -A && git -C "$R22" commit -qm "Plan the story"

# rebased: its patch is in main under a different sha — the shape --is-ancestor gets wrong
git -C "$R22" checkout -q -b br-rebased
printf 'one\n' > "$R22/r.txt"; git -C "$R22" add -A; git -C "$R22" commit -qm "Rebased work"
git -C "$R22" checkout -q main
# The same diff under a different commit message: a different SHA carrying an identical
# patch, which is what a rebase- or squash-merge leaves behind. Cherry-picking would not
# do it — same tree, parent, author and second produces a byte-identical commit object.
printf 'one\n' > "$R22/r.txt"; git -C "$R22" add -A; git -C "$R22" commit -qm "Rebased work, as it landed"
eq "fixture: the merged branch really does have a distinct sha" "1" \
   "$(git -C "$R22" rev-list --count main..br-rebased)"
# building: real commits, not in main
git -C "$R22" checkout -q -b br-building
printf 'two\n' > "$R22/b.txt"; git -C "$R22" add -A; git -C "$R22" commit -qm "Half done"
# finished: every task done but nothing merged
git -C "$R22" checkout -q main && git -C "$R22" checkout -q -b br-finished
printf 'three\n' > "$R22/f.txt"; git -C "$R22" add -A; git -C "$R22" commit -qm "All done"
git -C "$R22" checkout -q main
# gone: branch br-gone never created, sidecar says 2/2

S=$(run "$R22" story)
st() { printf '%s' "$S" | jq -r --arg i "$1" '.[0].deliverables[] | select(.id == $i) | .state'; }
eq "a rebase-merged branch reads as merged, not as unmerged work" "merged"         "$(st rebased)"
eq "a branch deleted after merging is settled by its sidecar"     "merged"         "$(st gone)"
eq "part-done work in flight is in-progress"                      "in-progress"    "$(st building)"
eq "all tasks done but nothing landed is awaiting-merge"          "awaiting-merge" "$(st finished)"
eq "a deliverable whose dependency is still building is blocked"  "blocked"        "$(st waiting)"
eq "and one whose dependencies all landed is ready"               "ready"          "$(st unblocked)"
eq "blocked names only the dependency that is not landed" "building" \
   "$(printf '%s' "$S" | jq -r '.[0].deliverables[] | select(.id=="waiting") | .blocked_by | join(",")')"
eq "merged says how it was established" "every commit on the branch is patch-present in the default branch" \
   "$(printf '%s' "$S" | jq -r '.[0].deliverables[] | select(.id=="rebased") | .evidence')"
eq "the plan's own status field is never read" "0" \
   "$(printf '%s' "$S" | jq -r '[.[0].deliverables[] | select(has("status"))] | length')"

# A deliverable with no depends_on used to lose its base: tab is IFS whitespace, so a
# run of them collapsed and every later field shifted left by one.
eq "a deliverable with no dependencies still carries its base" "main" \
   "$(printf '%s' "$S" | jq -r '.[0].deliverables[] | select(.id=="rebased") | .base')"
eq "and the base resolves to a commit a worktree can branch from" "$(git -C "$R22" rev-parse main)" \
   "$(printf '%s' "$S" | jq -r '.[0].deliverables[] | select(.id=="rebased") | .base_commit')"
eq "a stacked base resolves to its sibling's branch tip" "$(git -C "$R22" rev-parse br-building)" \
   "$(run "$R22" story tasks/story-a/plan.yaml | jq -r '.[0].deliverables[] | select(.id=="stacked") | .base_commit')"

# The drift that makes a driver scaffold a second worktree for work already under way.
git -C "$R22" branch waiting-something-else main
eq "a branch that is not the planned name is called out" "waiting-something-else" \
   "$(run "$R22" story | jq -r '.[0].deliverables[] | select(.id=="waiting") | .branch_alias')"

# A worktree exists but nothing is committed in it yet. Branch and sidecar both say
# untouched; only the worktree says a run already has this deliverable.
WT4="$R22/.wt/unblocked"
eq "before it is scaffolded, it reads as ready" "ready" "$(st unblocked)"
git -C "$R22" worktree add -q -b br-unblocked "$WT4" >/dev/null 2>&1
S=$(run "$R22" story)   # st() reads this snapshot; the worktree is new since the last one
eq "a worktree with nothing in it reads as scaffolded, not in-progress" "scaffolded" "$(st unblocked)"
eq "and names the worktree that claimed it" "$WT4" \
   "$(run "$R22" story | jq -r '.[0].deliverables[] | select(.id=="unblocked") | .worktree')"

mkdir -p "$R22/tasks/completed/older-story"
printf 'story: "Older"\nstory_slug: older\ndeliverables: []\n' > "$R22/tasks/completed/older-story/plan.yaml"
eq "with no plan named, archived plans are left out" "1" "$(run "$R22" story | jq -r 'length')"
eq "and naming one directly still works" "story-a" \
   "$(run "$R22" story tasks/story-a/plan.yaml | jq -r '.[0].story_slug')"

# A tracker id the caller gave decompose-to-deliverables survives as a field, not only as
# a slug prefix -- a prefix cannot be told apart from a title that happens to start with one.
eq "a plan with no ticket reports none" "null" "$(run "$R22" story | jq -r '.[0].ticket')"
printf 'ticket: "AGE-713"\n' >> "$R22/tasks/story-a/plan.yaml"
eq "and one that records a ticket carries it through" "AGE-713" \
   "$(run "$R22" story | jq -r '.[0].ticket')"
eq "--table renders a row per deliverable" "7" \
   "$(run "$R22" story --table | rg -c '^  (merged|ready|blocked|scaffolded|in-progress|awaiting-merge)')"

# --------------------------------------------------------------------------------
printf '\nstack — PR bases derived from the plan DAG\n'

# The fixture has no origin, so no `gh` call is made and every openable deliverable
# reads as "create". What is under test is the ordering and the base each PR targets,
# which is decided before any network call.
SK=$(run "$R22" stack --json)
sk() { printf '%s' "$SK" | jq -r --arg i "$1" --arg f "$2" '.[0].deliverables[] | select(.id == $i) | .[$f]'; }

eq "a deliverable based on the default branch targets it"  "main"        "$(sk building base)"
eq "a stacked deliverable targets its prerequisite branch" "br-building" "$(sk stacked base)"
eq "a merged deliverable is skipped"                       "skip"        "$(sk rebased action)"
eq "with the reason given"                          "already merged"     "$(sk rebased skip)"
eq "a deliverable whose branch was deleted after merging is skipped too" "already merged" \
   "$(sk gone skip)"
eq "a deliverable with no branch is skipped"        "no branch yet"      "$(sk stacked skip)"
eq "a branch carrying no commits is skipped" "branch carries no commits" "$(sk unblocked skip)"
# The head is the branch on disk, not the one the plan wished for: a PR opened against
# the planned name would 404, and the work sitting on the real branch never gets reviewed.
eq "a branch that drifted from its planned name is still the PR head" "waiting-something-else" \
   "$(sk waiting branch)"
eq "a finished but unlanded deliverable is opened"         "create"      "$(sk finished action)"

eq "the stack is emitted bottom-first, so a base exists before the PR that targets it" \
   "true" "$(printf '%s' "$SK" | jq -r '[.[0].deliverables[] | .id] | index("building") < index("stacked")')"

eq "creating without an origin refuses rather than opening half a stack" "2" \
   "$(run "$R22" stack --create >/dev/null 2>&1; echo $?)"

# The retarget that makes a stack survive its own merges. Two real branches: `high` sits
# on `low`, and once `low` lands, a PR still pointing at br-low diffs against code that
# is already in main. Its own fixture because R22's deliverables are shaped for state
# derivation — the one branch stacked there is deliberately never created.
R27=$(new_repo); mkdir -p "$R27/tasks/stack-s/low" "$R27/tasks/stack-s/high"
for d in low high; do
  printf '# %s\n' "$d" > "$R27/tasks/stack-s/$d/tasks.md"
  printf '{"story":"%s","tasks":[{"n":1,"title":"t","depends_on":[],"done":true}]}\n' "$d" \
    > "$R27/tasks/stack-s/$d/tasks.json"
done
{ printf 'story: Stacked\nstory_slug: stack-s\ndeliverables:\n'
  printf '  - id: low\n    branch: br-low\n    base: main\n    wave: 1\n    depends_on: []\n    tasks: tasks/stack-s/low/tasks.md\n'
  printf '  - id: high\n    branch: br-high\n    base: low\n    wave: 2\n    depends_on: [low]\n    tasks: tasks/stack-s/high/tasks.md\n'
} > "$R27/tasks/stack-s/plan.yaml"
git -C "$R27" add -A && git -C "$R27" commit -qm "Plan a stack"
git -C "$R27" checkout -q -b br-low
printf 'low\n' > "$R27/low.txt"; git -C "$R27" add -A; git -C "$R27" commit -qm "Low"
git -C "$R27" checkout -q -b br-high
printf 'high\n' > "$R27/high.txt"; git -C "$R27" add -A; git -C "$R27" commit -qm "High"
git -C "$R27" checkout -q main

eq "a stacked PR targets its prerequisite while that is unlanded" "br-low" \
   "$(run "$R27" stack --json | jq -r '.[0].deliverables[] | select(.id == "high") | .base')"
eq "and is opened rather than skipped" "create" \
   "$(run "$R27" stack --json | jq -r '.[0].deliverables[] | select(.id == "high") | .action')"

git -C "$R27" merge -q --no-ff -m "Land low" br-low
eq "once the prerequisite lands the stack retargets to the mainline" "main" \
   "$(run "$R27" stack --json | jq -r '.[0].deliverables[] | select(.id == "high") | .base')"
eq "and says why it moved" "low has merged" \
   "$(run "$R27" stack --json | jq -r '.[0].deliverables[] | select(.id == "high") | .base_note')"
eq "the landed prerequisite drops out of the stack" "already merged" \
   "$(run "$R27" stack --json | jq -r '.[0].deliverables[] | select(.id == "low") | .skip')"

R26=$(new_repo); mkdir -p "$R26/tasks/one" "$R26/tasks/two"
printf 'story: One\nstory_slug: one\ndeliverables:\n  - id: a\n    branch: br-a\n    base: main\n    wave: 1\n    depends_on: []\n    tasks: tasks/one/a.md\n' > "$R26/tasks/one/plan.yaml"
printf 'story: Two\nstory_slug: two\ndeliverables:\n  - id: b\n    branch: br-b\n    base: main\n    wave: 1\n    depends_on: []\n    tasks: tasks/two/b.md\n' > "$R26/tasks/two/plan.yaml"
git -C "$R26" remote add origin git@github.com:example/repo.git
eq "two plans is fine to look at" "2" "$(run "$R26" stack --json | jq 'length')"
eq "and refused for --create, which would open another story's PRs" "2" \
   "$(run "$R26" stack --create >/dev/null 2>&1; echo $?)"

# --------------------------------------------------------------------------------
printf '\nguidelines — required reading, loaded not looked up\n'

# A fixture set, not the real one: these assertions are about how a file is cut up, and
# pinning them to the live guidelines would make every edit to those files a test
# failure. The drifted spellings are copied from the real ones on purpose — they are
# what the slot list exists to absorb.
GD=$(cd "$(mktemp -d)" && pwd -P)
mkdir -p "$GD/testing" "$GD/go" "$GD/javascript"
cat > "$GD/testing/caller-patterns.md" <<'EOF'
<!-- index: 1-4 -->
# Caller Patterns

## Section Index
| Section | Use when... |

## How to Identify the Caller
identify-body

## 1. UI (User -> Page)
ui-body

## 5. Exported API (Other Code -> This Interface)
exported-body

## Quick Reference
quickref-body
EOF
printf '# Comment Usage\ncomments-body\n' > "$GD/comments.md"
cat > "$GD/go/testing-patterns.md" <<'EOF'
<!-- index: 1-3 -->
# Go Testing

## Section Index
| Section |

## What to Test
what-body

## What is a Unit of Behavior?
unit-body

## Assertion Strictness: Match to What You're Testing
assert-body

## Independent Verification
indep-body

## Unrelated Section
noise-body
EOF
printf '# Go Naming\nnaming-body\n' > "$GD/go/naming-patterns.md"
printf '# Go Architecture\narch-body\n' > "$GD/go/architecture-principles.md"
printf '# Go Workflow\nworkflow-body\n' > "$GD/go/development-workflow.md"
# JavaScript has no assertion-strictness section at all; it calls it something else.
cat > "$GD/javascript/testing-patterns.md" <<'EOF'
# JS Testing

## What to Test
js-what-body

## Unit of Behavior
js-unit-body

## Assertion Patterns
js-assert-body

## Independent Verification
js-indep-body
EOF
printf '# JS Naming\njs-naming-body\n' > "$GD/javascript/naming-patterns.md"
printf '# JS DOM\ndom-body\n' > "$GD/javascript/dom-patterns.md"
# Elixir's fixture is deliberately incomplete both ways: a file with a slot no heading
# satisfies, and a file the set does not have at all.
mkdir -p "$GD/elixir"
cat > "$GD/elixir/testing-patterns.md" <<'EOF'
# Elixir Testing

## What to Test
ex-what-body

## Unit of Behavior
ex-unit-body
EOF

gl() { "$CLERK" guidelines --guidelines-dir "$GD" "$@"; }

G=$(gl --language Go)
eq "the long file is cut to its slots, not read whole" "0" \
   "$(printf '%s' "$G" | grep -c 'noise-body')"
eq "and the slots it was cut to are all there" "4" \
   "$(printf '%s' "$G" | grep -cE 'what-body|unit-body|assert-body|indep-body')"

# The spellings the skill asked for by name are not the spellings the files use. A
# prompt matching these by eye fails silently; this is why they are a list.
eq "Go's renamed unit-of-behavior section still resolves" "1" \
   "$(printf '%s' "$G" | grep -c '§ What is a Unit of Behavior?')"
eq "and its qualified assertion heading too" "1" \
   "$(printf '%s' "$G" | grep -c "§ Assertion Strictness: Match")"
eq "JavaScript's differently-named one resolves as well" "1" \
   "$(gl --language JavaScript/TypeScript | grep -c '§ Assertion Patterns')"

eq "short files come whole" "1" "$(printf '%s' "$G" | grep -c 'naming-body')"
eq "and every one of them" "3" \
   "$(printf '%s' "$G" | grep -cE 'arch-body|workflow-body|comments-body')"

eq "the section index of a long file rides along" "1" \
   "$(printf '%s' "$G" | grep -c 'index: 1-3')"

# Which caller pattern fits the work is the caller's judgment, so it is asked for.
eq "no caller pattern is emitted unasked" "0" "$(printf '%s' "$G" | grep -c 'ui-body')"
eq "the identification section always is" "1" "$(printf '%s' "$G" | grep -c 'identify-body')"
eq "and the quick reference with it" "1" "$(printf '%s' "$G" | grep -c 'quickref-body')"
eq "--caller adds that pattern and only it" "1|0" \
   "$(C=$(gl --language Go --caller ui); printf '%s|%s' "$(printf '%s' "$C" | grep -c 'ui-body')" \
      "$(printf '%s' "$C" | grep -c 'exported-body')")"
eq "a numbered pattern is found by name, not by number" "1" \
   "$(gl --language Go --caller exported | grep -c 'exported-body')"

# Agents cite sections by name that no fixed slot list could anticipate.
S=$(gl --language Go --section 'go/testing-patterns.md:Unrelated Section')
eq "a section asked for by name is added to the bundle" "1" \
   "$(printf '%s' "$S" | grep -c 'noise-body')"
eq "without displacing the slots the bundle already had" "4" \
   "$(printf '%s' "$S" | grep -cE 'what-body|unit-body|assert-body|indep-body')"

# Headings contain colons; filenames do not — so the spec splits on the first only.
# Naming one the bundle already covers must also not print it twice.
eq "a heading with a colon in it still resolves, once" "1" \
   "$(gl --language Go --section "go/testing-patterns.md:Assertion Strictness: Match to What You're Testing" \
      | grep -c 'assert-body')"

# A file reached only this way is cut to what was asked, whatever its length.
printf '# Shared\n\n## Coupling-Based Assertion Levels\ncoupling-body\n\n## Other\nother-body\n' \
  > "$GD/testing/patterns.md"
P=$(gl --language Go --section 'testing/patterns.md:Coupling-Based Assertion Levels')
eq "a file outside every bundle gives only the section named" "1|0" \
   "$(printf '%s|%s' "$(printf '%s' "$P" | grep -c 'coupling-body')" \
      "$(printf '%s' "$P" | grep -c 'other-body')")"

eq "a named section that no heading matches is reported" "1" \
   "$(gl --language Go --section 'go/testing-patterns.md:Renamed Away' | grep -c 'no section matching .Renamed Away.')"
eq "and a spec with no heading is refused outright" "2" \
   "$(gl --language Go --section 'go/testing-patterns.md' >/dev/null 2>&1; printf '%s' $?)"

# A `## ` inside a fenced block is example content, not a section boundary. The regex
# cannot tell, so it truncates the real section there and invents one for the fence;
# ast-grep parses the markdown and does not. Two real guidelines contain exactly this.
GF=$(cd "$(mktemp -d)" && pwd -P)
mkdir -p "$GF/go" "$GF/testing"
{ printf '# Go Testing\n\n## What to Test\nwhat-body-before\n\n'
  printf '```\n## Fenced Not A Section\nfenced-body\n```\n\n'
  printf 'what-body-after\n\n## Unit of Behavior\nunit-body\n'
} > "$GF/go/testing-patterns.md"
printf '# Comments\ncomments-body\n' > "$GF/comments.md"
printf '# Caller\n\n## How to Identify the Caller\nid\n\n## Quick Reference\nqr\n' > "$GF/testing/caller-patterns.md"
for f in naming-patterns architecture-principles development-workflow; do
  printf '# %s\nbody\n' "$f" > "$GF/go/$f.md"
done
FENCE=$("$CLERK" guidelines --guidelines-dir "$GF" --language Go)
eq "a fenced heading does not become a section" "0" \
   "$(printf '%s' "$FENCE" | grep -c 'Fenced Not A Section -->')"
eq "and the real section is not truncated at it" "1" \
   "$(printf '%s' "$FENCE" | grep -c 'what-body-after')"
eq "the fenced example still travels inside its section" "1" \
   "$(printf '%s' "$FENCE" | grep -c 'fenced-body')"

# Without ast-grep the regex is what is left. Worse, but it must still work.
NOAG=$(PATH=/usr/bin:/bin "$(dirname "$CLERK")/clerk-guidelines" \
        --guidelines-dir "$GF" --language Go 2>&1)
eq "it falls back rather than failing when ast-grep is absent" "1" \
   "$(printf '%s' "$NOAG" | grep -c 'what-body-before')"
# The fence still splits the section there, which is the defect ast-grep removes: the
# half of "What to Test" below the example never arrives.
eq "and without it the section is cut short at the fence" "0" \
   "$(printf '%s' "$NOAG" | grep -c 'what-body-after')"

# A file whose name ends the same way but which no bundle contains. Cutting it to the
# slot list emits nothing and complains four times about headings it never claimed.
mkdir -p "$GD/cue"
printf '# CUE Testing\n\n## Critical Rule: Verify Tests Can Fail\ncue-test-body\n' \
  > "$GD/cue/testing-patterns.md"
C=$(gl --only --file cue/testing-patterns.md)
eq "a testing guideline outside every bundle comes whole" "1" \
   "$(printf '%s' "$C" | grep -c 'cue-test-body')"
eq "and is not reported as missing the bundle's sections" "0" \
   "$(printf '%s' "$C" | grep -c 'no section matching')"
eq "while a bundle's own testing guideline stays cut to its slots" "4" \
   "$(gl --only --file go/testing-patterns.md | grep -c '^<!-- go/testing-patterns.md §')"

# Files outside every language bundle — concurrency, performance, cue, architecture.
printf '# Go Concurrency\nconcurrency-body\n' > "$GD/go/concurrency-patterns.md"
F=$(gl --language Go --file go/concurrency-patterns.md)
eq "--file adds a guideline no bundle contains" "1" "$(printf '%s' "$F" | grep -c 'concurrency-body')"
eq "alongside everything the bundle already gave" "1" "$(printf '%s' "$F" | grep -c 'naming-body')"

# A reviewer wants its own guideline, not everything its language has.
O=$(gl --only --file go/concurrency-patterns.md)
eq "--only emits what was named" "1" "$(printf '%s' "$O" | grep -c 'concurrency-body')"
eq "and nothing that was not" "0" \
   "$(printf '%s' "$O" | grep -cE 'naming-body|comments-body|identify-body|what-body')"
eq "--only skips detection rather than falling back to it" "0" \
   "$(cd "$GD" && gl --only --file comments.md | grep -c 'naming-body')"
eq "--only with nothing named is refused" "2" \
   "$(gl --only >/dev/null 2>&1; printf '%s' $?)"
eq "--only still honours a caller pattern" "1|0" \
   "$(C=$(gl --only --caller ui); printf '%s|%s' "$(printf '%s' "$C" | grep -c 'ui-body')" \
      "$(printf '%s' "$C" | grep -c 'comments-body')")"
eq "and --only composes with --section" "1|0" \
   "$(C=$(gl --only --section 'go/testing-patterns.md:What to Test'); \
      printf '%s|%s' "$(printf '%s' "$C" | grep -c 'what-body')" \
      "$(printf '%s' "$C" | grep -c 'unit-body')")"

eq "the DOM guideline is opt-in" "0" "$(gl --language JavaScript/TypeScript | grep -c 'dom-body')"
eq "and arrives when asked for" "1" \
   "$(gl --language JavaScript/TypeScript --dom | grep -c 'dom-body')"

# A section silently absent reads exactly like a section the guideline never had.
E=$(gl --language Elixir)
eq "a slot that matches nothing is reported, not dropped" "1" \
   "$(printf '%s' "$E" | grep -c 'no section matching .assertions.')"
eq "and the headings it did find are named, so the slot can be fixed" "true" \
   "$(printf '%s' "$E" | grep -q 'Its headings are: What to Test, Unit of Behavior' && echo true || echo false)"
eq "each unmatched slot is reported on its own" "2" \
   "$(printf '%s' "$E" | grep -c 'no section matching')"
eq "the sections that did resolve still come through" "2" \
   "$(printf '%s' "$E" | grep -cE 'ex-what-body|ex-unit-body')"
eq "a language with no guideline set says so" "1" \
   "$(gl --language Rust | grep -c 'Rust.*no guideline set')"
eq "a file the set does not have says so too" "1" \
   "$(printf '%s' "$E" | grep -c 'elixir/naming-patterns.md.*does not exist')"
eq "nothing missing means no such section" "0" \
   "$(printf '%s' "$G" | grep -c '## Not loaded')"

eq "--list names the plan without emitting bodies" "whole|0" \
   "$(L=$(gl --language Go --list); printf '%s|%s' \
      "$(printf '%s' "$L" | jq -r '.files[] | select(.file == "comments.md") | .sections')" \
      "$(printf '%s' "$L" | grep -c 'comments-body')")"
eq "a missing guidelines directory is refused" "2" \
   "$("$CLERK" guidelines --guidelines-dir "$GD/nope" --language Go >/dev/null 2>&1; printf '%s' $?)"

# --------------------------------------------------------------------------------
printf '\nfixup — folding a fix into the commit that caused it\n'

# Three task commits on a branch, the shape Phase 3 finds: one file per task, plus a
# catalog every task edits — the case where the newest commit is the wrong answer.
RX=$(new_repo)
git -C "$RX" checkout -q -b feature
for t in 1 2 3; do
  printf 'task %s\n' "$t" > "$RX/task$t.go"
  printf 'entry %s\n' "$t" >> "$RX/catalog.txt"
  git -C "$RX" add -A && git -C "$RX" commit -qm "Add task $t"
done
BASE=$(git -C "$RX" rev-parse main)

printf 'task 2 fixed\n' > "$RX/task2.go"
F=$(run "$RX" fixup --base "$BASE" --dry-run -- task2.go)
eq "one commit in range means nothing to weigh" "Add task 2" "$(printf '%s' "$F" | jq -r '.subject')"
eq "and --dry-run leaves the tree alone" "1" \
   "$(git -C "$RX" status --porcelain | grep -c 'task2.go')"

F=$(run "$RX" fixup --base "$BASE" -- task2.go)
eq "the fix is marked for that commit" "true" "$(printf '%s' "$F" | jq -r '.ok')"
eq "as a fixup, not a fresh commit" "1" \
   "$(git -C "$RX" log --format=%s -1 | grep -c '^fixup! Add task 2')"

# The whole reason this refuses rather than taking the newest.
printf 'entry 4\n' >> "$RX/catalog.txt"
X=$(run "$RX" fixup --base "$BASE" -- catalog.txt)
eq "a file several tasks touched is refused, not guessed at" "ambiguous" \
   "$(printf '%s' "$X" | jq -r '.reason')"
eq "and every candidate is named, newest first" "Add task 3|Add task 1" \
   "$(printf '%s' "$X" | jq -r '[.candidates["catalog.txt"][0].subject, .candidates["catalog.txt"][-1].subject] | join("|")')"
eq "refusing exits 3, not 0" "3" \
   "$(run "$RX" fixup --base "$BASE" -- catalog.txt >/dev/null 2>&1; printf '%s' $?)"
eq "nothing was staged by the refusal" "0" \
   "$(git -C "$RX" diff --cached --name-only | grep -c 'catalog.txt')"

# The judgment escape hatch: the caller read the evidence and names the commit.
T1=$(git -C "$RX" log --format=%H --grep='Add task 1' -1)
eq "--onto takes the caller's answer" "Add task 1" \
   "$(run "$RX" fixup --base "$BASE" --onto "$T1" -- catalog.txt | jq -r '.subject')"

# Replaying that one would conflict: it appends to a file every later task also appends
# to. Aborting and keeping the separate commit is the documented answer, and the branch
# has to come back untouched.
BEFORE=$(git -C "$RX" rev-parse HEAD)
eq "a conflicted replay exits 3" "3" \
   "$(run "$RX" fixup --base "$BASE" --replay >/dev/null 2>&1; printf '%s' $?)"
eq "and leaves the branch exactly as it was" "$BEFORE" "$(git -C "$RX" rev-parse HEAD)"
eq "with no rebase left half-done" "false" \
   "$([ -d "$RX/.git/rebase-merge" ] || [ -d "$RX/.git/rebase-apply" ] && echo true || echo false)"
git -C "$RX" reset -q --hard HEAD~1

# Files whose targets differ decompose into one fixup each, which is worth saying.
git -C "$RX" reset -q --hard HEAD
printf 'task 1 edit\n' > "$RX/task1.go"; printf 'task 3 edit\n' > "$RX/task3.go"
S=$(run "$RX" fixup --base "$BASE" -- task1.go task3.go)
eq "a fix spanning two task commits says so" "spans-commits" "$(printf '%s' "$S" | jq -r '.reason')"
eq "and groups the files by the commit each belongs to" "2" \
   "$(printf '%s' "$S" | jq -r '.groups | length')"

git -C "$RX" reset -q --hard HEAD
printf 'brand new\n' > "$RX/newfile.go"
eq "a file no commit in range touches is new work, not a correction" "3" \
   "$(run "$RX" fixup --base "$BASE" -- newfile.go >/dev/null 2>&1; printf '%s' $?)"
rm "$RX/newfile.go"

# The replay.
R=$(run "$RX" fixup --base "$BASE" --replay)
eq "the marked fixup is folded" "1" "$(printf '%s' "$R" | jq -r '.folded')"
eq "leaving one commit per task" "3" \
   "$(git -C "$RX" rev-list --count "$BASE"..HEAD)"
eq "and no fixup! subject behind" "0" \
   "$(git -C "$RX" log --format=%s "$BASE"..HEAD | grep -c '^fixup!')"
eq "the fix is in the task commit it belonged to" "task 2 fixed" \
   "$(git -C "$RX" show "$(git -C "$RX" log --format=%H --grep='Add task 2' -1)":task2.go)"

eq "replaying with nothing marked is a no-op, not an error" "0" \
   "$(run "$RX" fixup --base "$BASE" --replay | jq -r '.folded')"

printf 'loose\n' > "$RX/task1.go"
eq "a dirty tree is refused before any rebase starts" "3" \
   "$(run "$RX" fixup --base "$BASE" --replay >/dev/null 2>&1; printf '%s' $?)"
eq "and the refusal names the way through" "1" \
   "$(run "$RX" fixup --base "$BASE" --replay 2>&1 | grep -c -- '--autostash')"

# A repo with unrelated work always in flight would otherwise never be able to replay.
printf 'task 2 more\n' > "$RX/task2.go"
run "$RX" fixup --base "$BASE" -- task2.go >/dev/null
A=$(run "$RX" fixup --base "$BASE" --replay --autostash)
eq "--autostash replays around the loose work" "1|true" \
   "$(printf '%s|%s' "$(printf '%s' "$A" | jq -r '.folded')" "$(printf '%s' "$A" | jq -r '.autostashed')")"
eq "and the loose work is still there afterwards" "loose" "$(cat "$RX/task1.go")"
eq "with no fixup! left in history" "0" \
   "$(git -C "$RX" log --format=%s "$BASE"..HEAD | grep -c '^fixup!')"
git -C "$RX" checkout -q -- task1.go

# Rewriting what someone else may already have is the one case to keep separate.
RM=$(cd "$(mktemp -d)" && pwd -P)
git -C "$RM" init -q --bare
git -C "$RX" remote add origin "$RM"
git -C "$RX" push -q -u origin feature
printf 'task 3 fixed\n' > "$RX/task3.go"
run "$RX" fixup --base "$BASE" -- task3.go >/dev/null 2>&1
P=$(run "$RX" fixup --base "$BASE" --replay 2>&1)
eq "a published range refuses the replay" "3" \
   "$(run "$RX" fixup --base "$BASE" --replay >/dev/null 2>&1; printf '%s' $?)"
eq "and says how much of it is already out there" "1" \
   "$(printf '%s' "$P" | grep -c 'already on origin/feature')"
eq "--force is the caller asserting the branch is theirs alone" "1" \
   "$(run "$RX" fixup --base "$BASE" --replay --force | jq -r '.folded')"

# --------------------------------------------------------------------------------
printf '\nlearn — what the next run reads\n'

RL=$(new_repo)
L=$(run "$RL" learn --type convention --title "Handlers own their decoding" \
      --learning "Every inbound handler decodes its own payload." \
      --apply-when "Adding a handler that takes a request body." --task 3 --feature "sso")
eq "written to the path clerk resolves" "$RL/tasks/learnings.md" "$(printf '%s' "$L" | jq -r '.path')"
eq "and counted" "1" "$(printf '%s' "$L" | jq -r '.entries')"
eq "the block carries every field" "4" \
   "$(grep -cE '^- (Type|Observed|Learning|Apply when):' "$RL/tasks/learnings.md")"
eq "the heading is the title" "## Handlers own their decoding" \
   "$(grep -m1 '^## ' "$RL/tasks/learnings.md")"
eq "task and feature land in one Observed line" "- Observed: task 3 — sso" \
   "$(grep -m1 '^- Observed:' "$RL/tasks/learnings.md")"
eq "a file created here gets a heading, not a bare block" "1" \
   "$(head -1 "$RL/tasks/learnings.md" | grep -c '^# ')"

run "$RL" learn --type pattern --title "Second thing" --learning "superseded wording" --apply-when "y" >/dev/null
eq "a second entry appends rather than replacing" "2" \
   "$(grep -c '^## ' "$RL/tasks/learnings.md")"

# The path hangs off the repo root, and Phase 3 runs from a worktree that is not it.
LWT="$RL/../wt-l-$(basename "$RL")"
git -C "$RL" add -A && git -C "$RL" commit -qm "Learnings"
git -C "$RL" worktree add -q -b learner "$LWT" >/dev/null 2>&1
eq "resolved from the repo root even when called from a worktree" "$RL/tasks/learnings.md" \
   "$(run "$LWT" learn --type constraint --title "From the worktree" --learning "x" \
        --apply-when "y" | jq -r '.path')"
eq "so the entry lands in the file the next run reads" "3" \
   "$(grep -c '^## ' "$RL/tasks/learnings.md")"

# Fanned-out runs share a git-common-dir, so each is given its own file.
eq "--path overrides for a run that was given one" "$RL/other.md" \
   "$(run "$RL" learn --path "$RL/other.md" --type pattern --title "Elsewhere" \
        --learning "x" --apply-when "y" | jq -r '.path')"
eq "and the default file is untouched by it" "3" "$(grep -c '^## ' "$RL/tasks/learnings.md")"

# Substance is the caller's to judge; an exact title collision is not.
eq "a repeated title is refused rather than doubled" "3" \
   "$(run "$RL" learn --type pattern --title "Second thing" --learning "z" \
        --apply-when "w" >/dev/null 2>&1; printf '%s' $?)"
eq "--list is how substance gets judged before writing" "3" \
   "$(run "$RL" learn --list | jq -r '.titles | length')"
R=$(run "$RL" learn --replace --type pattern --title "Second thing" \
      --learning "folded wording" --apply-when "y")
eq "--replace rewrites in place" "true|3" \
   "$(printf '%s|%s' "$(printf '%s' "$R" | jq -r '.replaced')" "$(grep -c '^## ' "$RL/tasks/learnings.md")")"
eq "and the new wording is what is there" "1" \
   "$(grep -c 'folded wording' "$RL/tasks/learnings.md")"
eq "with the old wording gone" "0" "$(grep -c 'superseded wording' "$RL/tasks/learnings.md")"

eq "an entry missing a field is refused, since it is the one nobody can act on" "2" \
   "$(run "$RL" learn --type pattern --title "Partial" --learning "x" >/dev/null 2>&1; printf '%s' $?)"
eq "and so is a type outside the four" "2" \
   "$(run "$RL" learn --type invention --title "P" --learning "x" --apply-when "y" >/dev/null 2>&1; printf '%s' $?)"

eq "a tracked file says committing is what shares it" "true" \
   "$(run "$RL" learn --type pattern --title "Tracked check" --learning "x" \
        --apply-when "y" | jq -r '.in_tree')"

RL2=$(new_repo)
printf 'tasks/\n' > "$RL2/.gitignore" && git -C "$RL2" add -A && git -C "$RL2" commit -qm "Ignore"
eq "an out-of-tree file says nothing here dirties the tree" "false" \
   "$(run "$RL2" learn --type pattern --title "Outside" --learning "x" \
        --apply-when "y" | jq -r '.in_tree')"

# --------------------------------------------------------------------------------
printf '\nlint — the conventions a regex settles\n'

R28=$(new_repo)
# A comment that was already there before the rule existed. Linting whole files would
# report it forever, which is how a check gets switched off.
printf 'package p\n\n// Task 9 predates this rule\nfunc Old() {}\n' > "$R28/old.go"
git -C "$R28" add -A && git -C "$R28" commit -qm "Baseline"

cat > "$R28/new.go" <<'EOF'
package p

// Task 3 wires the reactor
func A() {}

// PR 5 wiring
func B() {}

// see APP-1234
func C() {}

// the new helper for parsing
func D() {}

// decode as UTF-8 before comparing, since the store round-trips through latin-1
func E() {}

// Reordered before the walk: a translation-nested event is written above its sibling.
func F() {}
EOF
printf 'package p\n\nvar u = "https://example.com//x"\n' > "$R28/url.go"
printf '\nfunc Touched() {}\n' >> "$R28/old.go"
git -C "$R28" add -A
L=$(run "$R28" lint --staged --rule comment-plan-position --json)
lc() { printf '%s' "$L" | jq -r --arg f "$1" '[.[] | select(.file == $f)] | length'; }
eq "a comment naming a task by number is reported"      "4" "$(lc new.go)"
eq "and says which phrase tripped it" "names a task by its number: \"Task 3\"" \
   "$(printf '%s' "$L" | jq -r '.[0].message')"
eq "a standard that looks like a ticket id is not a ticket" "0" \
   "$(printf '%s' "$L" | jq -r '[.[] | select(.message | test("UTF"))] | length')"
eq "// inside a string literal is not a comment"        "0" "$(lc url.go)"
eq "a comment written before the rule is left alone"    "0" "$(lc old.go)"
eq "findings exit non-zero so this can gate"            "1" \
   "$(run "$R28" lint --staged --rule comment-plan-position >/dev/null 2>&1; echo $?)"

R29=$(new_repo)
mkdir -p "$R29/pkg"
cat > "$R29/pkg/reactor_test.go" <<'EOF'
package pkg

func TestReactorOpensNewCase(t *testing.T) {}
func TestReactorAttachesToExistingCase(t *testing.T) {}
func TestReactorReturnsNoCase(t *testing.T) {}
EOF
# Three types, not three scenarios. The rule is one umbrella per type, so this is right.
cat > "$R29/pkg/user_test.go" <<'EOF'
package pkg

func TestUser(t *testing.T) {}
func TestUserService(t *testing.T) {}
func TestUserRepo(t *testing.T) {}
EOF
cat > "$R29/pkg/two_test.go" <<'EOF'
package pkg

func TestQueueAcceptsItem(t *testing.T) {}
func TestQueueRejectsItem(t *testing.T) {}
EOF
git -C "$R29" add -A && git -C "$R29" commit -qm "Tests"
T=$(run "$R29" lint --rule test-umbrella --json pkg/reactor_test.go pkg/user_test.go pkg/two_test.go)
eq "sibling scenario tests are reported once for the group" "1" "$(printf '%s' "$T" | jq 'length')"
eq "and it is the scenario-named file"      "pkg/reactor_test.go" "$(printf '%s' "$T" | jq -r '.[0].file')"
eq "tests named after distinct types are left alone" "0" \
   "$(printf '%s' "$T" | jq -r '[.[] | select(.file == "pkg/user_test.go")] | length')"
eq "two siblings are not yet a pattern" "0" \
   "$(printf '%s' "$T" | jq -r '[.[] | select(.file == "pkg/two_test.go")] | length')"

R30=$(new_repo)
mkdir -p "$R30/svc"
printf 'package svc\n\ntype Sender struct{}\n\nfunc (s *Sender) Send() {}\n' > "$R30/svc/sender.go"
printf 'package svc\n\nfunc (s *Sender) Retry() {}\n' > "$R30/svc/retry.go"
printf '// Code generated by mockgen. DO NOT EDIT.\n\npackage svc\n\nfunc (s *Sender) Mocked() {}\n' > "$R30/svc/mock.go"
printf '//go:build linux\n\npackage svc\n\nfunc (s *Sender) OnLinux() {}\n' > "$R30/svc/linux.go"
git -C "$R30" add -A && git -C "$R30" commit -qm "Service"
M=$(run "$R30" lint --rule type-methods-split --json svc/sender.go)
eq "a method living apart from its type is reported"  "1" "$(printf '%s' "$M" | jq 'length')"
eq "against the file holding the stray method" "svc/retry.go" "$(printf '%s' "$M" | jq -r '.[0].file')"
eq "and names where the type is declared" "true" \
   "$(printf '%s' "$M" | jq -r '.[0].message | test("declared in sender.go")')"
eq "generated code is exempt, as it cannot live in the declaring file" "0" \
   "$(printf '%s' "$M" | jq -r '[.[] | select(.file | test("mock"))] | length')"
eq "and so is a build-tagged variant" "0" \
   "$(printf '%s' "$M" | jq -r '[.[] | select(.file | test("linux"))] | length')"
eq "a package is walked once however many of its files changed" "1" \
   "$(run "$R30" lint --rule type-methods-split --json svc/sender.go svc/retry.go | jq 'length')"
eq "the same file passed twice is not reported twice" "1" \
   "$(run "$R30" lint --rule type-methods-split --json svc/sender.go ./svc/sender.go | jq 'length')"
# A package can hold a layout older than this rule. Editing something unrelated in it must
# not reprint that layout, or the check becomes noise and gets switched off.
printf 'package svc\n\nfunc Unrelated() {}\n' > "$R30/svc/other.go"
eq "a split in an untouched pair of files is left alone" "0" \
   "$(run "$R30" lint --rule type-methods-split --json svc/other.go | jq 'length')"

eq "an unknown rule is refused rather than silently skipped" "2" \
   "$(run "$R30" lint --rule nonsense >/dev/null 2>&1; echo $?)"

# --------------------------------------------------------------------------------
git -C "$R22" worktree remove --force "$WT4" 2>/dev/null
git -C "$R21" worktree remove --force "$WT3" 2>/dev/null
git -C "$R19" worktree remove --force "$WT2" 2>/dev/null
rm -rf "$R" "$R2" "$R3" "$R4" "$R5" "$R6" "$R7" "$R8" "$R9" "$R10" "$R11" "$R12" "$R13" "$R14" "$R15" "$R16" "$R17" "$R18" "$R19" "$R20" "$R21" "$R22" "$R23" "$R24" "$R25" "$R26" "$R27" "$R28" "$R29" "$R30" "$WT" 2>/dev/null
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
