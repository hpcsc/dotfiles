---
name: mutate-go
description: Mutation-test a Go file with gremlins to find out whether its tests would actually catch a defect. Breaks the code one operator at a time and reports which changes went unnoticed, then triages each survivor into a concrete action. Use before trusting a suite for a refactor, when reviewing newly added tests, or when a package looks suspiciously green.
disable-model-invocation: true
---

# Go Mutation Testing

Find out whether the tests for a Go file would notice if the code were wrong: $ARGUMENTS

Coverage says a line executed. Mutation testing says a change to that line would
fail a test. Those come apart constantly — a test that calls a function and
asserts only `require.NoError` gives full coverage and no protection.

`$ARGUMENTS` names the file to mutate, plus any of the flags below. It may name
either the source file or its `_test.go` counterpart — the script maps a test
file to the code it covers.

## Running It

Delegate the run to the script — it handles module discovery, narrowing gremlins
to the one file, the timeout problem, and formatting:

```bash
$HOME/.claude/skills/mutate-go/mutate.sh path/to/file.go
```

Only these flags are understood; the script rejects anything else rather than
forwarding it to gremlins:

| Flag | When |
|---|---|
| `--tags a,b` | The suite is behind build tags. **Check this first** — see below. |
| `--all-mutators` | Thorough pass. Adds the logical, bitwise, loop-control and compound-assignment mutants that gremlins leaves off by default. |
| `--package` | The file's logic is spread across the package, or you want a package-wide picture. |
| `--timeout-coefficient N` | Results are timeout-dominated and the automatic retry didn't fix it. |
| `--max-shown N` | Many survivors; default shows 25 positions per section. |
| `--json PATH` | You want the raw gremlins report for follow-up. |

It runs the package's test suite once per mutant, so expect minutes on a real
package. Tell the user it's running rather than letting it look hung.

**Prerequisite:** the package's tests must pass. The script stops with a clear
message if they don't — a red baseline makes every mutation result meaningless.

**Build tags are the trap.** A package whose test files all sit behind
`//go:build unit` looks *empty*, not broken: `go test` prints `[no test files]`
and exits 0, gremlins gathers empty coverage, and every mutant comes back
unreachable — a clean-looking run that means nothing. The script now detects this
and tells you which tags to pass, but check the repo's own test command
(`Taskfile`, `Makefile`, CI config) for tags before the first run either way.

## Reading the Output

The script sorts findings by the action each one calls for. This distinction is
the whole point — do not collapse them into one list of "problems".

**SURVIVED** — the mutant ran, every test still passed. This is the real finding:
a behaviour the tests execute but do not pin down. Each one is shown with its
source line and a caret on the exact operator that changed.

