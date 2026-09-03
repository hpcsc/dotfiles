#!/usr/bin/env bash
# Fixture-repo tests for `clerk run` — the step table walked by a program instead of by a
# model. No framework: each case builds a throwaway git repo and asserts on the JSON.
# Run with: tests/clerk-run-test.sh
#
# The property under test is that the runner decides nothing the step table decides. It
# does the mechanical steps, spawns one turn for each of the rest, refuses what wants a
# person, and stops when a row will not close. The harness is a stub that reads the step
# out of the prompt it is handed and does that step, so a whole story is walked for free.
set -uo pipefail
BIN="$(cd "$(dirname "$0")/.." && pwd)/link/common/dot-local/bin"
CLERK="$BIN/clerk"
export PATH="$BIN:$PATH"
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
  printf 'seed\n' > "$d/README.md"
  mkdir -p "$d/tasks"
  # `true` as the suite: the runner runs it for real, so it has to be a command that is
  # green without a toolchain the fixture does not have.
  printf '{"default": "true"}\n' > "$d/tasks/test-commands.json"
  git -C "$d" add -A && git -C "$d" commit -qm "Seed"
  printf '%s' "$d"
}

# A two-task breakdown, committed, so a worktree branched from HEAD carries it.
seed() {  # repo slug
  local repo=$1 slug=$2
  printf '# %s\n\n## Tasks\n\n### Task 1: One\n- [ ] a\n\n### Task 2: Two\n- [ ] b\n' "$slug" \
    > "$repo/tasks/$slug.md"
  jq -n --arg s "$slug" '{story: $s, tasks_file: ("tasks/" + $s + ".md"), tasks: [
      {n: 1, title: "One", language: "Go", depends_on: [], affected_files: ["a.go"],
       certainty: "high", blast_radius: "low", patterns_to_follow: ["README.md:1"], done: false},
      {n: 2, title: "Two", language: "Go", depends_on: [1], affected_files: ["b.go"],
       certainty: "high", blast_radius: "low", patterns_to_follow: ["README.md:1"], done: false}]}' \
    > "$repo/tasks/$slug.json"
  git -C "$repo" add -A && git -C "$repo" commit -qm "Plan"
}

run() { (cd "$1" && shift && "$CLERK" "$@"); }
rc() { run "$@" >/dev/null 2>&1; printf '%s' $?; }

# --------------------------------------------------------------------------------
printf '\nusage and refusals\n'

R=$(new_repo)
eq "--help prints the usage and exits 0" "0" "$(rc "$R" run --help)"
eq "an unknown flag is a usage error" "2" "$(rc "$R" run --nope)"
eq "with no run open and no story, it says what to name" "3" "$(rc "$R" run)"
eq "and says so rather than starting something" "true" \
   "$(run "$R" run 2>&1 >/dev/null | grep -c -- '--slug' | awk '{print ($1>0)}' | sed 's/1/true/;s/0/false/')"
eq "with no harness on PATH a real run refuses rather than hanging" "3" \
   "$(cd "$R" && CLERK_HARNESS_CMD= PATH=/usr/bin:/bin "$CLERK" run --slug w --request x >/dev/null 2>&1; printf '%s' $?)"

# --------------------------------------------------------------------------------
printf '\ngates — a pause with nobody to wait for is refused, not approximated\n'

RG=$(new_repo); seed "$RG" gated
G=$(run "$RG" run --slug gated --request "build it --gears" --dry-run)
eq "gears on refuses to start, naming the flag and where it came from" "false|gears|request" \
   "$(printf '%s' "$G" | jq -r '[(.ran|tostring), .flag, .source] | join("|")')"
eq "and says which flag waives it" "true" \
   "$(printf '%s' "$G" | jq -r '.reason | contains("--no-gears")')"
RP=$(new_repo); seed "$RP" gated
eq "review_breakdown is refused the same way" "review_breakdown" \
   "$(run "$RP" run --slug gated --request "build it --review-breakdown" --dry-run | jq -r '.flag')"
eq "waived, the run proceeds" "ground" \
   "$(run "$RG" run --no-gears --dry-run | jq -r '.step')"

# The waiver is a fact about the run, so it is recorded rather than only acted on.
run "$RG" run --no-gears --dry-run >/dev/null
eq "a run whose request set the flag keeps it set for every later call" "3" \
   "$(rc "$RG" run --dry-run)"

