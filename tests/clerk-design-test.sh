#!/usr/bin/env bash
# Fixture-repo tests for `clerk design`. No framework: each case builds a throwaway Go
# module in a git repo, changes it on a branch, and asserts on what clerk reads from it.
# Run with: tests/clerk-design-test.sh
#
# The reader is a Go program, so these cases need `go` on PATH. Without it they are
# skipped and say so, the way clerk itself reports a design it could not read.
set -uo pipefail
BIN="$(cd "$(dirname "$0")/.." && pwd)/link/common/dot-local/bin"
CLERK="$BIN/clerk"
export PATH="$BIN:$PATH"
unset CLAUDECODE CLAUDE_CODE_SESSION_ID
export CLERK_HARNESS=claude
# The method text and the lens prompts come from this checkout, not from the stowed copy.
export CLERK_METHOD_DIR="$BIN/../../dot-config/.config/ai/method/implement"
# A cache of its own, so the reader is built here as it is on a first run.
CACHE=$(mktemp -d)
export XDG_CACHE_HOME="$CACHE"
PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has()  { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "text containing: $2" "$3" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "text without: $2" "$3" ;; *) ok "$1" ;; esac; }

if ! command -v go >/dev/null 2>&1; then
  printf 'clerk design: go is not installed — every case skipped\n'
  exit 0
fi

new_repo() {
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$d" init -q -b main
  git -C "$d" config user.email clerk@test
  git -C "$d" config user.name  Clerk
  git -C "$d" config commit.gpgsign false
  printf 'module example.com/shop\n\ngo 1.21\n' > "$d/go.mod"
  mkdir -p "$d/billing"
  cat > "$d/billing/payment.go" <<'EOF'
package billing

type Payment struct {
	ID     string
	Amount int
}

func (p *Payment) Capture() error { return nil }
EOF
  git -C "$d" add -A && git -C "$d" commit -qm "Seed"
  printf '%s' "$d"
}
run() { (cd "$1" && shift && "$CLERK" "$@"); }
commit_all() { git -C "$1" add -A && git -C "$1" commit -qm "$2"; }

# The feature: one new type with a method, a changed type, functions that share their
# parameters, and exported names that a caller, a struct tag and an interface account for.
feature() {
  local d=$1
  git -C "$d" checkout -q -b refunds
  cat > "$d/billing/payment.go" <<'EOF'
package billing

import "time"

type Payment struct {
	ID         string
	Amount     int
	CapturedAt time.Time `json:"captured_at"`
}

func (p *Payment) Capture() error { return nil }
EOF
  cat > "$d/billing/refund.go" <<'EOF'
package billing

type Refund struct {
	PaymentID string
	Amount    int
	reason    string
}

type Ledger struct{}

func NewRefund(payment Payment, amount int) (Refund, error) {
	limit := payment.Amount
	if amount > limit {
		return Refund{}, nil
	}
	return Refund{PaymentID: payment.ID, Amount: amount}, nil
}

func (r Refund) Issue() error  { return nil }
func (r Refund) String() string { return r.PaymentID }

func openBatch(store string, day int, size int) {}
func closeBatch(store string, day int)          {}
func countBatch(store string, day int) int      { return 0 }
EOF
  mkdir -p "$d/cmd/app"
  cat > "$d/cmd/app/main.go" <<'EOF'
package main

import "example.com/shop/billing"

func Run() {
	_, _ = billing.NewRefund(billing.Payment{}, 1)
}

func main() { Run() }
EOF
}

# --------------------------------------------------------------------------------
printf '\nshow --built — the design of a change, read from its code\n'

R=$(new_repo)
git -C "$R" checkout -q -b empty
V=$(run "$R" design show)
has "a branch with no Go change says so" "adds or changes no Go type or function" "$V"
eq "and the view is not refused for it" "0" "$(run "$R" design show >/dev/null 2>&1; printf '%s' $?)"

