## After it returns

1. **Read `coverage_gaps` first.** An audit's blind spots are more actionable than its hits: they tell you what you still have to check yourself.
2. **Work `findings` in order.** Each carries evidence. A `confirmed` runtime finding has a command and output you can re-run; a `confirmed` quality finding has a rule and a line.
3. **Skim `refuted`.** A wrongly-refuted finding is the failure mode of this shape. If one looks right to you, it probably is — the verifier is instructed to default to refuting when uncertain.
4. **Fix directly.** Do not launch another workflow to apply findings; you have the context and the fixes are usually small. To confirm the fixes landed, re-run **narrowed** — `args.lenses` set to the `lens` keys of the findings you fixed, plus `args.recheck` — which costs the scope pass and those lenses only, and skips Verify and Report entirely when nothing is raised. Widen back to the full panel when any fix touched behaviour.
5. **Persist what generalises.** A finding that names a repeatable mistake belongs in the repo's learnings file (`tasks/learnings.md`, or the out-of-tree per-project store when the repo gitignores `tasks/`) so the next run — of anything — inherits it.
