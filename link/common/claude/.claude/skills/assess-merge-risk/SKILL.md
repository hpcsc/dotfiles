---
name: assess-merge-risk
description: Assess a GitHub PR as a merge decision rather than a code review — how reversible it is (two-way door or one-way), what its blast radius is if it is wrong, how loudly and how quickly that would surface, and what would have to change to make it safe to merge. Use when deciding whether to merge or sign off, and when asked "can we undo this", "is this a one-way door", "what's the blast radius", "how risky is this to merge", or before shipping anything touching money, customer comms, migrations, public contracts, or shared infrastructure.
argument-hint: <PR number | #N | owner/repo#N | GitHub URL | --branch> [--depth quick|standard|deep] [--measure] [--full] [--share] [--post]
---

# Assess a PR as a merge decision

Two questions, in this order:

1. **Reversibility** — if we don't like this later, what does it cost to walk back?
2. **Blast radius** — if it is wrong, what and who does it reach before anyone notices?

Then one output: a **verdict with merge conditions** — the smallest set of changes
that would make merging boring.

This is not a defect hunt. A correctness review asks *is this code right*; this
skill assumes it might not be and prices being wrong. Run a correctness review too
(`/code-review`, the project's `/pr-review`, or `/pr-digest` when the PR is large or
unfamiliar) — this one deliberately does not duplicate them, and it never approves
or merges anything.

## The principle to reason from

> `git revert` is always available. Reversibility is about **what the change has
> left behind by the time you reach for it.**

Which gives the one number that matters more than any severity label:

> **irreversible residue ≈ effect rate × time to detect**

A change that reverts in one deploy but sends the wrong SMS to 40,000 customers at
500/min for the six hours before anyone looks is a one-way door in every way that
matters. Reversibility of *code* is not reversibility of *what the code did while it
ran*. Always price both.

Second-order rule: **reversibility decays.** A door that is two-way on merge day
closes as data accumulates in the new shape and consumers start depending on it. Say
*when* it closes, not just whether it is open.

## Inputs

Parse `$ARGUMENTS`:

- **PR ref** — bare number, `#N`, `owner/repo#N`, or a PR URL.
- `--branch` (or no ref at all) — assess the current local branch against the
  default branch, before the PR exists. Same analysis, no PR metadata.
- `--depth quick|standard|deep` (default `standard`) — see *Scaling*.
- `--measure` — put real numbers on traffic and population using the repo's own
  data tooling. Costs time and may need cloud auth; off by default.
- `--full` — run the secondary lenses in *Step 7* and print the long-form memo
  instead of the glance block. Without it, the long form is still written to the file.
- `--share` — publish the memo as an HTML artifact.
- `--post` — post the memo to the PR as a single comment. **Off by default**, only
  honour it if passed on this invocation, and show the exact text and get explicit
  confirmation first.

Requires `gh` (authenticated), `jq`, `python3`, `git`.

## Subagents

Every fan-out here is a plain unnamed background subagent. Never pass `name` and
never use `SendMessage` — a named agent becomes an addressable teammate with a tmux
pane the user has to close by hand, and its final text does not surface on its own.
Put everything an agent needs in its opening prompt: the worktree path, the base
SHA, the signals file, what is already established and must not be re-derived. If an
agent returns nothing usable, do that lens inline and say so in the memo.

## Step 0 — Acquire and scan

```bash
bash ~/.claude/skills/assess-merge-risk/scripts/pr_fetch.sh <pr-ref>      # or: --branch
python3 ~/.claude/skills/assess-merge-risk/scripts/scan_signals.py <outdir>
```

`pr_fetch.sh` prints `repo`, `number`, `outdir` and a metadata summary, and writes
`diff.patch` (combined `base...head`, the one with correct line numbers),
`commits.patch`, `meta.json` and the existing comments. In `--branch` mode it exits 3
when HEAD is at the merge base — there is nothing to assess.

`scan_signals.py` writes `signals.json` and prints a table of durability and
blast-radius leads, plus the mitigations it can see (flags, idempotency guards,
dry-runs, alarms) and whether tests moved with the core files. It grades only
production files — a `DROP TABLE` in a fixture is not an effect.

