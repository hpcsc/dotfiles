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
rm -rf "$R" "$CACHE" 2>/dev/null
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
