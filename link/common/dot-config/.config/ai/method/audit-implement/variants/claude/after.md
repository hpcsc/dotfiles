## After it returns

1. **Read `coverage_gaps` first.** An audit's blind spots are more actionable than its hits: they tell you what you still have to check yourself.
2. **Work `findings` in order.** Each carries evidence. A `confirmed` runtime finding has a command and output you can re-run; a `confirmed` quality finding has a rule and a line.
3. **Skim `refuted`.** A wrongly-refuted finding is the failure mode of this shape. If one looks right to you, it probably is — the verifier is instructed to default to refuting when uncertain.
4. **Fix directly.** Do not delegate the fixes; you have the context and they are usually small. To confirm they landed, run another round with `--recheck` naming every finding, `decision: fixed` or `decision: declined` with your reason (a declined one is settled and any re-raise is dropped), and `--fixed-file` set to the paths you touched: the panel keeps every lens that owns one of them and names the rest in `lenses_not_run`. Narrow harder with `--lens` only when every fix was a quality fix, which cannot break what another lens owns.
5. **Persist what generalises.** A finding that names a repeatable mistake belongs in the repo's learnings file (`tasks/learnings.md`, or the out-of-tree per-project store when the repo gitignores `tasks/`) so the next run — of anything — inherits it.
