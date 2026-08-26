## Phase 1: Run the lenses

Spawn these via the `task` tool. **If your runtime can run several tasks concurrently, spawn them in one message** — they are independent and read-only. If it cannot, run them in sequence; the audit is still correct, just slower.

| Lens | Agent | Run when |
|---|---|---|
| Correctness | `go-semantic-reviewer` / `js-semantic-reviewer` / `elixir-semantic-reviewer` / `semantic-reviewer` | always |
| Conventions | `go-guidelines-reviewer` / `js-guidelines-reviewer` / `elixir-guidelines-reviewer` | language has one |
| Test integrity | `go-test-reviewer` / `js-test-reviewer` / `test-reviewer` | any test file changed |
| Concurrency | `<lang>-concurrency-reviewer` / `concurrency-reviewer` | signal is true |
| Performance | `<lang>-performance-reviewer` / `performance-reviewer` | signal is true |

Run one set per language present in the diff.

**Only Go, JS/TS and Elixir have a conventions reviewer.** A diff of SQL, CUE, shell or Terraform therefore gets no conventions pass at all — name that in the coverage gaps every time it happens. "Language has one" is a condition the reader cannot see the other half of, and a lens that quietly does not run is indistinguishable from one that found nothing.

**Give each lens a remit, not the whole diff.** Group the changed files by the language each is *written in* — a `.go` file is Go even when it implements a JavaScript-facing feature, and "generic" means written in something with no lens of its own (CUE, SQL, a grammar corpus), never "everything left over". A lens reviews the files under its own language and raises findings only about those. Without this a three-language change set buys three passes over the same code rather than three complementary reviews, and the copies all get verified separately.

A changed file that lands under no language — prose documentation, a lockfile — is owned by nobody. That is usually right, but say so in the coverage gaps rather than letting the change set read as fully reviewed.

**Every lens prompt must be self-contained** and carry: the change-set summary, the exact diff command, its own remit, the rest of the changed files marked as context, and this shared preamble —

{{quote:audit-implement/prompts/review-open.md}}
>
{{quote:audit-implement/prompts/review-rules.md}}

**When `clerk lint` ran**, add what it covers so no lens pays to re-derive a rule a regex already settled — and hand the two Go rules over with their limits named, since the checker matches lines rather than declarations:

{{quote:audit-implement/prompts/mechanical.md}}
>
{{quote:audit-implement/prompts/mechanical-tail.md}}

Omit this block entirely when the checker did not run. A lens told to stand down on a check that never happened leaves the rule enforced by nobody.
**Every lens also carries the finding contract**, which is where severity is defined — one rubric for the whole panel, because grades made inside a single lens do not compare across them:

{{quote:audit-implement/prompts/finding-contract.md}}

**The correctness lens gets more**, because scope breaches and narrowed contracts are invisible to a diff — code delivering a declared non-goal looks like extra work rather than the breach it is:

{{quote:audit-implement/prompts/lens-semantic.md}}

**The conventions lens gets a boundary**, because without one it drifts into correctness and duplicates the lens already reading the same diff. Measured over 19 audit rounds, every runtime defect the conventions lens raised had already been raised by correctness or test integrity — each one bought a second verifier and no new information:

{{quote:audit-implement/prompts/lens-guidelines.md}}

**The test-integrity lens gets more**, because it is the highest-yield one — a suite that passes tells you nothing about whether it *could* fail:

{{quote:audit-implement/prompts/lens-tests.md}}

---

## Phase 2: Collapse duplicates before you pay to verify them

You hold every lens's findings, so do this yourself — it is reading and judgment, not a subagent's job.

{{include:audit-implement/prompts/dedupe-rules.md}}

Merging rules: keep the **highest** severity in the cluster (never the representative's alone), prefer the `runtime` report as the survivor when the cluster mixes natures, since it carries the reproduction, and record every lens that raised it. Verify the survivor once.

---

## Phase 3: Verify every claim

Nothing reaches the report unverified. Spawn one verifier per **distinct** finding (again, concurrently if your runtime allows). Use the language's semantic reviewer, or `general` — the verifier's job is execution and rule-checking, not taste.

{{quote:audit-implement/prompts/verify-open.md}}
>
{{quote:audit-implement/prompts/verify-file-rule.md}}

**For a `runtime` claim** — try to *refute* it by execution:

{{quote:audit-implement/prompts/verify-runtime.md}}

**For a `quality` claim** — there is nothing to execute, so check it rather than discarding it:

{{quote:audit-implement/prompts/verify-quality.md}}

---

## Phase 4: Report it yourself

You hold every finding and verdict — no synthesis agent needed.

1. **Drop the refuted**, but list them separately with *why*, so the caller can disagree.
2. **Re-grade severity across the whole set, then rank** most severe first. You are the only stage holding every finding at once, so this is the only place the grades can be made comparable:

{{include:audit-implement/prompts/regrade.md}}

   Then mark each `confirmed` (reproduced by execution, or a rule cited at a specific line) or `plausible`. They are already deduplicated; do not merge further here, or you discard one verifier's evidence for a claim that was judged on its own.
3. **State the coverage gaps** — the lenses that did not run and why, a changed file no language claimed, a claim nobody could test. Be concrete: "nothing was missed" is almost never true and is not a useful answer.
4. **Confirm the tree is clean**: `git status --porcelain`. Verifiers write scratch files to prove things; if any survived, say so and remove them. The audit must not leave the repo dirtier than it found it.

Do not invent findings to pad the report. A clean audit is a real outcome, and saying so plainly beats manufacturing nits.