# --------------------------------------------------------------------------------
printf '\ndry run — the step it would take, and nothing spawned\n'

RD=$(new_repo); seed "$RD" story
D=$(run "$RD" run --slug story --request "a story" --dry-run)
eq "it reports the first open step" "true|ground" \
   "$(printf '%s' "$D" | jq -r '[(.dry_run|tostring), .step] | join("|")')"
eq "and that a turn would do it, with a prompt of some size" "true" \
   "$(printf '%s' "$D" | jq -r '(.prompt_chars > 500) | tostring')"
eq "the run is still open at the same step afterwards" "ground" \
   "$(run "$RD" run --dry-run | jq -r '.step')"

# --------------------------------------------------------------------------------
printf '\ntool scoping — Bash is named down to what the step runs\n'

eq "a read-only step gets no Edit" "false" \
   "$(printf '%s' "$D" | jq -r '.allowed_tools | contains(["Edit"]) | tostring')"
eq "and no git verb that leaves this machine" "0" \
   "$(printf '%s' "$D" | jq -r '[.allowed_tools[] | select(startswith("Bash(git push") or startswith("Bash(git remote"))] | length')"
eq "clerk is always reachable — every step closes with one of its commands" "true" \
   "$(printf '%s' "$D" | jq -r '.allowed_tools | contains(["Bash(clerk:*)"]) | tostring')"
eq "--allow-tool adds to the list rather than replacing it" "true|true" \
   "$(run "$RD" run --dry-run --allow-tool 'Bash(docker:*)' | jq -r '[(.allowed_tools | contains(["Bash(docker:*)"])), (.allowed_tools | contains(["Read"]))] | map(tostring) | join("|")')"

# --------------------------------------------------------------------------------
printf '\nmechanical steps — clerk does them, no turn is paid for\n'

# The stub answers every step by doing it, so a whole story walks for nothing. It writes
# its argv to a log so the build phase's session handling can be asserted afterwards.
FAKE=$(cd "$(mktemp -d)" && pwd -P)
export STUB_LOG="$FAKE/argv.log"
export AUDIT_LOG="$FAKE/audit-argv.log"
cat > "$FAKE/claude" <<'STUB'
#!/usr/bin/env bash
p=$(cat)
# Two callers reach this stub: the runner, spawning one turn per step, and `clerk audit
# run`, spawning the round's lens and refuter agents. Only the runner's turns are what
# the assertions below count, and a prompt fragment is how an audit agent is recognised,
# so the two are logged apart rather than into one file that means neither.
case "$p" in
  *FRAGMENT*) printf '%s\n' "$*" >> "$AUDIT_LOG" ;;
  *)          printf '%s\n' "$*" >> "$STUB_LOG" ;;
esac
sid=""
prev=""
for a in "$@"; do
  case "$prev" in --session-id|--resume) sid=$a ;; esac
  prev=$a
done
[ -n "$sid" ] || sid=fresh-$RANDOM
emit() { printf '{"is_error":false,"total_cost_usd":0.01,"session_id":"%s","result":%s}\n' \
                "$sid" "$(jq -Rs . <<< "$1")"; }

case "$p" in
  *"FRAGMENT scope-open"*)
    emit '{"base":"a","head":"b","summary":"s","files":["a.go","b.go"],"languages":["Go"],"by_language":[{"language":"Go","files":["a.go","b.go"]}],"signals":{"tests_changed":false,"concurrency":false,"performance":false},"has_code":true}'
    exit 0 ;;
  *"FRAGMENT report-open"*)
    emit '{"findings":[],"coverage_gaps":[],"summary":"nothing to report"}'; exit 0 ;;
  *FRAGMENT*) emit '{"verdict":"pass","findings":[],"note":null}'; exit 0 ;;
esac

step=$(printf '%s' "$p" | grep -m1 -o '"step": "[a-z-]*"' | sed 's/.*"step": "//;s/"//')
n=$(printf '%s' "$p" | grep -m1 -o '"n": [0-9]*' | sed 's/.*: //')
case "$step" in
  ground)   clerk step --done ground --caller exported >/dev/null ;;
  decompose) clerk step --done decompose --tasks-file "tasks/story.md" >/dev/null ;;
  build)    case "$n" in 1) f=a.go ;; *) f=b.go ;; esac
            printf 'package main\n' > "$f"
            clerk finish "$n" -- "$f" >/dev/null && git commit -qm "Task $n" ;;
  match-request) clerk step --done match-request >/dev/null ;;
  explain)  printf '\n## Theory\nIt is a fixture.\n' >> tasks/story.md
            git add tasks/story.md && git commit -qm "Theory" ;;
  verify-run) clerk step --done verify-residue >/dev/null ;;
  learn)    clerk step --done learn --none >/dev/null ;;
