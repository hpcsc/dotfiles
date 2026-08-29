## Preconditions

1. **Git repo.** The audit resolves a diff; there must be one. A clean tree is *not* required — `target: "staged"` audits staged work deliberately.
2. **The work should be finished and green.** Lenses are told the suite already passes and not to re-run it. Auditing a red tree wastes the pass; fix it first.
3. **Resolve the test commands** the same way the implement-* skills do — the repo's own `tasks/test-commands.json` at the **main repo root** (not the cwd, which differs inside a worktree):
   ```
   root=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
   cat "$root/tasks/test-commands.json" 2>/dev/null
   ```
   Pass the parsed object as `args.testCommands`. Verifiers use the entry for the diff's primary language when they need to run something. Absent the file, pass a single detected `args.testCommand`.
4. **Confirm the cost.** This is a `Workflow` and needs the same explicit opt-in: 1 scoping agent + one per lens + 1 deduper + 1–3 verifiers per *distinct* finding + 1 report. A typical branch lands around 10–20 agents and 15–25 minutes wall-clock — an order of magnitude below a full `implement-flow` run, but not free. Lens count is the multiplier that surprises people: the panel is *per language*, so a diff touching Go, TypeScript and CUE runs three sets before either specialist. A secondary language owning fewer than three changed files is folded rather than given a panel of its own — its files still reach every other lens as context, and `lenses_not_run` names them so you can read them yourself. The primary language always gets its panel, however little it owns. Verification is the half that scales with findings rather than files, which is why duplicates are collapsed before it.

---

## How to launch

```
echo "$HOME/.claude/skills/audit-implement/audit-implement.workflow.js"   # -> use this absolute literal as scriptPath
```

```
Workflow({
  scriptPath: "<resolved absolute path from the echo above>",
  args: {
    target: "branch",
    testCommands: { ... },
    brief: "<what you were trying to build, in a sentence — optional>",
    request: "<the original request, verbatim — optional but worth more than the brief>",
    depth: "standard"
  }
})
```

- `args.target` — `"branch"` (default: this branch's own commits, base resolved via merge-base with `main`/`master`), `"staged"` (the staged changes), or a ref range / path filter you describe.
- `args.baseRef` — override the resolved base for `target: "branch"`.
- `args.brief` — one sentence on what the change set was *meant* to do. Cheap and worth it: correctness findings sharpen when a lens can compare the code against its intent rather than inferring intent from the code.
- `args.request` — the original request **verbatim**, unsummarized. Worth more than the brief, because the brief is *your* paraphrase: if you misread the request, the brief encodes the misreading and every lens downstream inherits it. With the request present, the correctness lens is told to raise a second class of finding — code that satisfies the change set's own summary while substituting a proxy for what was actually asked. Without it, every lens judges intent from the diff, which is judging the code against itself. Pass both: the brief compresses, the request is the ground truth.
- `args.lenses` — restrict the Review phase to named lenses, for **re-auditing after fixes** instead of paying for a whole pass. Keys are `semantic:<Lang>`, `guidelines:<Lang>`, `tests:<Lang>`, `concurrency`, `performance`; every returned finding carries the `lens` that raised it, so you feed those keys straight back. Held-back lenses are reported in `coverage_gaps` — a narrowed run must never read as full coverage — and if none of the named lenses is in this diff's recomputed panel, the **full panel runs instead**: the panel is derived from the current scope, so a lens can legitimately drop out (`tests:Go` goes once no test file changes), and narrowing to nothing would return a clean audit nobody performed.

  **Only narrow when the fixes could not have changed behaviour** — a comment removed, a redundant test folded, a name changed. A fix that touches a code path can break something a *different* lens owns, and the lens that raised the original finding is not watching for it. Same rule `implement-flow` applies when it narrows its per-task review panel.
- `args.fixedFiles` — the paths this round's fixes touched, on a re-audit only. Each language panel runs when it owns one of them and is held back, by name, in `lenses_not_run` when it does not; concurrency and performance read the whole diff and always run. Nothing narrows when the fixes reach every language, when `args.lenses` names the panel outright, or when no language owns any fixed file — a round that reviewed nothing must not come back reading like one that reviewed everything.
- `args.recheck` — `[{ id, claim, note }]` for the findings you just fixed. The lens is told what was claimed and checks whether it landed, re-raising with the same `id` if not. It keeps its full remit over the diff: a fix can introduce a fresh defect, and a lens restricted to old ids would be blind to exactly that.
- `args.depth` — `"standard"` (one verifier per finding, the default) or `"deep"` (three independent verifiers, majority vote, on the `high` and `medium` findings only). Use `deep` before something irreversible. It does not deepen `low` findings at any setting: verification is the single largest cost in an audit, and low-severity claims are most of what a panel raises.
- `args.testCommands` / `args.testCommand` — as in Preconditions §3.

Runs in the background; you are notified on completion. Do not poll it.
