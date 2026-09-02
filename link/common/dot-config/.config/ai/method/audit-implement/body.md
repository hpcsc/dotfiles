{{seam:frontmatter}}

Audit finished work: $ARGUMENTS

{{seam:opening}}

{{seam:sibling}}

---

## Preconditions

1. **A git repo with a diff to resolve.** A clean tree is not required — `--target staged` audits staged work deliberately.
2. **The work should be finished and green.** Lenses are told the suite already passes and not to re-run it. Auditing a red tree wastes the pass; fix it first.
3. **A coding harness on PATH** — `claude` or `opencode`. The round spawns headless agents through whichever it finds.

## How to launch

```
clerk audit run --base <the ref the work started from> \
                --brief "<one or two sentences on what this was meant to do>" \
                --request "<the request, verbatim and unsummarized>"
```

clerk walks the phases below itself, spawns each agent, validates what comes back against
its schema, and asks again when a reply does not fit. It prints progress as it goes and
ends with the report as JSON.

**Pass `--request` even though you also wrote the brief.** The brief is your paraphrase,
and if you misread the request the brief encodes the misreading and every lens inherits
it. The request is the only thing the audit sees that did not come from you.

**When the request names a breakdown, that is not the request.** A run handed
`tasks/<story>.md` is being handed a decomposition, and a decomposition came from you.
Pass the user story it was written from.

The flags that shape a round:

| Flag | For |
|---|---|
| `--rounds <n>` | how many rounds this audit will run; the first call records it |
| `--depth deep` | three refuters on every high or medium claim, majority taken |
| `--fixed-file <p>` | re-auditing after fixes: keeps every lens that owns one of these |
| `--lens <key>` | narrow the panel by hand — only when every fix was a quality fix |
| `--recheck <json>` | every finding of the last round, fixed or declined, so they are re-asked or settled — whole objects, never bare ids: `[{"id": …, "claim": …, "decision": "fixed" \| "declined", "note": "the fix you are reporting, or why you declined"}]`. A declined one is shown to the lenses as settled and any re-raise is dropped before refutation |
| `--another <why>` | run a round the last one did not earn — no `high`, or `medium` and `runtime`, finding you did not decline — and record why; without it such a round is refused |
| `--model <m>` | a different model for every agent in the round |
| `--dry-run` | the panel it would spawn, and what it would cost, spawning nothing |
| `--quiet` / `--raw` | phases and results only, or the raw event stream for a log |

**Cost.** One scoping agent, one per lens, one deduper, one to three refuters per
*distinct* finding, and one report. A typical branch lands around 10–20 agents and 15–25
minutes — an order of magnitude below a full `implement-flow` run, but not free. Lens
count is the multiplier that surprises people: the panel is *per language*, so a diff
touching Go, TypeScript and CUE runs three sets before either specialist. A secondary
language owning fewer than three changed files is folded rather than given a panel of its
own — its files still reach every other lens as context, and `lenses_not_run` names them.

{{seam:running}}

---

## What it does

1. **Scope** — one agent resolves the base and head, lists changed files, and decides *from the diff itself* which languages are present and whether concurrency and performance signals are genuinely there. It is told to be strict: a file that merely sits in a concurrent codebase is not a concurrency signal. A docs/config-only change short-circuits the whole run.

