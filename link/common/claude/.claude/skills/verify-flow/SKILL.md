---
name: verify-flow
description: Post-run verification of an autonomous implementation run (implement-flow / implement-auto). Independently re-checks, in the worktree, the failure modes the evidence gate cannot see — staged-but-uncommitted tails, vacuous test receipts, dead code with no live caller, collapsed commits — and surfaces the run's learnings. Use after an unattended run, before trusting its "done".
---

Independently verify what an autonomous implementation run (`implement-flow`, `implement-auto`) actually produced — before you trust its result or open the PR: $ARGUMENTS

These runs close tasks on **executed evidence**, but "a test executed and passed" is neither necessary nor sufficient for "the feature works". This skill runs the checklist that catches the gaps: correct work left uncommitted (false negatives), and green-but-broken work reported as done (false positives). It is **general** — no repo-specific assumptions. Run it from the **same worktree the run used**.

`$ARGUMENTS` may name the worktree/branch to check (default: the current tree) and/or `--fix` to remediate the mechanical findings (otherwise advisory-only — it reports, you act).

---

## Before you start

Locate the run's commits and confirm you're in the right tree — do NOT assume the main checkout, which may be on another branch:

```
git rev-parse --show-toplevel                 # the tree you're verifying — must be where the run committed
DEFAULT=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's#^origin/##'); : "${DEFAULT:=$(git branch --list main master | head -1 | tr -d ' *')}"
BASE=$(git merge-base HEAD "$DEFAULT")
git log --oneline "$BASE"..HEAD               # the commits this run produced
git diff --stat "$BASE"..HEAD                  # the run's net change
```

Everything below is scoped to `$BASE..HEAD` and this worktree.

---

## The checks

### 1. Unfinished / staged-but-uncommitted tail
`git status --porcelain`. When a task can't close, the run **stops the chain and leaves that task's edits STAGED** (`M `/`A ` in column 1) — a plain `git diff` looks empty. Any staged or dirty entry means an open task a later task likely depended on.
- `git diff --staged --stat` to see it; report it as an **unfinished task**, not a stray edit.
- If `--fix`: read `git diff --staged`, close the concrete gap named in the run's `unresolved` list / `tasks/*.md`, then commit it with the repo's own conventions (one commit, its own trailer). Never `git add -A`.

### 2. Honest re-run in the worktree
Re-execute the project's test command **here**, and build the changed code — the run's own "full-suite" receipt can be vacuous (run in the wrong tree, or a change-scoped runner that skipped everything).
- Run the test command for the changed packages/modules. If a change-scoped runner prints something like *"no files changed, skip"*, that receipt proved **nothing** — run the affected packages explicitly.
- Build the changed services/packages (`go build ./<svc>/...`, the project build, `tsc`, etc.). A build catches missed callers of a removed/renamed symbol that a change-scoped test never compiles.
- Report the **real** receipts (command + output tail + pass/fail). A green claim you didn't reproduce here doesn't count.

### 3. Reachability — dead code / missing integration seam
The sharpest false-positive: a new capability is defined and unit-tested **in isolation** but never called from the live path, while the old path's test still passes — so every test is green and the run reports done, yet production behavior is unchanged.

For each **new exported/public symbol** introduced in `$BASE..HEAD`, confirm it has a caller on the production path:
```
git diff "$BASE"..HEAD | rg '^\+' | rg -o '<language symbol pattern>'   # collect new public symbols
rg -n --glob '!*_test.*' --glob '!*.test.*' -w '<symbol>'               # callers OUTSIDE test files
```
- Go: exported `func`/method/`type`/const (capitalized). JS/TS: `export`ed symbol. Elixir: public `def`.
- A symbol referenced **only from its own test file** (or nowhere) on the live path is likely **dead code** — flag the specific symbol and the handler/entry point that was supposed to call it, and read that caller to confirm it actually delegates.
- **Heuristic caveat:** a new symbol can be legitimately uncalled because a *later, not-yet-implemented* task will call it (an open-task run — see check 1), or it's invoked via a route table / DI container / registration / reflection. Report as **"verify reachability"**, not "definitely dead" — but for a run that claims **all tasks closed**, an uncalled new public symbol is a real red flag, not noise.

### 4. Commit boundaries
`git show --stat <hash>` for each run commit. Flag:
- a commit touching files **unrelated** to its subject (sign of `git add -A` sweeping, or a flaky pre-commit hook collapsing two tasks into one commit under the wrong message),
- a task whose files landed in a **different** task's commit.
Nothing is lost when commits collapse — the files are all present — but the boundaries and messages are wrong; note it so the PR history is honest (or offer to re-split with `--fix`).

### 5. Surface the run's learnings and breakdown
The run writes `tasks/learnings.md` (left uncommitted by design) and the `tasks/*.md` breakdown. In repos where `tasks/` is **gitignored**, these never appear in `git status`/diff/PR — so read them **directly** and surface their contents; don't rely on the diff to reveal them.
```
[ -f tasks/learnings.md ] && cat tasks/learnings.md
git check-ignore tasks/learnings.md >/dev/null && echo "(gitignored — invisible in the PR; surface it manually)"
```

---

## Report

Emit a compact verdict:
- **PASS** — all checks clear; the run's "done" holds. Or,
- a **findings list**, most-severe first, each with: the check, the exact file/symbol/commit, and the concrete remedy. Order by risk: a false-positive (dead code, vacuous receipt — check 2/3) ships a silent bug and outranks a false-negative (staged tail — check 1) or a cosmetic one (commit boundaries — check 4).

Advisory by default — do not edit the tree. With `--fix`, remediate the mechanical findings (finish a staged tail's commit, delete confirmed dead code, re-split collapsed commits), each with the repo's own commit conventions, and re-run the affected checks to confirm.

---

## Notes

- **Generality:** works across Go / JS-TS / Elixir with no repo-specific knowledge. A repo-specific cross-boundary invariant — e.g. an event's SNS→SQS subscription-filter wiring, which no local command can execute end-to-end — does **not** belong here; encode it as a hermetic test checked into that repo, so it runs in CI for everyone, not only after an autonomous run.
- **Defense in depth:** some checks overlap the workflow's own receipts on purpose. As the evidence contract tightens (worktree-pinned receipts, per-file staging, reachability in the audit), the corresponding check here goes quiet — that's the signal it's safe to stop running it. Until then, an independent re-execution is the ground truth.
