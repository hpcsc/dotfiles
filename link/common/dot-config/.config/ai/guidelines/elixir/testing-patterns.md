<!-- index: 1-22 -->
# Elixir Testing Patterns

## Section Index

Read only the section(s) that match your task. To locate a section in the file, grep for its heading (e.g., `rg -n '^## Unit of Behavior'`).

| Section | Use when... |
|---|---|
| [Core Principle](#core-principle-test-behavior-through-public-api-only) | Foundation — all consumers |
| [Independent Verification](#independent-verification) | Reviewing test quality, judging expected values |
| [What to Test](#what-to-test) | Deciding whether something is worth testing |
| [Unit of Behavior](#unit-of-behavior) | Deciding test boundaries, filtering worthless tests |
| [Test Structure](#test-structure) | Writing new tests (describe blocks, async, tags) |
| [Assertion Strictness](#assertion-strictness) | Choosing pattern matches vs full equality |
| [Error Paths](#error-paths-and-negative-path-invariants) | Testing tagged tuples, raises, rejected operations |
| [Process & Concurrency Testing](#process-and-concurrency-testing) | Testing GenServers, Tasks, message passing |
| [Test Double Patterns](#test-double-patterns) | Writing or reviewing fakes, Mox mocks, Bypass |
| [Database Testing](#database-testing) | Ecto sandbox, factories, persistence assertions |
| [Anti-Patterns](#anti-patterns) | Reviewing tests for common mistakes |
| [Detection Checklist](#detection-checklist) | Quick scan for red flags in test reviews |
| [Quick Reference](#quick-reference) | Reference table of practices |

---

## Core Principle: Test Behavior Through Public API Only

**Never test implementation details. Test observable behavior through public functions.**

Tests should verify **what** the system does (observable behaviors), not **how** it does it (implementation details).

In Elixir this means:
- Test through public functions (`def`), never private ones (`defp`)
- Never inspect internal process state with `:sys.get_state/1` to assert — state shape is an implementation detail
- Never call GenServer callbacks (`handle_call/3`, `handle_cast/2`, `handle_info/2`) directly in tests — go through the client API
- Observable behavior is: return values, messages received by the caller, and side effects visible through a boundary (database row, sent email, published event)

### Why This Matters
- Tests remain valid during refactoring (extracting helpers, reshaping state, swapping a GenServer for ETS)
- Tests document intended behavior
- Tests catch genuine bugs, not implementation changes

---

## Independent Verification

A test provides independent verification when its expected values come from **outside the implementation** — from business requirements, specifications, or domain knowledge — rather than restating what the code does.

The key question: **if the implementation breaks, will this test catch it?**

### Degrees of Independence

| Degree | Expected value source | Can it fail on a bug? | Value |
|---|---|---|---|
| Strong | Domain knowledge / spec | Yes, and failure is self-evidently wrong | High |
| Moderate | Externally verified lookup | Yes, but correctness requires checking an external source | Medium |
| Weak | Copied from production code | Yes, but correctness requires checking production intent | Low (change detector) |
| None (tautology) | Computed from production code | No | Zero |

```elixir
# ✅ Strong — expected value from the business rule (10% premium discount)
assert Discount.calculate(1000, :premium) == 100

# ❌ Tautology — expected value computed by the code under test
expected = Discount.calculate(1000, :premium)
assert Discount.calculate(1000, :premium) == expected
```

### The Substitution Test: Is the Code Under Test Even Exercised?

A change detector restates a value the code produces. Its extreme form is the **vacuous test**: one whose assertions pass no matter what the code under test does, because they never exercise its logic. (The tautology in the table above computes the expected value from the code; a vacuous test is subtler — its expected value can look independent, yet no stubbed version of the code would fail the assertion.)

> Mentally replace the function under test with a trivial stub — one that returns a hardcoded constant, returns its input unchanged, or forwards a collaborator's value verbatim. If every assertion still passes, the test is not testing that function.

Two shapes fail this test:

- **Constant pin** — the expected value is a literal copied from the production source, and the code performs no transformation to produce it. Any stub returning that constant passes. (This is the weak-independence change detector, seen from the code's side.)
- **Passthrough** — the function returns a collaborator's output verbatim and the assertion pins that output, so the assertion really tests the collaborator, not the function.

```elixir
# ❌ Constant pin — default_currency/0 hardcodes :usd, so the assertion holds
#    for any implementation that returns :usd; it never exercises the function.
assert Config.default_currency() == :usd
# ...same expected value, without calling the code under test:
assert :usd == :usd

# ❌ Passthrough — current_rate/1 forwards the gateway's reply verbatim, so the
#    assertion is really testing the stub, not current_rate/1.
gateway = fn :eur -> Decimal.new("1.09") end
assert Rates.current_rate(:eur, gateway: gateway) == Decimal.new("1.09")
# ...same expected value, straight from the collaborator:
assert gateway.(:eur) == Decimal.new("1.09")
```

**The tell:** if you can rewrite the assertion to produce the same expected value *without calling the code under test* — by calling the collaborator directly or just writing the constant — the code under test is not on trial.

**What legitimately survives substitution** (and is therefore NOT vacuous):
- A real transform — stub it and the assertion fails, because the code computes the value (e.g. `assert Discount.calculate(1000, :premium) == 100`).
- A **golden / contract test** over frozen external input — decoding frozen input stubbed to a constant no longer reproduces the expected struct, so it fails.

A test that survives substitution is exercising the code; a test that survives substitution *and* a behavior-preserving refactor is exercising it at the right altitude.

---

## What to Test

### Test-worthy
- Business logic and domain calculations
- Each clause of multi-clause functions that encodes a business rule
- Edge cases (empty lists, `nil`, missing map keys, boundary values)
- Error paths (`{:error, reason}` tuples, changeset errors, raised exceptions)
- State transitions observed through the public API (before/after a command)
- Message contracts (what a process sends to its caller or subscribers)

### NOT test-worthy (skip these)
- Trivial struct construction (`%User{}` with defaults) with no logic
- `defdelegate` pass-throughs
- Language or OTP runtime behavior (`Enum.map`, supervisor restarts of a stock child spec)
- Private functions — they are covered through their public callers
- Generated code (Ecto schema field access, derived protocols)

---

## Unit of Behavior

A **unit of behavior** is any piece of code that can produce an independently observable outcome — a return value, a state change, a message, a side effect, or a raised error — regardless of how many functions or modules it spans.

The unit is **one behavior**, not one function:

```elixir
# One unit: calculating the discount
def calculate_discount(price, tier), do: ...

# Another unit: applying it to an order
def apply_discount(order, discount), do: ...
```

### What is NOT a Unit of Behavior
- A private helper that formats a string, when the public caller already tests the formatted output
- Internal GenServer state that no caller observes
- A side effect always paired with another operation (persist + log — test persist, the log is incidental)
- An intermediate pipeline stage whose output only matters to the next stage

---

## Test Structure

Use `describe` blocks grouped by the operation under test; test names read as full sentences about the observed outcome.

```elixir
defmodule MyApp.Billing.InvoiceTest do
  use ExUnit.Case, async: true

  alias MyApp.Billing.Invoice

  describe "create" do
    test "totals line items into the invoice amount" do
      assert {:ok, invoice} = Invoice.create(line_items: [%{amount: 500}, %{amount: 1000}])
      assert invoice.total == 1500
    end

    test "rejects an invoice with no line items" do
      assert {:error, :empty_invoice} = Invoice.create(line_items: [])
    end
  end
end
```

### Rules
- **`async: true` by default** — drop it only when the test touches shared global state (named processes, named ETS tables, `Application.put_env`, the filesystem)
- **One behavior per `test`** — multiple assertions about the same outcome belong in one test; different outcomes split into separate tests
- **Fresh fixtures per test** — build state in `setup` or inline; never share mutable state via `setup_all`
- **`start_supervised!/1`** for any process the test needs — ExUnit guarantees shutdown ordering and cleanup
- **Tag slow/external tests** — `@tag :integration` with `ExUnit.configure(exclude: [:integration])` in `test_helper.exs`
- **Doctests** for pure functions with stable, illustrative examples — not as a substitute for edge-case tests

---

## Assertion Strictness

### Full equality for business values

When the caller depends on the complete value, compare with `==`:

```elixir
# ✅ Good — exact value
assert Money.add(Money.new(500), Money.new(1000)) == Money.new(1500)

# ❌ Avoid — weak assertion for a deterministic value
assert Money.add(Money.new(500), Money.new(1000)).amount > 0
```

### Pattern matching for partial shape

Pattern-match assertions are partial for maps and structs — unmatched keys are ignored. Use them when extra fields are irrelevant, and bind only what you assert on:

```elixir
# ✅ Good — strict on the fields the behavior is about
assert {:ok, %Invoice{total: 1500, status: :draft}} = Invoice.create(params)

# ❌ Avoid — shape-only match when the caller depends on values
assert {:ok, %Invoice{}} = Invoice.create(params)
```

### Other rules
- `assert_raise ExpectedError, ~r/message/, fn -> ... end` — assert the error type and message, not just "it raises"
- `assert_in_delta` for floats — never `==`
- Don't assert only `{:ok, _}` / `refute is_nil(result)` — those pass for almost any implementation, including wrong ones
- For changesets, assert on the specific error: `assert %{email: ["has already been taken"]} = errors_on(changeset)`

---

## Error Paths and Negative-Path Invariants

Expected failures return tagged tuples; test them as first-class behaviors:

```elixir
test "unknown ID returns not-found error" do
  assert {:error, :not_found} = Accounts.fetch_user("missing-id")
end
```

### Negative-path invariants

A rejected operation must leave state unchanged. After asserting the error, re-read through the public API and confirm nothing moved:

```elixir
test "overdrawn withdrawal leaves the balance untouched" do
  {:ok, account} = Accounts.open(balance: 100)

  assert {:error, :insufficient_funds} = Accounts.withdraw(account.id, 500)

  assert Accounts.balance(account.id) == 100
end
```

### Bang pairs

When a module exposes both `fetch/1` (tagged tuple) and `fetch!/1` (raises), test the tagged-tuple variant thoroughly; one test confirming the bang variant raises on the error case is enough.

---

## Process and Concurrency Testing

### Never `Process.sleep/1` to wait for async work

Sleeping makes tests slow and flaky. Synchronize on messages instead:

```elixir
# ❌ Bad — guesses at timing
MyApp.Notifier.notify_async(user)
Process.sleep(100)
assert called_somehow?()

# ✅ Good — the test double reports to the test process
test "notifies the user after signup" do
  test_pid = self()
  notifier = fn user -> send(test_pid, {:notified, user.id}) end

  {:ok, user} = Accounts.signup(%{email: "a@b.com"}, notifier: notifier)

  assert_receive {:notified, user_id}
  assert user_id == user.id
end
```

- `assert_receive` waits (default 100ms, configurable); `assert_received` checks the mailbox without waiting
- To detect a process exit, `Process.monitor/1` then `assert_receive {:DOWN, ^ref, :process, _, _}`
- Telemetry side effects: attach a handler that forwards events to `self()`, then `assert_receive`

### GenServer testing

Test through the client API (`MyServer.put/2`, `MyServer.get/1`), never via `:sys.get_state/1` or direct callback invocation. If the only way to observe an outcome is reading internal state, the behavior is not observable and likely not worth testing — or the API is missing a query function.

### `async: true` safety

A test file must be `async: false` (or redesigned) when it:
- Starts or talks to a globally named process
- Reads/writes a named ETS table shared across tests
- Mutates `Application` env (use per-test injection instead)
- Touches the filesystem or global registries

---

## Test Double Patterns

Preference order: **hand-rolled fakes > Mox (behaviour-verified mocks) > HTTP-boundary doubles**. Never globally replace a module you don't own.

### Fakes (preferred)

In-memory implementations of the behaviour, co-located with real implementations:

```elixir
defmodule MyApp.Mailer.Fake do
  @behaviour MyApp.Mailer

  @impl true
  def deliver(email) do
    send(self(), {:delivered, email})
    {:ok, %{id: "fake-#{email.to}"}}
  end
end
```

### Mox (contract-verified mocks)

Mox requires a behaviour — that is the point: expectations are checked against an explicit contract.

```elixir
Mox.defmock(MyApp.Mailer.Mock, for: MyApp.Mailer)

test "sends a receipt after payment" do
  expect(MyApp.Mailer.Mock, :deliver, fn email ->
    assert email.to == "a@b.com"
    {:ok, %{id: "msg-1"}}
  end)

  assert {:ok, _payment} = Payments.process(order, mailer: MyApp.Mailer.Mock)
end
```

Rules:
- `setup :verify_on_exit!` so unmet expectations fail the test
- An `expect` must contribute to verifying an **outcome** — a call-count check with no assertion on arguments or downstream result is not a behavioral test
- Mock only at boundaries you own via a behaviour. To stub a third-party SDK, define a consumer behaviour wrapping it and mock that

### HTTP boundary

Use `Bypass` or `Req.Test` to fake the remote server rather than stubbing the HTTP client module.

---

## Database Testing

- `Ecto.Adapters.SQL.Sandbox` per-test transactions allow `async: true` for DB tests
- Assert persistence through the public API (read back what was written), not by inspecting Repo internals
- Factories: plain functions or ExMachina; build only the fields the scenario needs
- Assert on the specific changeset errors, not just `refute changeset.valid?`

```elixir
test "persists the invoice with a draft status" do
  {:ok, invoice} = Billing.create_invoice(line_items: [%{amount: 500}])

  assert %Invoice{status: :draft, total: 500} = Billing.get_invoice!(invoice.id)
end
```

---

## Anti-Patterns

| # | Anti-pattern | Looks like | Instead |
|---|---|---|---|
| 1 | Testing private functions | Exporting `defp` for tests, `@compile {:no_warn_undefined, ...}` tricks | Test through the public caller |
| 2 | Asserting internal process state | `:sys.get_state(pid).buffer == [...]` | Assert through the client API |
| 3 | Tautology | `expected = fun(x); assert fun(x) == expected` | Fixed expected value from domain knowledge |
| 4 | No behavioral assertion | `assert {:ok, _} = ...` as the only assertion | Assert on the business values |
| 5 | Sleep-based synchronization | `Process.sleep(100)` before asserting | `assert_receive`, monitors |
| 6 | Call-count-only mocking | `expect(Mock, :deliver, 1, fn _ -> :ok end)` with no outcome assertion | Assert arguments and downstream result |
| 7 | Mocking modules you don't own | Stubbing `HTTPoison`/`Req` directly | Consumer behaviour wrapper, Bypass at the HTTP boundary |
| 8 | Change detector | Expected value copied from production code | Derive from spec/domain knowledge |
| 9 | Shared mutable fixtures | `setup_all` creating state tests mutate, named processes reused across tests | Fresh state per test, `start_supervised!` |
| 10 | Calling callbacks directly | `MyServer.handle_call({:get, k}, self(), state)` | Go through the client API |
| 11 | Testing the framework | Asserting a supervisor restarts a crashed child with stock options | Trust OTP; test your handler logic |

---

## Detection Checklist

When reviewing a test, check for these red flags:

- [ ] Expected value is computed from the code under test → tautology
- [ ] Only assertion is `assert {:ok, _}`, `assert result`, or `refute is_nil(...)` → missing behavioral assertion
- [ ] Test reads process internals (`:sys.get_state`, `Agent.get` on someone else's agent) → implementation detail
- [ ] Test invokes `handle_*` callbacks directly → implementation detail
- [ ] Test stubs a module the project doesn't own → mock boundary violation
- [ ] `Process.sleep` used to wait for an outcome → flaky test
- [ ] Mox `expect` whose function body asserts nothing and whose result is never checked → call-count-only
- [ ] Expected values copied from production code without domain justification → weak independence
- [ ] Assertion still passes when the code under test is replaced by a constant/passthrough stub (substitution test) → vacuous test
- [ ] `async: false` with no shared-state reason, or `async: true` with global state → wrong concurrency mode
- [ ] Error-path test doesn't confirm state is unchanged → missing negative-path invariant

---

## Quick Reference

| Practice | Rule |
|---|---|
| Framework | ExUnit; `use ExUnit.Case, async: true` when no shared global state |
| Test structure | `describe` per operation, one behavior per `test` |
| Naming | Test names are full sentences about the observed outcome |
| Module scope | Public functions only; never `defp`, callbacks, or `:sys.get_state` |
| Expected values | From domain knowledge, not production code |
| Assertion strictness | `==` for complete values, pattern match binding the fields that matter |
| Errors | Tagged tuples as first-class behavior; `assert_raise` with type + message |
| Negative paths | Rejected operations leave state unchanged — re-read and confirm |
| Async work | `assert_receive`/monitors; never `Process.sleep` |
| Processes | `start_supervised!`; test via client API |
| Test doubles | Fakes > Mox (behaviour-backed) > Bypass; never stub modules you don't own |
| Database | SQL Sandbox, assert by reading back through the public API |
| Coverage | Happy path + every error path the caller can hit |