**UNREACHABLE** (gremlins' `NOT COVERED`) — no test executes the line at all, so
no mutant could be tried. Usually a coverage gap rather than a weak assertion,
and the fix is a test that reaches the branch. Report it separately.

Verify it before you believe it, because this bucket lies in one specific case:
Go's cover tool instruments a `case` *body* (from the colon onward) and never the
`case` *condition*, so any mutation position inside `case <expr>:` falls outside
every coverage block. Gremlins reports those unreachable **whether the case is
exhaustively tested or never tested at all** — the two are indistinguishable from
this output. The script flags how many entries sit on `case` lines; resolve each
by reading the tests, or by checking the block hit-counts in a `-coverprofile`
(a trailing `0` means genuinely never executed). Reporting a well-tested branch
as a coverage gap is worse than saying nothing.

**INCONCLUSIVE** (timed out / not viable) — no verdict. Never present these as
either pass or fail. Gremlins sizes each mutant's timeout from how long the
coverage run took, so a package with a sub-second suite reports everything as
timed out; the script retries once with a large coefficient and tells you when
it did. If timeouts still dominate, say the run was inconclusive rather than
reporting an efficacy number that means nothing.

Efficacy is killed over *decided* mutants. Treat it as a discovery signal, never
as a target — mutation score is trivially gamed by asserting trivia, and 100% is
unreachable in principle because some mutants are semantically equivalent.

## Triage — What To Do With Each Survivor

Read the source line and answer one question: **why didn't a test notice?**
There are exactly three answers, and only one of them means "write a test".

### 1. Unasserted — the test reaches it but checks the wrong thing

The common case. Usually an existing test needs a sharper assertion rather than a
new test alongside it.

A boundary survivor (`>` → `>=`) almost always means no case sits *on* the edge:
the code branches at 100 and the tests only use 200. Add the edge value, not
another arbitrary one.

### 2. Unobservable — no input can distinguish the mutant

The mutant is semantically equivalent, and no test can kill it. This is often a
finding about the **code**, not the tests: a guard that changes nothing, a
redundant branch, dead defensive logic.

Example: in `if total <= 0 { return 0 }` followed by `return total * rate / 100`,
mutating `<=` to `<` survives — with `total == 0` both paths return 0. The guard
is redundant at its own boundary. Say so instead of contriving a test.

Before concluding this, check it properly: name an input that would produce
different output. If you can, it's case 1. Then prove it mechanically — see
[Verify Before You Report](#verify-before-you-report).

**Do not reflexively recommend deleting the redundant code.** Ask what the guard
is holding up first. A bounds check that never fires on today's inputs may be
exactly what makes *other* mutants equivalent — delete it and those boundary
mutations stop being no-ops and start being panics. A guard that is both
unreachable and load-bearing should be reported as untestable and left alone.
Recommend deletion only when you have checked that nothing else leans on it;
either way it is the user's call.

### 3. Not worth pinning — the behaviour is genuinely incidental

Rare, and the weakest answer. Log-only values, debug strings, an arbitrary
tie-break with no contract. Say why it doesn't matter rather than adding a test
that freezes an accident.

**Never** kill a mutant by asserting implementation detail. A test written to
satisfy a mutant, shaped like the code rather than the behaviour, is worse than
the survivor was — it couples the suite to structure and breaks on every
refactor. If the only way to kill it is reaching into internals, that is case 2
or 3, not case 1.

## Verify Before You Report

Triage by reading gets the category right most of the time, which is not the same
as being right. Every claim below is cheap to *prove*, and an unproven mutation
report is just a plausible story about code you skimmed. Prove the ones your
recommendations rest on.

**Guard the file first.** Every technique here edits production code and reverts
it. `git checkout -- FILE` only restores the last commit, so it destroys
uncommitted work — snapshot instead. Use `command cp -f`: a bare `cp` is often
aliased to an interactive one that will hang waiting for a prompt you cannot
answer, and a `>` redirect fails outright under zsh's `noclobber`.

```bash
orig=$(mktemp)
command cp -f path/to/file.go "$orig"
restore() { command cp -f "$orig" path/to/file.go; }
```

**Check the mutation landed before trusting the verdict.** A substitution that
silently didn't apply reads exactly like an equivalent mutant, and a restore that
silently didn't happen makes every later result meaningless because the mutants
accumulate. Both failures produce confident, wrong output. Assert that exactly
one line differs from the snapshot:

```bash
restore
perl -i -pe 'if ($. == 172) { s/&&/||/ }' path/to/file.go
(( $(diff "$orig" path/to/file.go | grep -c '^<') == 1 )) || { echo "edit did not apply"; restore; return; }
```

**To prove a survivor is killable (case 1):** write the candidate test, apply the
mutant, and confirm the suite now fails — then restore and confirm it passes
again. Check too that the *existing* tests alone don't catch the mutant; that is
what shows your new assertion is the thing closing the gap.

```bash
go test -tags unit -count=1 ./internal/lexer/    # must FAIL under the mutant
restore
```

**To prove a mutant is equivalent (case 2):** apply it and run the whole suite.
Surviving the suite it already survived proves nothing, so add pressure — a few
hundred thousand fuzzed inputs through the public entry point, asserting nothing,
just checking that behaviour and the mutant stay indistinguishable:

```go
alphabet := []byte("model {}[],:->\"# \t\n09azAZ_")
rng := rand.New(rand.NewSource(1))
for i := 0; i < 200000; i++ { /* build a random string, call the API */ }
```

**To prove a branch is dead rather than untested:** replace its body with a
`panic` and run the suite plus the fuzz. If it never fires, no input reaches it —
that is the difference between "needs a test" and "cannot be tested", and it is
not a judgement you can make by reading. It is also how you find out whether the
guard is load-bearing before recommending its deletion.

State in the report which findings you verified this way and which are reasoned.
The distinction is what makes the rest of it trustworthy.

## Fixing

When adding or strengthening tests, follow the project's Go testing guidelines
so the fix doesn't introduce a worse problem than it solves:

```bash
cat ~/.config/ai/guidelines/go/testing-patterns.md      # anti-patterns, independent verification
cat ~/.config/ai/guidelines/testing/caller-patterns.md  # what to assert for this component type
```

Also honour the user's Go test organisation rules: one umbrella `Test{TypeName}`,
`t.Run` groups per operation, subtest names that read as sentences about the
observed behaviour, `testify/require` assertions, fresh fixtures per leaf
subtest.

Prefer strengthening an existing assertion over appending a new test. If several
survivors sit in the same function and one sharper assertion kills them all, say
so — one good assertion beats four mutant-shaped tests.

## Reporting Back

Lead with the judgement, not the raw table. The user can read counts themselves;
what they need is which survivors matter.

```markdown
## Mutation Report — `path/to/file.go`

**N survived, N unreachable** of N mutants with a verdict[, N inconclusive].

### Worth fixing
1. `file.go:42` — `>` → `>=` survived. No test sits on the 100 boundary, so an
   off-by-one in the tier threshold would ship. Fix: assert `Tier(100)` in the
   existing `t.Run("silver", ...)` case. [verified: kills the mutant]

### Equivalent — no test can kill these
2. `file.go:4` — `<=` → `<` survived because `total == 0` returns 0 either way.
   The guard is redundant at its own boundary. [verified: survives 200k fuzzed
   inputs]

### Unreachable
3. `file.go:21` — nothing exercises the `spend >= 100` branch. Needs a test case,
   not a stronger assertion.

### Verdict
[One or two sentences: is this suite trustworthy for the refactor at hand?]
```

Then offer to make the changes. Do not apply them unprompted — the triage
judgement is the deliverable, and case 2 findings may mean deleting production
code, which is the user's call.

## When To Reach For This

Good uses: before trusting a suite for a refactor or migration; reviewing a PR
that adds a lot of tests; auditing tests that were written after the code (they
tend to assert what the code does, so they pass by construction); decision-dense
code like pricing, permissions, state machines, retry logic.

Poor uses: as a CI gate with a score threshold; on IO glue or generated code
where mutants are mostly equivalent; chasing a number.

Its structural blind spot: mutation testing can only perturb code that exists,
so it says nothing about behaviour never implemented — a missing validation, an
unhandled error, an input nobody considered. A clean report means the assertions
are sharp, not that the behaviour is complete. Keep designing test cases from
the spec; use this to check the assertions held up.