R=$(new_repo)
feature "$R"
V=$(run "$R" design show)
has "a new type is drawn as a class" 'class billing__Refund["billing.Refund"]' "$V"
has "with its exported and unexported fields marked" "+PaymentID string" "$V"
has "an unexported field keeps its minus" "-reason string" "$V"
has "a changed type shows its new field with a star" "+CapturedAt time.Time ★" "$V"
has "and counts the fields it kept" "…2 fields unchanged" "$V"
has "a new method sits on its type" "+Issue() error" "$V"
has "package functions share one box, with parameter names only" "-openBatch(store, day, size)" "$V"
has "new types are green" "style billing__Refund fill:#E6F4EA" "$V"
has "changed types are yellow" "style billing__Payment fill:#FFF8E1" "$V"
has "an exported function a caller uses names the caller" '| `NewRefund` | function | billing | cmd/app/main.go |' "$V"
has "an exported type nothing uses is flagged" '| `Ledger` | type | billing | **nothing** |' "$V"
has "a field with a struct tag is accounted for by the tag" '| `CapturedAt` | field | billing `Payment` | a struct tag |' "$V"
has "a method of a standard interface is accounted for by it" '| `String` | method | billing `Refund` | an interface method |' "$V"
hasnt "package main exports nothing anyone can import" '`Run`' "$V"
has "parameters three functions pass together are grouped" '| `day`, `store` | `closeBatch`, `countBatch`, `openBatch` |' "$V"
hasnt "the view does not list every name the change adds" "limit" "$V"

J=$(run "$R" design show --json)
eq "--json carries every new name for a reader that wants them all" "true" \
   "$(printf '%s' "$J" | jq -r '[.names[] | select(.kind=="variable" and .name=="limit")] | length == 1')"
eq "and the packages it read" "billing|cmd/app" "$(printf '%s' "$J" | jq -r '.dirs | join("|")')"

commit_all "$R" "Add refunds"
V=$(run "$R" design show --base main --head refunds)
has "a ref as the head is read from git, not from the working tree" 'class billing__Refund["billing.Refund"]' "$V"
hasnt "and without the working tree there is no use column" "Used outside its package by" "$V"

OUT=$(mktemp)
eq "--out writes the view and answers in JSON" "$OUT" "$(run "$R" design show --out "$OUT" | jq -r .written)"
has "with the view in the file" "## Types and functions" "$(cat "$OUT")"
rm -f "$OUT"

# Without go the design is reported as not read, never as a change with no design.
NOGO=$(mktemp -d)
for t in git python3 jq tar; do ln -s "$(command -v $t)" "$NOGO/$t"; done
V=$(cd "$R" && PATH="$NOGO:$BIN" "$CLERK" design show --base main)
has "a machine without go says the design was not read" "The design was not read: go is not installed." "$V"
rm -rf "$NOGO"

# A package at the root of the repository is the directory ".", which git names differently.
RR=$(new_repo)
git -C "$RR" checkout -q -b root
printf 'package shop\n\ntype Basket struct{ Items int }\n' > "$RR/basket.go"
commit_all "$RR" "Add a basket"
has "a package at the repository root is read from git too" 'class ___Basket["shop.Basket"]' \
   "$(run "$RR" design show --base main --head root)"
rm -rf "$RR"

eq "--help prints a USAGE block" "1" "$(run "$R" design --help | grep -c '^USAGE')"
eq "an unknown verb is a usage error" "2" "$(run "$R" design draw >/dev/null 2>&1; printf '%s' $?)"

# --------------------------------------------------------------------------------
printf '\nthe planned design — read, bound to a run, and drawn against the code\n'

# A run on its own branch, with a breakdown whose task record names a planned design.
planned_run() {  # repo
  local d=$1
  git -C "$d" checkout -q -b refunds
  # Work on the branch before the run starts is not the run's work.
  printf 'package billing\n\ntype Pre struct{}\n' > "$d/billing/pre.go"
  commit_all "$d" "Earlier work"
  mkdir -p "$d/tasks"
  printf '# refunds\n\n### Task 1: Refund\n- [ ] a\n\n### Task 2: Ledger\n- [ ] b\n' > "$d/tasks/refunds.md"
  jq -n '{story: "refunds", tasks_file: "tasks/refunds.md", design_file: "tasks/refunds.design.yaml", tasks: [
    {n: 1, title: "Refund", depends_on: [], done: false, certainty: "low", blast_radius: "low", patterns_to_follow: []},
    {n: 2, title: "Ledger", depends_on: [1], done: false, certainty: "low", blast_radius: "low", patterns_to_follow: []}]}' \
    > "$d/tasks/refunds.json"
  cat > "$d/tasks/refunds.design.yaml" <<'EOF2'
