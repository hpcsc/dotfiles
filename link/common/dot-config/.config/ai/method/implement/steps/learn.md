## Reflect and persist learnings

Distil what generalises: a codebase convention, a recurring finding, a constraint, a reusable pattern. **Falsifiable filter** — keep a candidate only if you can name in one sentence the specific future mistake it prevents. Otherwise it is noise.

**Include what `match-request` turned up.** Audit findings and diffs only ever teach implementation conventions. A story mismatch — a criterion that measured a proxy, a task boundary drawn in the wrong place, an assumption the story made that the codebase contradicts — teaches how a story in this repo gets *decomposed* wrong, and the next run reads this file while planning, before any code exists. That is the more valuable class; write it so a planner can act on it. It is exempt from wanting two observations, not from the falsifiable filter.

**And include where the breakdown mis-read the work.** Three observations from this run say the breakdown, not the code, was wrong, and all three are only visible from here:

- **A task the breakdown called high certainty that took several attempts to get right**, or arrived with a lint finding. Whatever the breakdown thought made it routine, does not.
- **A task the breakdown called low certainty that was boring.** This one is worth as much and gets recorded far less, because nothing went wrong to prompt it. Left unwritten, the next story over the same ground pauses on it again for nothing, and the pause keeps costing until someone notices.
- **A `clerk fixup` that came back `ambiguous`** at the audit step. Several commits in range touched one file, which is a task boundary drawn across something the codebase treats as one thing.

Each is a fact about *this repo's* work rather than about this story, which is what makes it worth a durable line. Write it so the next breakdown can act on it: name the kind of task, not the task.

Dedup against the learnings file on substance, not wording.

**Write what survives the filter, then show what you appended.** Nothing here waits on approval — the filter is the quality bar, and a learning that turns out to be wrong is cheaper to delete later than one that was never recorded.

```
clerk learn --list          # what is already recorded, to dedup against
clerk learn --type convention --title "<short title>" \
            --learning "<the durable fact, 1–2 sentences>" \
            --apply-when "<the future situation where this is relevant>" \
            --task 3 --feature "<feature name>"
```

`--type` is one of `convention`, `recurring-finding`, `constraint`, `pattern`. Pass `--path` when this run was given its own learnings file; otherwise it writes to the one `facts.learnings_path` names, **which hangs off the repo root and not the worktree you are standing in** — hand-resolving it from here writes a file the next run will never read.

**Dedup is still yours.** It refuses an exact title collision, and that is the whole of what a script can settle; matching on substance is judgment, which is what `--list` is for. `--replace` folds new wording into an entry that already exists.

A clean run produces no learnings, and that is fine — say so rather than manufacturing one to fill the section, and record it with `clerk step --done learn --none`; a `clerk learn` that wrote an entry is the evidence otherwise. The step's `breakdown_signals` lists the three observations above as the run recorded them: the tasks called `high` that were retried or refused by the lint, the `low` ones that were neither, the `fixup` calls that came back ambiguous.

**Committing is a decision; writing is not.** `in_tree` in the output says which regime you are in. When it is true the file is part of the repo's history: offer to commit so teammates inherit it — writing changes what your next run reads, committing changes what everyone's does — and when you leave it uncommitted, say so, because the next run in this repo finds the tree dirty and stops to ask about a file this one left there.

Reflect comes **last** because it leaves that file modified and uncommitted by design, and a dirty tracked file blocks a rebase.

**The `finished` reply carries `stats`** — the run's time and token table, per step, task and audit round, from `clerk stats`. Paste it into your closing message as a fenced block, verbatim. It is the reader's only view of what the run cost, and it is computed, so it needs no summarising.

