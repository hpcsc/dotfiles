# Four review skills that become programs

## What it is

A companion to [clerk-jev.md](clerk-jev.md). That page puts typed questions inside `clerk`.
This one applies the same tier rule to the skills under `link/common/claude/.claude/skills`,
and finds four that stop being prose a model reads and become programs a model runs.

Read the other page first for the contract, the client and the three rules every call site
obeys. Nothing here repeats them.

## The shape they share

Each of these skills already has a scan that produces candidates, and then a model that
reads each candidate. Three of them say so in almost the same words:

| Where | The words |
|---|---|
| `clerk lint` | "does this decide without judgment" |
| `assess-merge-risk/scripts/scan_signals.py` | "Leads, not verdicts" |
| `review-oo-design` 2.5 | "Every hit is a place to read, not a line to report" |
| `mutate-go` | "Triage by reading gets the category right most of the time, which is not the same as being right" |

The gap between a lead and a verdict is one judgement, repeated over many items, and it
needs no code to run. That is the whole of what Jev answers.

## When a skill converts

A skill **gains a call** when it makes the same small judgement over many items.

A skill **becomes a program** when everything around that judgement is already mechanical:
the gathering, the arithmetic and the report. The judgement is then the only part left for a
model, and a program can ask it.

A skill **stays a skill** when its output is prose somebody reads — a proposal, a report, a
diagram, a commit message. Jev returns no string.

Most of these skills are all three at once, in different phases. The conversion takes the
phases that qualify and leaves the rest where they are.

---

## 1. `review-module-structure`

The strongest case in the directory, and the only one that converts end to end.

**Phase 1 is already a program.** Inventory, public surface, internal dependency graph,
boundary, co-change from git. The skill writes the commands out and asks a model to run
them and hold the results in its head.

**Phase 2 is two questions and some arithmetic.**

| Step | What it decides | Who answers |
|---|---|---|
| 2.2 strength | Intrusive, Functional, Model, Contract | a choice of four, per edge |
| 2.3 distance | same file … separate system | the graph |
| 2.3 volatility | high or low, from the business domain | a score of two, per component |
| 2.4 balance | the finding | three lines of boolean algebra |

The skill states 2.4 as algebra already:

```
BALANCE = (STRENGTH XOR DISTANCE) OR NOT VOLATILITY
```

So one edge costs one question, one component costs one question, and everything else is
computed. A module with twelve components and thirty edges is one request.

**Its own rule becomes the confidence floor.** 2.3 says to ask the user when volatility is
genuinely unclear *and it changes the verdict*. A score below the floor on a component
whose grade flips a balance is exactly that case, and the program can tell which
components those are, because it holds the graph.

**What stays with the model.** The one-sentence responsibility per component (2.1) is
prose. So is the restructuring proposal (Phase 4), the diagram (Phase 5) and the report.
The program hands over a graded table and the model writes the review from it.

## 2. `assess-merge-risk`

The best instrumented of the four. `scripts/pr_fetch.sh` gathers the pull request and
`scripts/scan_signals.py` scans the diff for durability and blast-radius patterns. Its
docstring already draws the line this proposal is about: leads, not verdicts.

The D0–D5 reversibility ladder is a score of six levels, and a score takes two to ten. The
verdict rule needs no model at all — the skill states it as *the worst rung any effect
reaches*, which is `max()`. The six blast-radius lenses are six more rubrics over the same
state.

So the program grades each effect the scan found, takes the maximum, and hands the model a
ladder position per effect. The glance block, the undo procedure and the residue list stay
prose.

## 3. `mutate-go`

The one that gains most per call, because a run produces hundreds of survivors and each one
costs a read.

Triage asks one question per survivor, with exactly three answers: unasserted, unobservable,
or not worth pinning. That is a choice of three with clear criteria, and `mutate.sh` already
produces the list.

**The proof stays.** The skill is explicit that reading gets the category right most of the
time, which is not the same as being right, and that a claim must be proved before it is
reported. Jev sorts the list so the expensive proof runs where it matters, exactly as the
audit's scope pass sorts before its refuters run.

**One bucket must stay mechanical.** Go's cover tool never instruments a `case` condition,
so gremlins reports every mutation inside `case <expr>:` as unreachable whether the case is
exhaustively tested or never tested at all. No judgement over the source settles that. It
needs the block hit counts from a `-coverprofile`, which the script already reads.

## 4. `review-go-tests`

Severity is a choice of four — Disqualifier, Fidelity, Resilience, Precision — and the
skill already writes the criteria for each as a table, with examples. The reporting rule is
then arithmetic: report the first three, and report Precision only when it is severe.

The substitution test stays with execution. A tautology is proved by replacing the code
under test and watching the test still pass, which is a mutation probe and not a judgement.

---

## Skills that gain a call and stay skills

| Skill | Where |
|---|---|
| `review-oo-design` | 2.6, the vocabulary diff: "one concept, two words" is a pairwise same-meaning question, the same one as `repeated_gaps` |
| `decompose-to-tasks`, `decompose-to-deliverables` | `certainty` and `blast_radius`, which is site 7 of the other page |
| `implement`, `deliver-story`, `verify-run` | the nine sites of the other page |
| `review-go` | the per-symbol naming checks of steps 2 to 5 |

`review-oo-design` does not convert, and it is the closest miss. Phases 5 and 6 propose a
redesign and design a module from scratch. That is generation.

## What does not convert

`write-pr`, `review-pr`, `draw-event-flow`, `write-user-story`, `model-events`,
`propose-feature`, `write`, `solution-architect`, `domain-design-review`, `test-go`,
`refactor-go`, `implement-go-interface`, `cue`, `pcommit`, and the eight Anthropic skills
under `synced/`. Each either writes prose or gives instructions once, rather than judging
many items.

`profile-run` is a near miss. It measures and divides. Its numbers come from timing rather
than from judgement, so there is nothing to ask.

## What every conversion keeps

A program that grades is not a program that reviews. In all four, the model still writes the
sentence a human reads: the responsibility, the finding, the proposal, the memo. The program
removes the part where a model holds thirty edges in its head and grades them one at a time
in prose, which is the part it does worst and the part that costs the most context.

## Order of work

1. `review-module-structure`. It converts end to end, and its arithmetic is written down
   already, so the program is testable against a module whose answer is known.
2. `mutate-go`. The list exists, the triage is three options, and the win scales with the
   survivor count.
3. `review-go-tests`. One question per violation, criteria already tabulated.
4. `assess-merge-risk`. The largest, and the one whose report is hardest to reduce to a
   table.

Each is independent. None needs the other, and none needs the clerk sites.