esac
emit "did the $step step"
STUB
chmod +x "$FAKE/claude"

PR=$(cd "$(mktemp -d)" && pwd -P); mkdir -p "$PR/audit-implement/prompts"
for f in scope-open scope-rules review-open review-rules finding-contract lens-semantic \
         lens-guidelines lens-tests lens-concurrency lens-performance dedupe-open \
         dedupe-rules dedupe-output refute-open refute-file-rule refute-runtime \
         refute-quality report-open report-rules report-tail regrade mechanical \
         mechanical-tail; do printf 'FRAGMENT %s\n' "$f" > "$PR/audit-implement/prompts/$f.md"; done
cp "$(cd "$(dirname "$0")/.." && pwd)/link/common/dot-config/.config/ai/method/audit-implement/schemas.json" \
   "$PR/audit-implement/schemas.json"
export CLERK_AUDIT_PROMPTS="$PR/audit-implement/prompts"

RW=$(new_repo); seed "$RW" story
: > "$STUB_LOG"
OUT=$(cd "$RW" && PATH="$FAKE:$PATH" "$CLERK" run --slug story --request "a story" --rounds 1 --quiet 2>/dev/null)
eq "a whole story walks to the end" "true|true" \
   "$(printf '%s' "$OUT" | jq -r '[(.ran|tostring), (.finished|tostring)] | join("|")')"
eq "the isolate step cost no turn — clerk made the worktree and entered it" "clerk" \
   "$(printf '%s' "$OUT" | jq -r '.steps[] | select(.step=="isolate") | .by' | head -1)"
eq "so did the suite, the audit and the landing" "clerk|clerk|clerk" \
   "$(printf '%s' "$OUT" | jq -r '[(.steps[] | select(.step=="suite" or .step=="audit" or .step=="land") | .by)] | unique | join("|")' | sed 's/^clerk$/clerk|clerk|clerk/')"
eq "every task was built by a turn" "2" \
   "$(printf '%s' "$OUT" | jq -r '[.steps[] | select(.step=="build")] | length')"
eq "and the run cost what its turns cost" "true" \
   "$(printf '%s' "$OUT" | jq -r '(.cost_usd > 0) | tostring')"
eq "the branch landed with the breakdown archived" "1" \
   "$(git -C "$RW" log --all --oneline | grep -c 'Archive completed task')"

# --------------------------------------------------------------------------------
printf '\nthe build phase — one session, one process per task\n'

eq "the first task opens a session and the second resumes it" "1|1" \
   "$(awk '/--session-id/ {s++} /--resume/ {r++} END {print s "|" r}' "$STUB_LOG")"
eq "and both turns name the same conversation" "1" \
   "$(grep -oE -- '--(session-id|resume) [0-9a-f-]+' "$STUB_LOG" | awk '{print $2}' | sort -u | wc -l | tr -d ' ')"
eq "no step outside the build phase was given a session" "true" \
   "$(awk '/--session-id|--resume/ {n++} END {print (n == 2 ? "true" : "false")}' "$STUB_LOG")"
# One --allowedTools per turn the runner made. The audit's lens agents are scoped too,
# by `clerk audit run` rather than by the runner, and they are counted separately —
# folded into one log they outnumber the turns and this says nothing about either.
eq "every turn the runner spawned was scoped" "true" \
   "$(test "$(grep -c -- '--allowedTools' "$STUB_LOG")" = "$(printf '%s' "$OUT" | jq -r '.turns')" && echo true || echo false)"
eq "and so was every agent the audit spawned" "true" \
   "$(test "$(grep -c -- '--allowedTools' "$AUDIT_LOG")" = "$(wc -l < "$AUDIT_LOG" | tr -d ' ')" && echo true || echo false)"

# --------------------------------------------------------------------------------
printf '\nrefusals mid-walk\n'

