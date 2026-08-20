# Risk memo shape

Two artefacts, and they are not the same length:

- **The glance block** — what you print. A reader deciding whether to click merge
  gets their answer in the first line and the whole picture in under twenty. No
  tables, no section headings, no prose paragraphs beyond one.
- **The saved memo** — what you write to the file. The full working: effects table,
  six lenses, failure modes in full, evidence ledger, every question. Nobody has to
  read it to decide; it exists so the decision can be checked, argued with, or
  picked up by whoever inherits the incident.

Print the glance block. Save the memo. Print the long form only on `--full`.

---

## The glance block

Printed inside a fenced code block so the terminal keeps the column alignment.
Hard-wrap at 78 characters. Labels are a fixed 14-character column; content starts
at column 15 and wrapped lines indent to match.

```
──────────────────────────────────────────────────────────────────────────────
 PR 6798 · Tolerate un-parseable/empty To: headers on inbound email
──────────────────────────────────────────────────────────────────────────────

 Verdict      🟢 SAFE TO MERGE — nothing blocking

 Change       stops rejecting inbound email whose To: header is unusable
 Undo         revert + one deploy
 Reaches      only messages that already 400'd — ~60 in two weeks
 Leaves       events whose To says "mailbox", unmarked as inferred

 Watch
   🔴 permanent   the To substitution cannot be told apart afterwards
   🔴 permanent   an un-parseable mailbox leaves To empty, nothing validates it
   🟢 reversible  bulk mail becomes conversations agents see in the backlog

 Ask author   mark the substituted To, or leave it empty? Mailbox is already
              on the event
 Full memo    .claude/merge-risk/pr-6798.md
──────────────────────────────────────────────────────────────────────────────
 Leaves: what a revert does NOT undo · permanent: cannot be unwritten/unsent
 recoverable: repairable from known prior state · reversible: revert is the fix
```

### Rules

**The header** carries the PR and nothing else: a rule, `PR <n> · <title>`, a rule.
Trim the title to fit on one line. No verdict, no glyph — the header says which PR
this is, and the body says what to do about it.

**Verdict** is the first body row, set off by a blank line, and it must read as a
complete answer on its own. Three states:

| Verdict | When |
|---|---|
| 🟢 `SAFE TO MERGE — nothing blocking` | two-way or two-way-with-trivial-cleanup, bounded radius, nothing required first |
| 🟡 `MERGE AFTER <gate>` | safe once that gate holds |
| 🔴 `HOLD — <why>` | one-way, or a silent failure mode with no detection and a live population |

Never leave the verdict dangling. `MERGE WHEN`, `NEEDS`, `HOLD UNTIL` all pose a
question the reader then has to go and answer, which is the one thing this row exists
to prevent. Name the gate: `MERGE AFTER 6817 is merged and deployed`,
`MERGE AFTER a dry-run against a shadow table`. Use `AFTER` for every amber verdict
rather than mixing in `ONCE` and `WHEN` — one connector means the eye reads the shape
without parsing the grammar. The row wraps like any other, so the gate can be a full
phrase; if it takes more than a line, it is several conditions wearing one label, and
either the `Before merge` rows should carry them or the verdict is really a `HOLD`.

**The four facts.** One line each, no exceptions — if a fact needs two lines, it is
carrying detail that belongs in the file.

- `Change` — what the running system does differently. Not a summary of the diff.
- `Undo` — the cheapest real path back: `revert + one deploy`, `flag flip`,
  `revert + backfill (hours)`, `cannot be undone, only compensated`.
- `Reaches` — who and how many, with the basis implied by the wording. Say
  `all AU customers`, `tests only`, `~60 in two weeks`.
- `Leaves` — the residue after a revert. `nothing` is a complete and common answer,
  and printing it is the point: it is the fact people most want and least often get.

**Watch.** At most three, most severe first, ranked by irreversibility × population
rather than by likelihood. Each line opens with a permanence word in the second
column, so the eye scans one column to see how bad the worst case is:

| Marker | Ladder rung | Meaning |
|---|---|---|
| 🔴 `permanent` | D2–D5 | cannot be unwritten, unsent, or restored |
| 🟡 `recoverable` | D1 | needs a repair or rebuild, but the prior state is knowable |
| 🟢 `reversible` | D0 | the revert is the whole fix |

**One glyph family, deliberately.** The three coloured circles are the only coloured
characters in the block, they carry the same meaning in the verdict as in the `Watch`
column, and they are all the same width — so the columns still line up. Never reach
for a second family (⚠️, ⛔, ↩️): variation selectors render at inconsistent widths and
break the alignment the fixed columns exist to provide. Colour is a second channel on
information the words already carry, never the only channel — the block reads
identically with every glyph stripped.

Then the symptom in plain words. No `file:line`, no rung codes, no arrows — the
saved memo carries the full trigger → symptom → detection chain. A failure mode with
no detection at all goes first regardless of likelihood. Print fewer than three when
there are fewer than three; never pad.

**Before merge** appears only when there is something to do. A 🟢 verdict already
says `nothing blocking` on its own row, so the line is dropped rather than repeated.
Under an amber or red verdict it carries the conditions in full — the evidence behind
the gate, and any second condition the verdict row could not hold. Each says what it
buys. Add a `Before <event>` line only when the door closes on something specific —
a UI PR, a client integration, a backfill.

**Ask author** — the single question for the PR author whose answer would most change
the verdict. Omit the line entirely if there isn't one. Every other question goes in
the file.

**Full memo** — the path to the saved long-form memo. Always last.

### The footer

A rule, then a legend for the terms the block just used — the labels are short
because the footer is there, and the footer is short because it only defines what
this block contains. Two lines at most, at the same 78-character wrap.

```
──────────────────────────────────────────────────────────────────────────────
 Leaves: what a revert does NOT undo · permanent: cannot be unwritten/unsent
 recoverable: repairable from known prior state · reversible: revert is the fix
```

Define only what appears above it. A block with no `Watch` section drops the three
permanence words and keeps one line:

```
──────────────────────────────────────────────────────────────────────────────
 Leaves: what a revert does NOT undo
```

Define a label only when a first-time reader could not say what belongs on that line.
`Verdict`, `Change`, `Undo`, `Reaches`, `Watch`, `Before merge`, `Ask author` and
`Full memo` pass that test, so they are never defined — and if one of them stops
passing it, the fix is a better label, not a longer footer. `Leaves` always earns its
line: it is the one whose meaning nobody guesses, and the one carrying the answer
people came for.

### Nothing follows the block

The block is the entire printed output. Do not add a paragraph explaining what it
means, what you verified, or what you found interesting — that is the file's job, and
appending it defeats the whole format. If a finding is worth the reader's attention,
it earns a `Watch` line; if it isn't, it goes in the file and stays there.

### Budget

Twenty lines is the ceiling, not the target. A D0/D1 change with a small radius
prints nine:

```
──────────────────────────────────────────────────────────────────────────────
 PR 6810 · Refactor the 1NEW letter test file
──────────────────────────────────────────────────────────────────────────────

 Verdict      🟢 SAFE TO MERGE — nothing blocking

 Change       none at runtime — test file only
 Undo         revert + one deploy
 Reaches      tests only
 Leaves       nothing

 Full memo    .claude/merge-risk/pr-6810.md
──────────────────────────────────────────────────────────────────────────────
 Leaves: what a revert does NOT undo
```

A conditional verdict names its gate on the verdict row, so the answer still arrives
without reading further:

```
──────────────────────────────────────────────────────────────────────────────
 PR 6823 · Rocket UI: raise a case's Jira ticket from the actions rail
──────────────────────────────────────────────────────────────────────────────

 Verdict      🟡 MERGE AFTER 6817 is merged and deployed

 Change       adds a CREATE JIRA TICKET button to the case actions rail
 Undo         revert + one deploy
 Reaches      every agent holding a ticketless case, every client, no flag
 Leaves       nothing; tickets raised while live stand on the desk

 Watch
   🔴 permanent   a press opens a real desk ticket even for clients deliberately
                  off CASE_JIRA_ESCALATION — that gates only the automatic path
   🟢 reversible  merged before 6817 deploys, every press hits an unregistered
                  route and the agent gets a toast they cannot act on

 Before merge 6817 is still OPEN and master has no jira-ticket route registered
              the bot's "Retryable is never sent" comment is stale — 6817 adds
              that field, and its Option A would double-handle it
 Ask author   confine the manual raise to clients on CASE_JIRA_ESCALATION?
 Full memo    .claude/merge-risk/pr-6823.md
──────────────────────────────────────────────────────────────────────────────
 Leaves: what a revert does NOT undo · permanent: cannot be unwritten/unsent
 reversible: revert is the whole fix
```

Bad news uses the same shape, which is what makes it readable:

```
──────────────────────────────────────────────────────────────────────────────
 PR 7014 · Backfill customer contact preferences
──────────────────────────────────────────────────────────────────────────────

 Verdict      🔴 HOLD — the prior values are overwritten with no backup

 Change       rewrites contact preferences for every AU customer in place
 Undo         cannot be undone — the prior values are gone
 Reaches      ~1.2M customers, all channels, one batch [measured]
 Leaves       the old preferences; consent state unrecoverable

 Watch
   🔴 permanent   an over-broad match opts customers back into contact
   🔴 permanent   no dry-run, no diff, no sample — the first run is the real one

 Before merge dry-run writing to a shadow table, and a reviewed sample diff
 Ask author   where does the pre-backfill state survive if this is wrong?
 Full memo    .claude/merge-risk/pr-7014.md
──────────────────────────────────────────────────────────────────────────────
 Leaves: what a revert does NOT undo · permanent: cannot be unwritten/unsent
```

Spend lines only where the risk is: a block that flags everything gets skimmed on the
PR where it mattered.

---

## The saved memo

Everything the analysis produced, in this order. This is where the discipline lives
even though it is not what gets printed.

1. **Verdict line and the why** — the same text as the glance block, so the file
   stands alone.
2. **Effects table** — `# | effect | file:line | rung | note`, deploy-time effects
   included. Mark any rung that is nominal rather than real (`D4 → D0 in practice,
   no consumer`) — the gap between the two is usually the most useful line in the memo.
3. **Reversibility** — verdict, undo procedure with a time-to-undo per step, what a
   revert does *not* undo, and when the door closes.
4. **Blast radius** — six lenses, one to three lines each, every number carrying
   `[measured]`, `[derived]` or `[estimated]`.
5. **Failure modes** — the same three as the glance block, in full: trigger →
   symptom → who feels it → loudness → detection and time-to-detect → rung. Include
   the exposure arithmetic where it applies:
   `400 SMS/day ÷ 8h × 6h to detect ≈ 300 wrong messages before anyone knows.`
6. **Merge conditions** — each naming what it buys: which rung it lowers, or how
   much detection time it cuts.
7. **Secondary lenses** (`--full`) — security & authz, data & compliance, cost,
   performance & capacity, dependencies, reviewer routing, timing. One line each;
   "not checked" is an acceptable line, silently dropping one is not.
8. **Evidence ledger** — measured / read / unverifiable-until-deployed, three lists,
   never merged.
9. **Questions for the author**, and a closing **coverage** line: what was dropped,
   which flags were not passed, and where a skeptic pass disagreed rather than
   converged. Report the disagreement; never average two positions into a middle.

---

## Tone rules

- Grade the change, not the author. Never speculate about care or competence.
- Say "I could not verify X" rather than implying X is wrong.
- Most PRs are two-way doors with a small radius. Print five lines and stop.