design: planned
types:
  - name: Refund
    package: billing
    change: new
    does: returns part or all of one payment
    owns: [the refunds of a payment never exceed its amount]
    fields: [PaymentID, Amount]
    methods: [Issue]
  - name: Chargeback
    package: billing
    change: new
    does: records money the bank took back
functions:
  - NewRefund(payment, amount) (Refund, error)
words:
  - concept: money that goes back to the customer
    word: refund
    not: [reversal]
EOF2
  commit_all "$d" "Breakdown"
  run "$d" step start refunds --request "Add refunds" >/dev/null
}

R=$(new_repo)
planned_run "$R"
LEDGER="$R/.git/clerk/runs/refunds"

BADDIR=$(mktemp -d)
printf 'design: planned\ntype:\n  - name: Refund\n' > "$BADDIR/typo.yaml"
eq "a misspelt key is refused, not read as a design with no types" "1" \
   "$(run "$R" design show --planned "$BADDIR/typo.yaml" >/dev/null 2>&1; printf '%s' $?)"
has "and the error names the key" 'unknown key `type`' "$(run "$R" design show --planned "$BADDIR/typo.yaml" 2>/dev/null)"
printf 'design: none\n' > "$BADDIR/none.yaml"
has "design: none needs the reason the story has no design" '`design: none` needs a `reason`' \
   "$(run "$R" design show --planned "$BADDIR/none.yaml" 2>/dev/null)"
printf 'design: planned\ntypes:\n  - name: Refund\n    change: rewritten\n' > "$BADDIR/change.yaml"
has "a type is new or changed, nothing else" '`change` must be `new` or `changed`' \
   "$(run "$R" design show --planned "$BADDIR/change.yaml" 2>/dev/null)"
printf 'design: none\nreason: one config line\n' > "$BADDIR/none.yaml"
has "a design of none is drawn as its reason" "The story needs no design: one config line" \
   "$(run "$R" design show --planned "$BADDIR/none.yaml")"

V=$(run "$R" design show --planned "$R/tasks/refunds.design.yaml")
has "a planned type is drawn with its planned members" "+Issue()" "$V"
has "and a new planned type is green" "fill:#E6F4EA" "$V"
has "what each type does and owns is a table" "| \`Refund\` | billing | returns part or all of one payment | the refunds of a payment never exceed its amount |" "$V"
has "the planned words are a table" "| money that goes back to the customer | \`refund\` | \`reversal\` |" "$V"

B=$(run "$R" step done decompose --tasks-file tasks/refunds.md)
eq "binding the breakdown binds its planned design" "true|planned" \
   "$(printf '%s' "$B" | jq -r '[(.bound|tostring), .design] | join("|")')"
eq "and the ledger keeps the design as planned" "Refund,Chargeback" \
   "$(jq -r '[.planned.types[].name] | join(",")' "$LEDGER/design.json")"
has "a run's own planned design is drawn with no file named" 'class billing__Refund["billing.Refund"]' \
   "$(run "$R" design show --planned)"

cp "$R/tasks/refunds.design.yaml" "$BADDIR/keep.yaml"
printf 'design: maybe\n' > "$R/tasks/refunds.design.yaml"
eq "a planned design that does not read refuses the bind" "1|false" \
   "$(run "$R" step done decompose --tasks-file tasks/refunds.md >"$BADDIR/out" 2>/dev/null; printf '%s|' $?; jq -r '.bound|tostring' "$BADDIR/out")"
cp "$BADDIR/keep.yaml" "$R/tasks/refunds.design.yaml"
run "$R" step done decompose --tasks-file tasks/refunds.md >/dev/null

cat > "$R/billing/refund.go" <<'EOF2'
package billing

type Refund struct {
	PaymentID string
	Amount    int
}

type Ledger struct{}