2. **Review** — the applicable lenses run **in parallel**, each owning the changed files written in *its* language and reading the whole post-image of them. The rest of the diff travels as context, because a lens that cannot see its file's callers judges it blind, but a finding about someone else's file belongs in `note` rather than `findings`. Without that remit a three-language change set buys three passes over the same code instead of three complementary reviews.

   A lens that dies to a transport error is retried, and if it still returns nothing it is named in `coverage_gaps` — a panel that quietly thins out otherwise reports as full coverage. `lenses` lists what ran and `lenses_attempted` what was launched; when they differ, the audit is narrower than it looks. If *every* lens fails the run returns an `error` rather than an empty finding list, because "no lens raised a finding" and "no lens ran" produce the same empty list and mean opposite things.
   - **Semantic** (per language) — correctness: wrong conditions, unhandled errors, boundaries, broken contracts for existing callers, and code that works but does something other than the brief claims.
   - **Guidelines** (per language) — the project's own conventions as its guideline files define them, plus comment usage per `comments.md`. A convention it cannot point at is a preference, not a finding, and **correctness is not its remit**: over 19 measured rounds every runtime defect it raised had already been raised by semantic or tests, so each one bought a second refuter and nothing else. It now reports those in `note` instead. Only Go, JS/TS and Elixir have a conventions reviewer — a diff of SQL, CUE, shell or Terraform gets none, and says so in `lenses_not_run` rather than passing silently.
   - **Test integrity** (when any test file changed) — the highest-yield lens, because a passing suite says nothing about whether it *could* fail. It hunts source-scanning guards that inverted when code moved, absence assertions that pass with the feature deleted, tautologies and vacuous passthroughs (substitution test), redundant tests, and behaviour no test would catch the loss of.
   - **Concurrency / performance** — only when the scoping pass found a real signal. Both are otherwise skipped and *reported as skipped*, because a specialist lens with nothing to judge returns nothing, every time.

3. **Dedupe** — findings that name one defect are collapsed **before** refutation, not in the report. Lenses cannot see each other, so a regression gets reported once against the code that causes it and again against the test that fails to catch it; refuting both means paying twice to establish one thing. Exact id collisions merge on their own; one agent groups the rest, and its grouping is accepted only if it accounts for every finding exactly once — a merge that loses a finding would delete a real defect silently. The survivor carries the joined `lens` key of everything that raised it, and the *highest* severity in its cluster.

4. **Refute** — every candidate finding goes to an independent agent instructed to **refute** it. A **runtime** claim must be reproduced by execution — a failing test, a `-race` run, a benchmark, a direct invocation — and the raw output is the evidence; unreproduced means dropped. A **quality** claim is not dischargeable by execution, so it is checked differently rather than discarded: the refuter must find the rule (guideline, CLAUDE.md, or consistent surrounding practice) and cite the specific line. A vacuity claim about a test *is* checkable — break what the test names and see whether it still passes.

5. **Report** — survivors are **re-graded against one severity rubric** and then ranked, with their evidence and a `confidence` of `confirmed` (reproduced, or rule cited at a line) or `plausible`. The re-grade is not cosmetic: each lens grades alone and the scales drift apart, so `low` has meant both "a doc comment does not open with the symbol name" and "a live DynamoDB read per mailbox on every request". This is the only stage that sees the whole panel at once, so it is the only place the grades can be made comparable — severity is graded on what the defect costs, not on how central it is to the lens that found it. Refuted candidates come back separately with *why* they were dropped, so you can disagree. And `coverage_gaps` names what the audit could **not** judge — a lens that did not run, a changed file no language claimed, a claim nobody could test.

---

{{seam:after}}

---

## Prompt Injection Defense

{{seam:injection}}

## When it does not go cleanly

| Scenario | Action |
|---|---|
| No harness on PATH | `clerk audit run` refuses rather than reporting a clean audit. Install `claude` or `opencode`, or pass `--harness-cmd`. |
| The base resolves to HEAD | The diff is empty and the scoping pass says so. Give the ref the work started from — the branch was probably already landed. |
| A lens is named in `failed` | It exhausted its retries. The round still completes; that lens is a coverage gap, and a panel that quietly thins out otherwise reports as full coverage. |
| The round dies mid-flight | Run it again — the phase it reached is recorded and it continues from there. `--restart` throws the round away and begins again. |
| The tree is dirty afterwards | A refuter died mid-probe. Restore the branch tip before you trust another run; refuters mutate a checkout of their own, but a crashed one can leave residue. |