**The scanner generates leads, not verdicts.** Confirm every hit by reading the
code — a `DROP COLUMN` in a comment is not a dropped column. And absence proves
nothing: it only knows the patterns it ships with, so never report "no irreversible
changes found" on the strength of a clean scan.

Report the surface to the user in one line before analysing anything — *"31 files,
9 carry runtime behaviour, 4 touch shared code, 1 migration, highest durability
signal D5"*. On a big PR that single line is what makes the rest tractable.

**Repo conventions.** If the repo has `.claude/skills/pr-review/guides/`, read
`_common.md` plus any guide matching the changed paths (`routes.yaml` maps them);
they encode local durability rules — which store is append-only, which queues are
at-least-once, which files are contracts. Project rules win over the generic ladder.

## Step 1 — Enumerate the effects

Write one sentence: **what changes for a running system when this merges.** If you
can't, you don't understand the PR yet — read the code, or run `/pr-digest` first
and come back with its brief.

Then list the **effects**. An effect is any place the change writes state, emits an
event or message, calls out of the process, changes a response, or alters what gets
deployed. Effects are the unit of analysis for both questions: reversibility grades
each one, blast radius sizes each one's audience.

Include effects of *deploying*, not just of the code — migrations that run on
deploy, `terraform apply` replacements, one-shot backfills, cron registration,
consumer/queue changes, config and secret rotation. These are the effects that most
often turn a "small PR" into a one-way door, and they are invisible if you only read
the Go/TypeScript.

## Step 2 — Reversibility

Read `~/.config/ai/guidelines/change-risk/reversibility-ladder.md`. Grade every effect on the D0–D5
durability ladder. **The PR's verdict is the worst rung any effect reaches**, noted
with how many effects sit there — one D5 in a pile of D0s is still a D5 PR.

Produce four things — these go in the saved memo; the glance block carries only the
verdict and, when the door closes on something specific, the horizon:

1. **Verdict** — `two-way` (revert restores the prior world), `two-way with cleanup`
   (code reverts, residue stays — name the cleanup and its cost), or `one-way` (some
   effect cannot be recalled at any price, only compensated).
2. **Undo procedure** — the cheapest real path back, as ordered steps with a
   time-to-undo estimate each: flag flip (seconds) → revert + deploy (one pipeline)
   → revert + backfill/repair (hours–days, needs a written plan) → compensate
   (apology, refund, correction — not undo). State which step this PR actually needs.
3. **What a revert does NOT undo** — the residue list. This is the section people
   actually need and the one every other tool omits.
