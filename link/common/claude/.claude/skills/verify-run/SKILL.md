---
name: verify-run
description: Post-run verification of an autonomous implementation run (implement-flow / implement-auto / implement). Runs the run-verifier agent to catch the failure modes the evidence gate can't see — staged tails, dead code, vacuous receipts, collapsed commits — and, with --fix, remediates them. Use after an unattended run, before trusting its "done".
---

Independently verify what an autonomous run produced — before trusting its result or opening the PR: $ARGUMENTS

Detection lives in the **`run-verifier`** agent (read-only; structured verdict). This skill is the entry point: it runs that agent, presents the verdict, and — only with `--fix` — remediates the mechanical findings. Run it from the **same worktree the run used**.

`$ARGUMENTS` may name the worktree/branch to check (default: the current tree) and/or `--fix`.

Why this exists: these runs close tasks on **executed evidence**, but "a test executed and passed" is neither necessary nor sufficient for "the feature works" — correct work can be left uncommitted (false negatives) and green-but-broken work reported as done (false positives). The agent catches both.

## Run

1. **Spawn the `run-verifier` agent** with a one-line brief naming the worktree/branch to verify (default: the current tree) and whether the run reported all tasks closed. It resolves the run's commits, executes its checks in that worktree, and returns `{ clean, findings, learnings_path }`.

2. **Present the verdict:**
   - **`clean: true`** → one line: `verified · <N> commits on <branch> · no blocking findings`. Surface `learnings_path` if set (it may be out-of-tree and invisible in the diff). Stop.
   - **findings** → list them most-severe first, each with the exact file/symbol/commit and the fix. A `block` (`staged-tail`, `vacuous-receipt`, `dead-code`) means the run's "done" does **not** hold; a `warn` (`commit-boundary`) is cosmetic history.

3. **`--fix` only** (never otherwise — default is advisory): remediate the mechanical findings yourself — finish a staged tail's commit (repo's own conventions, one commit, explicit-path staging), delete confirmed dead code, or re-split a collapsed commit — then re-spawn `run-verifier` to confirm.

## Notes

- **General** across Go / JS-TS / Elixir; the agent carries the per-language recipes. A repo-specific cross-boundary invariant (e.g. an event's SNS→SQS filter wiring, unexecutable locally) does **not** belong here — encode it as a hermetic test in that repo so it runs in CI for everyone.
- **Same agent, three callers.** `implement-flow`'s Finalize spawns `run-verifier` as its integration gate, and `implement` / `implement-auto` can run it post-run — so the `/verify-run` command and the automated gates verify identically.
- **Defense in depth.** The checks overlap the workflow's own receipts on purpose. As the evidence contract absorbs one (worktree-pinned receipts, per-file staging, reachability in the audit), the agent's matching finding goes quiet — the signal it's safe to retire it.