# A row the table marks `stop` wants a person; unattended there is nobody to be one.
RS=$(new_repo); seed "$RS" story
printf 'loose\n' > "$RS/loose.txt"
S=$(cd "$RS" && PATH="$FAKE:$PATH" "$CLERK" run --slug story --request "a story" --quiet 2>/dev/null)
eq "a dirty tree stops the run at ground rather than building on it" "false|ground" \
   "$(printf '%s' "$S" | jq -r '[(.ran|tostring), .step] | join("|")')"
eq "and the reason is the table's own" "true" \
   "$(printf '%s' "$S" | jq -r '.reason | contains("dirty")')"

# A turn that does nothing must not spin.
IDLE=$(cd "$(mktemp -d)" && pwd -P)
printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf %s\n "{\\"is_error\\":false,\\"total_cost_usd\\":0.01,\\"result\\":\\"nothing\\"}"\n' \
  > "$IDLE/claude"
chmod +x "$IDLE/claude"
RI=$(new_repo); seed "$RI" story
I=$(cd "$RI" && PATH="$IDLE:$PATH" "$CLERK" run --slug story --request "a story" --quiet 2>/dev/null)
eq "a step that will not close stops the run instead of paying for it forever" "false|ground" \
   "$(printf '%s' "$I" | jq -r '[(.ran|tostring), .step] | join("|")')"
eq "and says nothing changed between the attempts" "true" \
   "$(printf '%s' "$I" | jq -r '.reason | contains("attempts")')"
eq "three attempts, not more" "3" "$(printf '%s' "$I" | jq -r '.turns')"

# --------------------------------------------------------------------------------
printf '\noutput — the same walk at three volumes\n'

# A stub that answers in whichever format it was asked for, so all three levels are
# exercised against one story rather than three.
SEE=$(cd "$(mktemp -d)" && pwd -P)
cat > "$SEE/claude" <<'STUB'
#!/usr/bin/env bash
p=$(cat)
case "$p" in *'"step": "ground"'*) clerk step --done ground --caller exported >/dev/null ;; esac
case "$*" in
  *stream-json*)
    cat <<'EV'
{"type":"system","subtype":"init","session_id":"s1","model":"m"}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"README.md"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"clerk guidelines --caller exported"}}]}}
EV
    printf '{"type":"result","subtype":"success","is_error":false,"result":"named the caller pattern","total_cost_usd":0.02,"session_id":"s1"}\n' ;;
  *) printf '{"is_error":false,"total_cost_usd":0.02,"session_id":"s1","result":"named the caller pattern"}\n' ;;
esac
STUB
chmod +x "$SEE/claude"

show() {  # repo extra-flag  -> prints stderr
  (cd "$1" && shift && PATH="$SEE:$PATH" "$CLERK" run --max-steps 1 "$@" 2>&1 >/dev/null)
}

RV=$(new_repo); seed "$RV" story
run "$RV" run --slug story --request "a story" --dry-run >/dev/null
E=$(show "$RV")
eq "by default every tool call the turn made is a line" "2" \
   "$(printf '%s\n' "$E" | grep -c '⋯')"
eq "and each says which call it was" "true" \
   "$(printf '%s\n' "$E" | grep -q 'Read.*README.md' && printf '%s\n' "$E" | grep -q 'Bash.*clerk guidelines' && echo true || echo false)"
eq "the step and what it cost bracket them" "true" \
   "$(printf '%s\n' "$E" | grep -q '^ground ·' && printf '%s\n' "$E" | grep -q '✓.*\$0.02' && echo true || echo false)"

RQ=$(new_repo); seed "$RQ" story
run "$RQ" run --slug story --request "a story" --dry-run >/dev/null
Q=$(show "$RQ" --quiet)
eq "--quiet keeps the step and the result and drops the rest" "0|true" \
   "$(printf '%s\n' "$Q" | grep -c '⋯' | tr -d ' ')|$(printf '%s\n' "$Q" | grep -q '✓' && echo true || echo false)"
eq "and the model's own words with them" "0" \
   "$(printf '%s\n' "$Q" | grep -c 'named the caller pattern')"

RR=$(new_repo); seed "$RR" story
run "$RR" run --slug story --request "a story" --dry-run >/dev/null
RAW=$(cd "$RR" && PATH="$SEE:$PATH" "$CLERK" run --max-steps 1 --raw 2>/dev/null)
eq "--raw passes the harness's own events through" "true" \
   "$(printf '%s\n' "$RAW" | jq -sr '[.[] | select(.type == "tool_use" or .type == "assistant")] | length > 0')"