func (r Refund) Issue() error { return nil }
EOF2
V=$(run "$R" design show)
hasnt "the default base is the commit the run started from, not the merge-base" "Pre" "$V"
has "so the run's own type is there" 'class billing__Refund["billing.Refund"]' "$V"

eq "a note without a reason is a usage error" "2" "$(run "$R" design note Ledger "" >/dev/null 2>&1; printf '%s' $?)"
N=$(run "$R" design note Ledger "the batch totals need one owner" --affects 2)
eq "a note records the change with the task in flight" "D1|1|2" \
   "$(printf '%s' "$N" | jq -r '[.recorded, (.note.task|tostring), (.note.affects|map(tostring)|join(","))] | join("|")')"

printf '| Concept | Words in this change | Finding |\n| --- | --- | --- |\n| a refund | `Refund` | none |\n' > "$BADDIR/words.md"
eq "the design check's words table is kept for the view" "words" "$(run "$R" design words --file "$BADDIR/words.md" | jq -r .recorded)"

V=$(run "$R" design show --changes)
has "a type the plan does not name is orange" "style billing__Ledger fill:#FDEBD0" "$V"
has "a planned type the code does not have is a dashed box" 'class billing__Chargeback["billing.Chargeback"]' "$V"
has "drawn dashed" "stroke-dasharray: 5 5" "$V"
has "each design change is listed with its reason" "| D1 | 1 | \`Ledger\` | the batch totals need one owner | not done |" "$V"
has "and the words table follows" "| a refund | \`Refund\` | none |" "$V"

git -C "$R" checkout -q main
eq "a note off the run's branch is refused" "2" "$(run "$R" design note Ledger "x" >/dev/null 2>&1; printf '%s' $?)"
git -C "$R" checkout -q refunds
rm -rf "$BADDIR"

# --------------------------------------------------------------------------------
printf '\nfinish — a design change with no reason refuses the task\n'

R=$(new_repo)
planned_run "$R"
run "$R" step done decompose --tasks-file tasks/refunds.md >/dev/null
cat > "$R/billing/refund.go" <<'EOF2'
package billing

type Refund struct {
	PaymentID string
	Amount    int
}

type Ledger struct{}

func (r Refund) Issue() error { return nil }
EOF2
F=$(run "$R" finish 1 -- billing/refund.go)
eq "a type the plan does not name refuses the task" "1" "$(run "$R" finish 1 -- billing/refund.go >/dev/null 2>&1; printf '%s' $?)"
eq "and names the rule and the type" "design-unplanned-type|Ledger" \
   "$(printf '%s' "$F" | jq -r '.design_findings | map(.rule + "|" + .name) | join(",")')"
has "with the command that records the reason" 'clerk design note Ledger' "$(printf '%s' "$F" | jq -r '.design_findings[0].message')"
eq "an export nothing uses waits for the last task: a later one can add the caller" "0" \
   "$(printf '%s' "$F" | jq -r '[.design_findings[] | select(.rule=="unused-export")] | length')"
eq "the task is not marked done" "false" "$(jq -r '.tasks[0].done' "$R/tasks/refunds.json")"
eq "and its files stay staged" "billing/refund.go" "$(git -C "$R" diff --cached --name-only)"

run "$R" design note Ledger "the batch totals need one owner" >/dev/null
F=$(run "$R" finish 1 -- billing/refund.go)
eq "with the reason recorded, the same task finishes" "true|clean" \
   "$(printf '%s' "$F" | jq -r '[(.done|tostring), .design] | join("|")')"
commit_all "$R" "Task 1"

cat >> "$R/billing/refund.go" <<'EOF2'

func NewRefund(payment Payment, amount int) (Refund, error) { return Refund{}, nil }

func (r Refund) Total() int { return r.Amount }
EOF2
F=$(run "$R" finish 2 -- billing/refund.go)
eq "at the last task, a planned type never built and an unused export refuse it" \
   "design-absent-type|Chargeback,unused-export|Total" \
   "$(printf '%s' "$F" | jq -r '.design_findings | map(.rule + "|" + .name) | join(",")')"
hasnt "an export the plan names is exported on purpose, with or without a caller" "NewRefund" "$F"
hasnt "and one a design change explains is not refused again" "unused-export|Ledger" \
   "$(printf '%s' "$F" | jq -r '.design_findings | map(.rule + "|" + .name) | join(",")')"

