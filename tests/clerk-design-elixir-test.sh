#!/usr/bin/env bash
# Fixture-repo tests for `clerk design` on Elixir code. No framework: each case builds a
# throwaway Mix project in a git repo, changes it on a branch, and asserts on what clerk
# reads from it. Run with: tests/clerk-design-elixir-test.sh
#
# The reader is an Elixir script, so these cases need `elixir` on PATH. Without it they are
# skipped and say so, the way clerk itself reports a design it could not read.
set -uo pipefail
BIN="$(cd "$(dirname "$0")/.." && pwd)/link/common/dot-local/bin"
CLERK="$BIN/clerk"
export PATH="$BIN:$PATH"
unset CLAUDECODE CLAUDE_CODE_SESSION_ID
export CLERK_HARNESS=claude
export CLERK_MUTANTS_BIN=/nonexistent/mutants
export CLERK_METHOD_DIR="$BIN/../../dot-config/.config/ai/method/implement"

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has()  { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "text containing: $2" "$3" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "text without: $2" "$3" ;; *) ok "$1" ;; esac; }

if ! command -v elixir >/dev/null 2>&1; then
  printf 'clerk design (Elixir): elixir is not installed — every case skipped\n'
  exit 0
fi

new_repo() {
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$d" init -q -b main
  git -C "$d" config user.email clerk@test
  git -C "$d" config user.name  Clerk
  git -C "$d" config commit.gpgsign false
  printf 'defmodule Shop.MixProject do\n  use Mix.Project\nend\n' > "$d/mix.exs"
  mkdir -p "$d/lib/billing"
  cat > "$d/lib/billing/payment.ex" <<'EOF'
defmodule Billing.Payment do
  defstruct [:id, :amount]

  def capture(payment), do: payment
end
EOF
  git -C "$d" add -A && git -C "$d" commit -qm "Seed"
  printf '%s' "$d"
}
run() { (cd "$1" && shift && "$CLERK" "$@"); }
commit_all() { git -C "$1" add -A && git -C "$1" commit -qm "$2"; }

# --------------------------------------------------------------------------------
printf '\nshow — the design of an Elixir change, read from its code\n'

R=$(new_repo)
git -C "$R" checkout -q -b refunds
cat > "$R/lib/billing/payment.ex" <<'EOF'
defmodule Billing.Payment do
  defstruct [:id, :amount, :refunded_at]

  def capture(payment), do: payment

  def capture(payment, at), do: %{payment | refunded_at: at}

  def refund(payment), do: refund(payment, payment.amount)

  def refund(payment, amount) when amount > 0 do
    remaining = payment.amount - amount
    %{payment | amount: remaining}
  end
end
EOF
cat > "$R/lib/billing/refund.ex" <<'EOF'
defmodule Billing.Refund do
  use Ecto.Schema

  schema "refunds" do
    field :amount, :integer
    belongs_to :payment, Billing.Payment
    timestamps(updated_at: false)
  end

  def issue(%__MODULE__{} = refund, reason \\ :customer), do: check(refund, reason)

  defp check(refund, _reason), do: refund

  defmodule Reason do
    def all, do: [:customer, :fraud]
  end
end
EOF
commit_all "$R" "Add refunds"
V=$(run "$R" design show --base main --head refunds --json)
eq "a module is a type of the directory its file is in, a nested one under its parent's name" \
   "lib/billing|Billing.Payment,Billing.Refund,Billing.Refund.Reason" \
   "$(printf '%s' "$V" | jq -r '[.packages[0].dir, ([.packages[0].types[].name] | sort | join(","))] | join("|")')"
eq "a module with new members is changed, and a module the base does not have is new" "changed|new" \
   "$(printf '%s' "$V" | jq -r '[.packages[0].types[] | select(.name == "Billing.Payment" or .name == "Billing.Refund") | .status] | join("|")')"
eq "a function of two arities is two functions: a new arity is new, and the old one is unchanged and not shown" \
   "capture/2:new,refund/1:new,refund/2:new" \
   "$(printf '%s' "$V" | jq -r '.packages[0].types[] | select(.name == "Billing.Payment") | [.methods[] | "\(.name)/\(.signature | split(",") | length):\(.status)"] | join(",")')"
eq "def is public and defp is private" "issue:true,check:false" \
   "$(printf '%s' "$V" | jq -r '.packages[0].types[] | select(.name == "Billing.Refund") | [.methods[] | "\(.name):\(.exported)"] | join(",")')"
eq "a schema is read with its fields, its associations and its timestamps" "schema|amount,payment,inserted_at" \
   "$(printf '%s' "$V" | jq -r '.packages[0].types[] | select(.name == "Billing.Refund") | [.kind, ([.fields[].name] | join(","))] | join("|")')"
eq "a struct's new field is read, and the old ones are counted" "refunded_at|2" \
   "$(printf '%s' "$V" | jq -r '.packages[0].types[] | select(.name == "Billing.Payment") | [([.fields[].name] | join(",")), (.fields_unchanged | tostring)] | join("|")')"
eq "the new public names are its public functions, never a module or a field" "all,capture,issue,refund,refund|function" \
   "$(printf '%s' "$V" | jq -r '[([.exported[].name] | sort | join(",")), ([.exported[].kind] | unique | join(","))] | join("|")')"

M=$(run "$R" design show --base main --head refunds)
has "the view names a module by its full name" 'class lib_billing__Billing_Refund["Billing.Refund"]' "$M"
has "and marks a public function with +" "+issue(refund, reason)" "$M"
has "a private one with -, and a pattern or an ignored argument as pattern" "-check(refund, pattern)" "$M"
has "a schema field with its type, and public" "+amount integer" "$M"
hasnt "and does not say that the change has no type or function" "no type or function" "$M"