eq "every line is one JSON value, so it pipes" "true" \
   "$(printf '%s\n' "$RAW" | jq -e . >/dev/null 2>&1 && echo true || echo false)"
eq "and the run's summary is the last of them" "summary" \
   "$(printf '%s\n' "$RAW" | tail -1 | jq -r '.kind')"
eq "a step clerk did itself is in the stream too, not a gap" "true" \
   "$(printf '%s\n' "$RAW" | jq -sr '[.[] | select(.kind == "step")] | length > 0')"
eq "--quiet and --raw together are refused" "2" \
   "$(rc "$RR" run --quiet --raw)"

# --------------------------------------------------------------------------------
printf '\nthe opencode path — written to the documented contract, not to a binary\n'

# No `opencode` is installed here, so what is checked is the invocation this would make
# and the scoping it would write. A run under it stays unverified until one happens.
OC=$(cd "$(mktemp -d)" && pwd -P)
cat > "$OC/opencode" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
printf 'OPENCODE_CONFIG=%s\n' "${OPENCODE_CONFIG:-none}" >> "$STUB_LOG"
p=$(cat)
case "$p" in *'"step": "ground"'*) clerk step --done ground --caller exported >/dev/null ;; esac
printf '{"sessionID":"ses_abc","text":"named the caller pattern"}\n'
STUB
chmod +x "$OC/opencode"

ROC=$(new_repo); seed "$ROC" story
run "$ROC" run --slug story --request "a story" --dry-run >/dev/null
P=$(run "$ROC" run --dry-run --harness-cmd opencode | jq -c '.permission')
eq "the allowlist is written as a permission block, since there is no flag for it" "deny" \
   "$(printf '%s' "$P" | jq -r '.bash["*"]')"
eq "a read-only step is denied edit" "deny" "$(printf '%s' "$P" | jq -r '.edit')"
eq "and clerk is allowed both bare and with arguments" "allow|allow" \
   "$(printf '%s' "$P" | jq -r '[.bash["clerk"], .bash["clerk *"]] | join("|")')"
eq "nothing grants the network" "deny" "$(printf '%s' "$P" | jq -r '.webfetch')"
eq "the step text it would be handed is opencode's, not Claude's" "true" \
   "$(run "$ROC" step --harness opencode --run story --full | jq -r '.instructions | contains("EnterWorktree") | not')"

: > "$STUB_LOG"
OCOUT=$(cd "$ROC" && PATH="$OC:$PATH" "$CLERK" run --max-steps 1 --harness-cmd opencode --quiet 2>/dev/null)
eq "it is invoked as documented — run, json, and approval that is not manual" "true" \
   "$(head -1 "$STUB_LOG" | grep -q -- '--format json' && head -1 "$STUB_LOG" | grep -q -- '--auto' && echo true || echo false)"
eq "no --allowedTools, which that command does not take" "0" \
   "$(grep -c -- '--allowedTools' "$STUB_LOG")"
eq "the scoping reaches it through the environment instead" "true" \
   "$(grep -q 'OPENCODE_CONFIG=.*/opencode.json' "$STUB_LOG" && echo true || echo false)"
eq "and the config it was pointed at is readable after the run" "deny" \
   "$(jq -r '.permission.bash["*"]' "$(git -C "$ROC" rev-parse --path-format=absolute --git-common-dir)/clerk/runs/story/opencode.json")"
eq "the first turn names no session, because opencode names its own" "0" \
   "$(grep -c -- '--session' "$STUB_LOG")"
# Its events are not reduced into tool lines, but the envelope reader still finds the
# reply — a turn whose reply could not be read comes back marked failed.
eq "its reply is read even though its events are not reduced" "ground|opencode" \
   "$(printf '%s' "$OCOUT" | jq -r '[.steps[0].step, .steps[0].by] | join("|")')"
eq "so the run moved on from the step it did" "isolate" \
   "$(run "$ROC" step --run story | jq -r '.step')"

unset CLERK_AUDIT_PROMPTS STUB_LOG
rm -rf "$R" "$RG" "$RP" "$RD" "$RW" "$RS" "$RI" "$RV" "$RQ" "$RR" "$FAKE" "$IDLE" "$SEE" "$OC" "$ROC" "$PR" 2>/dev/null
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