4. **When the door closes** — the forward-only hazards: data accumulating in the new
   shape, a consumer starting to depend on a new field, a name leaking into
   dashboards or client-facing contracts. Give the horizon ("two-way until the first
   client integrates, ~weeks").

## Step 3 — Blast radius

Read `~/.config/ai/guidelines/change-risk/blast-radius.md` and run all six lenses: code fan-out,
deploy surface, traffic and population, failure mode and loudness, detection and
time-to-detect, coupling and partial-deploy states.

Quantify what you can, and **give every number a basis** — measured, derived from
code (an ungated path is 100% of traffic, and that is a derivation, not a guess), or
estimated. Label which. With `--measure`, get real volumes from the repo's own
tooling (project skills such as `datalake-query`, `lambda-logs`, `queue-health`, or
CloudWatch directly). Never invent a traffic number; an unmeasured radius is stated
as a range with its basis.

Size the radius as **exposed population × exposure window**, not as a t-shirt label
alone. "All customers" for a path that runs nightly is a different animal from "all
customers" on a synchronous request path.

## Step 4 — Failure modes

The top three ways this goes wrong in production. Work each one out in full —
**trigger → symptom → who feels it → loudness (fail-closed and visible, or fail-open
and silent) → detection and expected time-to-detect → durability rung** — and save
that. Each becomes **one line** in the glance block's `Watch` list.

Rank by *irreversibility × population*, not by likelihood — likelihood is what the
correctness review is for, and ranking by it here just reproduces that review. The
quadrant to escalate on is **silent and irreversible**: nothing throws, nothing
alarms, and the residue accumulates the whole time.

If a failure mode has no detection at all, it goes first in `Watch` and keeps the `!`
marker regardless of likelihood — no detection is the finding.

## Step 5 — Skeptic pass

Before writing the verdict, spawn independent unnamed agents to attack it from both
sides, each with the effects list, the signals file and the draft verdict:

- *"Argue this is MORE reversible / smaller than claimed. Find the guard, the flag,
  the gate, the existing alarm, the impossible input that makes this fear unfounded."*
- *"Argue this is LESS reversible / bigger than claimed. Find the caller outside the
  diff, the replay path, the consumer, the deploy-time effect that was missed."*

Keep what survives. Where they genuinely disagree, **report the disagreement** — do
not average two positions into a mushy middle. Overstated risk burns credibility as
fast as understated risk, and a memo nobody believes changes no decisions.

At `deep`, run three per side and drop anything a majority refutes.

## Step 6 — Verdict and merge conditions

Everything so far was analysis. What you print is a **glance block**: the reader gets
a merge/hold answer in line two and the whole picture in under twenty lines. Read
`~/.config/ai/guidelines/change-risk/risk-memo-template.md` for the exact shape and
the line budget.

The header carries the PR alone. The **verdict is the first body row**, and it must
read as a complete answer without the reader going anywhere else:

- 🟢 `SAFE TO MERGE — nothing blocking` — two-way or two-way-with-trivial-cleanup,
  bounded radius, nothing required first. Drop the `Before merge` row entirely; the
  verdict has already said it.
- 🟡 `MERGE AFTER <gate>` — safe once that gate holds. **Name the gate in the verdict
  row** — `MERGE AFTER 6817 is merged and deployed` — never a bare `MERGE WHEN`,
  which poses a question the row exists to answer. One connector, `AFTER`, always.
- 🔴 `HOLD — <why>` — one-way, or a silent failure mode with no detection and a live
  population.

Then the **merge conditions**: the smallest set of changes that moves the verdict one
notch safer, one line each, each naming what it buys — which rung it lowers, or how
much detection time it cuts. Prefer **making the door two-way** over promising to be
careful: a flag, a client/region allowlist, a shadow run, an expand-contract split, a
backfill dry-run, an alarm added before merge. *Careful is not a control.*

`Before merge` appears only when there is something to do, and it carries the
evidence behind the gate rather than restating it. Add a `Before <event>` line only
when the door closes on something specific — a UI PR, a client integration, a
backfill.

Most PRs are two-way doors with a small radius, and their glance block is eight
lines. Spend lines only where the risk is: a block that flags everything gets skimmed
on the PR where it mattered.

## Step 7 — Secondary lenses (`--full`)

One line each in the saved memo; a clean lens gets a clean line, and a lens you did
not check is marked "not checked" rather than dropped. These reach the glance block
only when one of them changes the verdict:

- **Security & authz** — new endpoint, new IAM grant, new secret, widened permission.
- **Data & compliance** — new PII fields, retention, residency, regulated decisions.
- **Cost** — new LLM calls, per-message cost, storage, egress, a new always-on resource.
- **Performance & capacity** — new work on a hot path, N+1, concurrency and timeout limits.
- **Dependencies** — version bumps, transitive risk, lockfile churn.
- **Reviewer routing** — who owns the blast radius and must be in the review.
- **Timing** — freeze windows, peak billing or campaign periods, adjacent in-flight
  PRs on the same files, whether this lands when the people who could undo it are online.

## Step 8 — Evidence ledger

Build all three lists, always, and save them. The glance block does not print them;
the file must not omit them.

- **Measured** — you ran something. Name the command and the result.
- **Read** — traced in code. `file:line` per claim.
- **Unverifiable until deployed** — infra and deploy-time behaviour: SNS/SQS filter
  policies, Terraform plans, IAM, migration ordering, feature-flag state in each
  environment. For these, verify the *naming chain* by hand (constant → config →
  filter) and say explicitly it is unproven until applied.

Never let an unverifiable item sit in the same list as an executed one — that is how
a risk memo becomes false comfort. Finish the file with the questions only the author
can answer; the glance block prints, on its `Ask author` line, the single one that
would most change the verdict.

## Output

**Print the glance block. Save the working.** The decision is in the terminal; the
file is where it can be checked, argued with, or picked up by whoever inherits the
incident. Both shapes are specified in
`~/.config/ai/guidelines/change-risk/risk-memo-template.md`.

Write the full memo — effects table, six lenses, failure modes in full, evidence
ledger, questions, coverage line — to `.claude/merge-risk/pr-<N>.md`, adding the path
to `.git/info/exclude` if it isn't already ignored; never edit a tracked
`.gitignore`. The glance block's `Full memo` line points at it.

**The block is the entire printed output.** Nothing follows it — no paragraph on what
you verified, what surprised you, or what the block means. Appending commentary is
what the glance format exists to prevent, and it is the easiest rule here to break
without noticing. A finding worth the reader's attention earns a `Watch` line; a
finding that isn't goes in the file and stays there.

Print it inside a fenced code block so the terminal preserves the column alignment,
hard-wrapped at 78 characters. Use the permanence words — `permanent`, `recoverable`,
`reversible` — not the D-codes: the ladder is the framework you reason with, not
vocabulary the reader should have to carry.

Colour comes from one glyph family only — 🔴 🟡 🟢 — used on the verdict and in the
`Watch` column. They are equal-width, so the columns hold. Never introduce a second
family (⚠️, ⛔, ↩️): variation selectors render at inconsistent widths and break the
alignment. ANSI escapes do not survive the renderer; do not emit them. Colour always
repeats what a word already says, so the block reads the same with every glyph gone.

Close with the footer legend, defining only the terms that block actually used. It is
what lets the labels stay one word: `Leaves` always gets a definition, the permanence
words get one when a `Watch` section is present, and a label a first-time reader can
already parse never does. If one of those stops being parseable, rename the label
rather than lengthening the footer.

Do not print the long form unless `--full` was passed. Compressing is not the same as
skipping: every step still runs, the evidence ledger is still built, and a finding
that does not fit the glance block goes in the file rather than being dropped. If the
analysis found nothing worth three `Watch` lines, print fewer — never pad to fill the
budget.

`--share`: load the `artifact-design` skill, write the page to the scratchpad, publish
with `Artifact`. Never publish for a private or security-sensitive repo without asking.
`--post`: one comment, never inline comments, confirmation first. Post the glance
block, not the file.

## Scaling

| depth | effect analysis | lens agents | skeptics |
|---|---|---:|---:|
| `quick` | inline | 0 | 0 |
| `standard` | inline | 2 (reversibility, blast radius) | 1 per side |
| `deep` | 1 agent per effect cluster | 4 (adds failure-mode and detection) | 3 per side, majority-refute |

Choose `quick` under ~5 changed files with no infra, migration, or outbound effect.
Choose `deep` on request, or whenever the scan reaches D4/D5, or the PR touches money,
auth, customer comms, data migration, or a public contract. If you bound coverage,
**say what you dropped** — silent truncation reads as full coverage.

## Local checkout

Reading callers and running checks needs the code. Use a throwaway worktree so the
user's tree is untouched, and pin every agent to that path:

```bash
gh pr checkout <N> --repo <repo> --branch merge-risk-<N> 2>/dev/null \
  || git fetch origin pull/<N>/head:merge-risk-<N>
git worktree add <scratchpad>/pr-<N> merge-risk-<N>
```

Remove it when done. For a fork with no fetchable ref, fall back to patch-only
reading and mark every conclusion as read, never measured.

## Not this skill's job

Finding bugs, style, test-quality review, approving or merging. If the correctness
question is open, say so and point at the review skill rather than half-doing it
here — "this is a two-way door" says nothing about whether the code works.