cat > "$R/billing/refund.go" <<'EOF2'
package billing

type Refund struct {
	PaymentID string
	Amount    int
}

type Ledger struct{}

func (r Refund) Issue() error { return nil }

func NewRefund(payment Payment, amount int) (Refund, error) { return Refund{}, nil }

func (r Refund) total() int { return r.Amount }
EOF2
run "$R" design note Chargeback "a chargeback is a refund the bank starts; Refund carries it" >/dev/null
eq "unexported, and with the planned type's reason recorded, the last task finishes" "true" \
   "$(run "$R" finish 2 -- billing/refund.go | jq -r '.done|tostring')"
commit_all "$R" "Task 2"

# A design that cannot be read does not block a finished task, and does not read as a refusal.
printf 'package billing\n\ntype Audit struct{}\n' > "$R/billing/audit.go"
READER=$(ls "$CACHE"/clerk/design-go-* | head -1)
mv "$READER" "$READER.keep"
printf '#!/bin/sh\necho broken >&2\nexit 3\n' > "$READER"
chmod +x "$READER"
git -C "$R" checkout -q -b crash
mkdir -p "$R/.git/clerk/runs/crash"
cp "$R/.git/clerk/runs/refunds/run.json" "$R/.git/clerk/runs/crash/run.json"
cp "$R/.git/clerk/runs/refunds/design.json" "$R/.git/clerk/runs/crash/design.json"
jq '.tasks |= map(.done = false)' "$R/tasks/refunds.json" > "$R/tasks/refunds.json.tmp" && mv "$R/tasks/refunds.json.tmp" "$R/tasks/refunds.json"
F=$(run "$R" finish 1 -- billing/audit.go tasks/refunds.json)
eq "a reader that fails leaves the task finished, and says why the design was not judged" "true|could not run: RuntimeError: the design reader failed: broken" \
   "$(printf '%s' "$F" | jq -r '[(.done|tostring), .design] | join("|")')"
mv "$READER.keep" "$READER"
git -C "$R" reset -q --hard && git -C "$R" checkout -q refunds

# A breakdown with no planned design is not judged, and says so.
R2=$(new_repo)
git -C "$R2" checkout -q -b plain
mkdir -p "$R2/tasks"
printf '# plain\n\n### Task 1: One\n- [ ] a\n' > "$R2/tasks/plain.md"
jq -n '{story: "plain", tasks_file: "tasks/plain.md", tasks: [{n: 1, title: "One", depends_on: [], done: false}]}' > "$R2/tasks/plain.json"
commit_all "$R2" "Breakdown"
run "$R2" step start plain --request "Plain" >/dev/null
B=$(run "$R2" step done decompose --tasks-file tasks/plain.md)
has "a task record with no design_file binds, and says nothing was planned" "not planned" "$(printf '%s' "$B" | jq -r .design)"
printf 'package billing\n\ntype Extra struct{}\n' > "$R2/billing/extra.go"
eq "and its tasks finish without a design judgment" "true|no planned design is bound to the run" \
   "$(run "$R2" finish 1 -- billing/extra.go | jq -r '[(.done|tostring), .design] | join("|")')"
rm -rf "$R2"

# --------------------------------------------------------------------------------
printf '\ndesign check — a design change is judged before the next task builds on it\n'

R=$(new_repo)
planned_run "$R"
run "$R" step done ground --caller inbound >/dev/null
run "$R" step done decompose --tasks-file tasks/refunds.md >/dev/null
eq "with no design change, the run builds the first task" "build|1" "$(run "$R" step | jq -r '[.step, (.n|tostring)] | join("|")')"
cat > "$R/billing/refund.go" <<'EOF2'
package billing

type Refund struct {
	PaymentID string
	Amount    int
}

type Ledger struct{}

func (r Refund) Issue() error { return nil }
EOF2
run "$R" design note Ledger "the batch totals need one owner" >/dev/null
F=$(run "$R" finish 1 -- billing/refund.go)
eq "the task that made a design change hands over to its design check" "design-check|D1" \
   "$(printf '%s' "$F" | jq -r '[.after_commit.step, .after_commit.change.id] | join("|")')"
