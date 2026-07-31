---
name: profile-run
description: Profile a finished agentic run — where its wall-clock went, per stage, and what the slowest stage actually spent it on. Answers "why did that take 4 hours" and "why is the implementation step 15-20 minutes" with measurements rather than intuition, then proposes the change that would move the number. Use after an implement-flow / implement-auto / implement run feels slow.
---

Profile a finished run and say where the time went: $ARGUMENTS

The sibling of `verify-run`. That one asks whether a run's "done" holds; this one asks
what it cost and why. Both read the run's own artefacts rather than re-deriving anything.

---

## The question this answers

A slow stage is slow for exactly one of two reasons, and the fix for one is useless for
the other:

- **Compute-bound** — it waits on commands. Tests, builds, installs. Fix by making the
  commands faster or running fewer of them.
- **Round-trip-bound** — it waits on the model. Time ≈ turns × per-turn latency, and
  each turn re-sends a context that keeps growing. Fix by making tool calls fewer and
  wider. Faster commands change nothing.

Most stages that "feel slow" are the second, and the fix people reach for first is the
first. Measure before recommending.

---

## Step 1 — Measure

```
python3 ~/.claude/skills/profile-run/profile-run.py [transcript_dir] [--top=N] [--type=AGENT]
```

With no directory it profiles the most recently modified workflow run. The workflow tool
prints its transcript dir when it launches; otherwise they live under
`~/.claude/projects/<project>/<session>/subagents/workflows/wf_*`.

It prints a per-stage table (runs, median, slowest, share of total), a concurrency
verdict, and a drill-down on the slowest agent: model turns, seconds per turn, transcript
size, tool mix, what its shell calls were doing, and the specific commands worth timing.

**Durations come from file mtimes** — `.meta.json` is written when an agent starts, its
`.jsonl` grows until it returns. The journal carries no timestamps, so this is the clock.
An agent still running has no end time; it is skipped.

## Step 2 — Time the operations by hand

The script names the test/build commands the slowest stage ran. Time one:

```
/usr/bin/time -p <the command>
```

This is the step that settles compute-bound vs round-trip-bound, and it is the one most
often skipped. A suite that runs in 7 seconds cannot explain an 18-minute stage, however
many times it ran.

## Step 3 — Value, not just cost

Cost alone does not tell you what to cut. For reviewer-shaped stages, weigh time against
what they produced — findings per run, minutes per finding — by reading the run's
`journal.jsonl` (`{"type":"result"}` lines carry each agent's return value, and the
`.meta.json` beside each transcript gives its type). A reviewer at 13 minutes per finding
is a candidate to merge or trim; one that caught the only real bug is not, however slow.

Do the same for refactor-shaped stages: count how many returned an applied change versus
"none needed". A stage that does nothing most of the time should become conditional.

## Step 4 — Recommend, ordered by payoff

Tie every recommendation to a number from Steps 1–3. Typical outcomes:

| Symptom | Change |
|---|---|
| Most shell calls are `rg`/`sed`/`head` | Front-load reading: open known files in ONE message, whole, then search only for gaps |
| Reviewers re-run the test suite | Stop them — check first whether anything downstream consumes their receipt |
| An agent rediscovers what the previous one knew | Pass it forward (changed-file list, diff, prior findings) |
| One agent is far slower than its siblings | Split that task; two short tasks fail more cheaply than one long one |
| Agent-minutes ≈ wall-clock | Nothing overlaps — only the critical path matters, so optimise the slowest stage, not the total |

State the trade honestly: reading wide costs input tokens to save round-trips. That is
usually the right trade, but it is a trade.

---

## Traps

Every one of these has produced a wrong answer in practice.

- **`cd` persists across commands in one shell invocation.** Comparing behaviour across
  directories in a single call silently measures the last `cd`. Wrap each in its own
  subshell: `(cd "$d" && ...)`.
- **A `-run` pattern that matches nothing exits 0** and prints `no tests to run`. Go
  replaces spaces in subtest names with underscores. Always confirm the test actually
  selected before believing a timing or a pass.
- **`$?` after a pipeline is the last command's**, so `cmd | head` reports `head`'s exit
  status. Use `PIPESTATUS`/`pipefail`, or check the output rather than the code.
- **zsh does not word-split unquoted variables.** A `for x in $LIST` loop that works in
  bash silently passes the whole string as one item.
- **Editor diagnostics go stale mid-run.** Agents rewriting files leave gopls (and
  friends) reporting compile errors that no longer exist. Confirm with a real build
  before treating one as a finding.
- **A verifier that runs before the finish step** cannot see the finish step's commit.
  Check the tree before repeating its claim.

---

## Reporting

Lead with where the time went and the one-line verdict — compute-bound or
round-trip-bound — then the evidence, then the recommendations. Give the share of total
for each stage, not just absolute minutes: a 6-minute stage that runs 14 times matters
more than an 18-minute stage that runs once.

Name what you did **not** change and why. A stage that is slow but earning its keep
should be called out as such, so it does not get trimmed on the next pass.