W=$(run "$R" design show --json)
eq "the working tree against the start of the branch reads the same modules" "Billing.Payment,Billing.Refund,Billing.Refund.Reason" \
   "$(printf '%s' "$W" | jq -r '[.packages[0].types[].name] | sort | join(",")')"
eq "with no elixir on PATH the design is not read, and says why" "elixir is not installed" \
   "$(cd "$R" && PATH=/usr/bin:/bin "$CLERK" design show --base main --head refunds --json | jq -r '.not_checked')"
rm -rf "$R"

# --------------------------------------------------------------------------------
printf '\nfinish — an Elixir run is judged against its planned design\n'

R=$(new_repo)
mkdir -p "$R/tasks"
git -C "$R" checkout -q -b refunds
printf '# refunds\n\n### Task 1: Refund\n- [ ] a\n\n### Task 2: Ledger\n- [ ] b\n' > "$R/tasks/refunds.md"
jq -n '{story: "refunds", tasks_file: "tasks/refunds.md", design_file: "tasks/refunds.design.yaml", tasks: [
  {n: 1, title: "Refund", depends_on: [], done: false, certainty: "low", blast_radius: "low", patterns_to_follow: []},
  {n: 2, title: "Ledger", depends_on: [1], done: false, certainty: "low", blast_radius: "low", patterns_to_follow: []}]}' \
  > "$R/tasks/refunds.json"
cat > "$R/tasks/refunds.design.yaml" <<'EOF'
design: planned
types:
  - name: Billing.Refund
    package: lib/billing
    change: new
    does: returns part or all of one payment
    methods: [issue]
  - name: Billing.Ledger
    package: lib/billing
    change: new
    does: keeps the money that each refund moves
    methods: [record]
  - name: Billing.RefundStub
    package: test/support
    change: new
    does: answers for a refund in a test
EOF
commit_all "$R" "Breakdown"
run "$R" step start refunds --request "Add refunds" >/dev/null
run "$R" step done decompose --tasks-file tasks/refunds.md >/dev/null

mkdir -p "$R/test/support" "$R/test/billing"
cat > "$R/lib/billing/refund.ex" <<'EOF'
defmodule Billing.Refund do
  def issue(payment), do: payment

  def orphan, do: :nobody_calls_this
end

defmodule Billing.Audit do
end
EOF
printf 'defmodule Billing.RefundStub do\n  def refunded, do: :ok\nend\n' > "$R/test/support/refund_stub.ex"
printf 'defmodule Billing.RefundTest do\n  test "x", do: Billing.RefundStub.refunded()\nend\n' > "$R/test/billing/refund_test.exs"
F=$(run "$R" finish 1 -- lib/billing/refund.ex test/support/refund_stub.ex test/billing/refund_test.exs); FRC=$?
eq "a module the planned design does not name refuses the task" "1|design-unplanned-type:Billing.Audit" \
   "$FRC|$(printf '%s' "$F" | jq -r '[.design_findings[] | "\(.rule):\(.name)"] | join(",")')"
run "$R" design note Billing.Audit "the refunds need a record of who issued each" >/dev/null
F=$(run "$R" finish 1 -- lib/billing/refund.ex test/support/refund_stub.ex test/billing/refund_test.exs); FRC=$?
eq "a design note answers it, and a planned module is not judged absent before the last task" "0|true|clean" \
   "$FRC|$(printf '%s' "$F" | jq -r '[(.done|tostring), .design] | join("|")')"
git -C "$R" commit -qm "Task 1"

mkdir -p "$R/lib/billing/plug"
cat > "$R/lib/billing/plug/refund_plug.ex" <<'EOF'
defmodule Billing.RefundPlug do
  @behaviour Plug

  def init(opts), do: opts
  def call(conn, _opts), do: conn

  @impl true
  def handle_refund(conn), do: conn
end
EOF
F=$(run "$R" finish 2 -- lib/billing/plug/refund_plug.ex); FRC=$?
# issue is planned, refunded is test support code that the tests call, and init, call and
# handle_refund are callbacks: none of them is in the list.
eq "at the last task, a planned module the code lacks and a public function nothing calls refuse it" \
   "1|design-absent-type:Billing.Ledger,design-unplanned-type:Billing.RefundPlug,unused-export:orphan" \
   "$FRC|$(printf '%s' "$F" | jq -r '[.design_findings[] | "\(.rule):\(.name)"] | sort | join(",")')"
has "the function is told to become private with defp" "make it private with defp" \
   "$(printf '%s' "$F" | jq -r '.design_findings[] | select(.rule == "unused-export") | .message')"
mkdir -p "$R/lib/billing/ledger"
printf 'defmodule Billing.Ledger do\n  def record(payment), do: Billing.Refund.orphan()\nend\n' > "$R/lib/billing/ledger/ledger.ex"
run "$R" design note Billing.RefundPlug "the refunds route needs a plug" >/dev/null
F=$(run "$R" finish 2 -- lib/billing/plug/refund_plug.ex lib/billing/ledger/ledger.ex); FRC=$?
eq "with the planned module built, in a directory the plan did not name, and a caller for the function, the last task finishes" "0|true|clean" \
   "$FRC|$(printf '%s' "$F" | jq -r '[(.done|tostring), .design] | join("|")')"
rm -rf "$R"

# --------------------------------------------------------------------------------
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