commit_all "$R" "Task 1"
S=$(run "$R" step --full)
eq "and the step stays there after the commit" "design-check" "$(printf '%s' "$S" | jq -r .step)"
has "with the method text for the step" "## Check a design change" "$(printf '%s' "$S" | jq -r .instructions)"
P=$(run "$R" design prompt D1)
has "the prompt holds the change and its reason" 'D1 `Ledger`: the batch totals need one owner' "$P"
has "and the commit to read" "$(git -C "$R" rev-parse HEAD)" "$P"
has "and the design lens" "Your lens is DESIGN" "$P"
has "with the language's naming patterns to read" "go/naming-patterns.md" "$P"
eq "an unknown design change has no prompt" "1" "$(run "$R" design prompt D9 >/dev/null 2>&1; printf '%s' $?)"
D=$(run "$R" step done design-check D1 --fixed)
eq "closing the check moves the run to the next task" "build|2" "$(printf '%s' "$D" | jq -r '[.next.step, (.next.n|tostring)] | join("|")')"
eq "and the ledger records that the check changed code" "true" "$(jq -r '.notes[0].check.fixed|tostring' "$R/.git/clerk/runs/refunds/design.json")"
has "the changes view says the check is done" "| D1 | 1 | \`Ledger\` | the batch totals need one owner | fixed |" \
   "$(run "$R" design show --changes)"
eq "an unknown design change cannot be closed" "1" "$(run "$R" step done design-check D9 >/dev/null 2>&1; printf '%s' $?)"

# --------------------------------------------------------------------------------
printf '\naudit — a design lens runs when the change has a design to judge\n'

panel() {  # scope-json
  (cd "$BIN" && python3 -c '
import json, sys
import clerk_audit_panel as p
lenses, not_run = p.build_panel(json.loads(sys.argv[1]), p.load_prompts())
print(json.dumps({"lenses": [{"key": l["key"], "agent": l["agent"], "prompt": l["prompt"]} for l in lenses], "not_run": not_run}))
' "$1")
}
SCOPE='{"base": "a", "head": "b", "summary": "s", "languages": ["Go"], "files": ["x.go"], "by_language": [{"language": "Go", "files": ["x.go"]}], "signals": {"design": true}}'
L=$(panel "$SCOPE")
eq "a change with a design gets the design lens, on the generic reviewer" "semantic-reviewer" \
   "$(printf '%s' "$L" | jq -r '.lenses[] | select(.key=="design") | .agent')"
has "with the lens text inside the audit's own preamble" "Your lens is DESIGN" \
   "$(printf '%s' "$L" | jq -r '.lenses[] | select(.key=="design") | .prompt')"
has "and the finding contract" "Every finding needs a stable kebab-case" \
   "$(printf '%s' "$L" | jq -r '.lenses[] | select(.key=="design") | .prompt')"
L=$(panel "$(printf '%s' "$SCOPE" | jq -c '.signals = {"design": false, "design_reason": "clerk reads the design of Go code only"}')")
eq "a change without one names the lens it did not run, and why" "design — clerk reads the design of Go code only" \
   "$(printf '%s' "$L" | jq -r '.not_run[] | select(startswith("design"))')"

R=$(new_repo)
feature "$R"
commit_all "$R" "Add refunds"
signal() { (cd "$BIN" && python3 -c 'import json, sys, clerk_design as d; print(json.dumps(d.audit_signal(*sys.argv[1:4])))' "$@"); }
eq "the signal is read from the code between the scope's base and head" "true" \
   "$(signal "$R" main refunds | jq -r '.[0]|tostring')"
git -C "$R" checkout -q -b docs main
printf 'more\n' >> "$R/README.md"
commit_all "$R" "Docs"
eq "a change with no Go type or function has none, and says so" "false|the change adds or changes no Go type, function or exported name" \
   "$(signal "$R" main docs | jq -r '[(.[0]|tostring), .[1]] | join("|")')"

# --------------------------------------------------------------------------------
printf '\nstack — a deliverable'"'"'s pull request carries its design\n'

R=$(new_repo)
feature "$R"
commit_all "$R" "Add refunds"
TF=$(mktemp)
printf '# refunds\n\n## Story Reference\nRefund a payment.\n\n## Boundaries\nNo chargebacks.\n\n## Tasks\n' > "$TF"
mkdir -p "$R/.git/clerk/runs/refunds"
jq -n '{notes: [{id: "D1", task: 1, name: "Ledger", reason: "the batch totals need one owner", check: {fixed: false}}]}' \
  > "$R/.git/clerk/runs/refunds/design.json"
describe() { (cd "$BIN" && python3 -c '
import sys, clerk_stack as s
print(s.pr_description({"tasks_file": sys.argv[1], "base": sys.argv[2], "branch": sys.argv[3]}, sys.argv[4]))' "$@"); }
D=$(describe "$TF" main refunds "$R")
has "the description keeps the breakdown's story reference" "Refund a payment." "$D"
has "and adds the design under its own heading" "## Design" "$D"
has "with the diagram of the deliverable's own types" 'class billing__Refund["billing.Refund"]' "$D"
has "and the design changes its run recorded" "| D1 | 1 | \`Ledger\` | the batch totals need one owner | clean |" "$D"
git -C "$R" checkout -q -b docs main
printf 'more\n' >> "$R/README.md"
commit_all "$R" "Docs"
hasnt "a deliverable with no Go type or function has no design section" "## Design" "$(describe "$TF" main docs "$R")"
rm -f "$TF"

# --------------------------------------------------------------------------------
printf '\ncorrections — what a person changed after the run handed its branch over\n'

R=$(new_repo)
planned_run "$R"
run "$R" step done decompose --tasks-file tasks/refunds.md >/dev/null
run "$R" design note Ledger "the batch totals need one owner" >/dev/null
eq "a run that has not finished has nothing handed over to compare with" "1" \
   "$(run "$R" design corrections >/dev/null 2>&1; printf '%s' $?)"
cat > "$R/billing/refund.go" <<'EOF2'
package billing

type Refund struct {
	PaymentID string
	Amount    int
}

type Ledger struct{}
EOF2
commit_all "$R" "Add refunds"
# The run hands over here. Recorded the way the step table records it at `finished`.
RJ="$R/.git/clerk/runs/refunds/run.json"
jq --arg c "$(git -C "$R" rev-parse HEAD)" '.finished = true | .finished_commit = $c' "$RJ" > "$RJ.tmp" && mv "$RJ.tmp" "$RJ"
eq "a finished run with no later commits has no corrections" "0" "$(run "$R" design corrections | jq -r '.commits | length')"
cat > "$R/billing/refund.go" <<'EOF2'
package billing

type Refund struct {
	PaymentID string
	Amount    int
}

type ledger struct{}
EOF2
commit_all "$R" "Keep the ledger unexported"
C=$(run "$R" design corrections)
eq "the commits after the hand-over are listed" "Keep the ledger unexported" "$(printf '%s' "$C" | jq -r '.commits[0] | sub("^[0-9a-f]+ "; "")')"
eq "with the files they changed" "billing/refund.go" "$(printf '%s' "$C" | jq -r '.files | join(",")')"
eq "and the design of the correction: the exported type went, an unexported one came" "Ledger|ledger" \
   "$(printf '%s' "$C" | jq -r '.design.packages[0] | [(.removed_types | join(",")), (.types | map(.name) | join(","))] | join("|")')"
eq "beside the reason the run gave for the type" "the batch totals need one owner" "$(printf '%s' "$C" | jq -r '.notes[0].reason')"
eq "and the planned design it left" "Refund,Chargeback" "$(printf '%s' "$C" | jq -r '[.planned.types[].name] | join(",")')"
git -C "$R" checkout -q main
eq "off the run's branch, the run is named" "Keep the ledger unexported" \
   "$(run "$R" design corrections --run refunds | jq -r '.commits[0] | sub("^[0-9a-f]+ "; "")')"
eq "and a run that does not exist is refused" "2" "$(run "$R" design corrections --run nope >/dev/null 2>&1; printf '%s' $?)"

# --------------------------------------------------------------------------------
rm -rf "$R" "$CACHE" 2>/dev/null
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
