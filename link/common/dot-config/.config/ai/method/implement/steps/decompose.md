## Phase 1: Decompose

### Adopt an existing breakdown if there is one

If the request names a file in `tasks/`, or `clerk prepare` reported a `resume`, read that breakdown, present it with `clerk status`, and skip decomposing. Tasks with `done: true` in the sidecar are finished — `clerk step` resumes at the first unblocked one that is not.

**Do not decompose a story that already has a breakdown in progress.** Decomposing again produces a different breakdown against the same code, and the sidecar recording what was already built no longer describes it. `clerk status` tells you where the previous run stopped.

A breakdown with no `tasks/<story>.json` beside it cannot be bound: `clerk step` refuses rather than guessing at dependencies from prose. Decompose it again, or write the sidecar by hand from the task sections — one entry per task with its `n`, `title`, `depends_on` and `done` — and commit it alongside the breakdown it describes.

### Otherwise decompose

{{seam:decompose}}

It does the codebase exploration and dependency analysis that makes the breakdown worth having. It writes `tasks/[story-name].md` describing each task, and `tasks/[story-name].json` beside it — the sidecar that carries the dependency graph and the run's progress. The sidecar is the durable record; the markdown is prose and nothing rewrites it.

**Carry the learnings forward.** Pass the learnings file's contents as `Accumulated project learnings`: "These are durable conventions, recurring review findings and constraints from earlier runs in this repo. Fold the relevant ones into each task's `patterns_to_follow`, and do not re-propose work they already cover."

**Pass the guidelines** as `Required Reading` — the text `clerk guidelines` printed you, not a list of paths to go and fetch. Add: "The unit-of-behavior section is the one to decide each task against: whether it delivers independently testable behaviour, or is only meaningful through a downstream consumer."

**If it fails or returns nothing, retry once.** Then decompose yourself and show the user the list you wrote, flagging that it skipped the codebase-exploration pass.

**One judgment call.** Decomposing costs a full agent (~15 minutes measured). Work that is obviously a single slice does not need it — say so and go straight to building. Anything with more than one deliverable, real dependencies, or an unclear surface gets decomposed.

### Bind the breakdown to the run

```
clerk step --done decompose --tasks-file <the breakdown>
```

Before it binds anything it runs `clerk lint --rule certainty-unevidenced` over the sidecar and refuses on a finding. Seconds, no agent, and it settles the one thing about an assessment that is not a matter of opinion: a task called `high` or `medium` certainty with no precedent named, or one citing a file that is not there. Both mean the same thing — a confidence with nothing behind it, which is how the field drifts to `high` on everything and stops being worth reading. Fix a finding by correcting the assessment, not by deleting the reference: a precedent you cannot produce is a task that is `low`. An adopted breakdown goes through the same check, which tells you whether the one you are about to build was checked when it was written.

**A breakdown planned before these fields existed carries neither**, and `clerk status` lists those under `gears.unassessed`. Read them as medium certainty and low blast radius — but **say that you did**, because "not assessed" and "assessed as routine" are otherwise the same silence. Do not re-decompose a run in progress to acquire them.

On success it prints the task table — certainty and blast radius included — which is the breakdown presented, with the first task under `next`.

### Present the breakdown, then build

Show the breakdown, in order, with dependencies, **each task with its certainty and blast radius** — then start. **It is not something to wait on.**

Those two columns are the cheapest review the breakdown ever gets. A task the breakdown called routine that the user knows is not costs them one sentence to say so here, and costs a whole run to find out from the code. Say which tasks would pause were `gears` on, so that sentence can be "turn gears on" rather than a description of what to watch for.

That follows from what this skill is for. Its whole claim is that at minutes per feature, building a version and looking at it is a cheaper way to find out whether a requirement is right than arguing about a task breakdown; stopping to debate the breakdown spends the advantage the speed was bought for. The branch is disposable, the audit reads the finished code against the request rather than against the breakdown, and a breakdown that turns out wrong costs one short run rather than a negotiation.

**With `review_breakdown` on, it is a pause:**
- Show the breakdown and ask the user to approve or request changes.
- On changes, re-spawn the decompose agent with the feedback and present the revised plan. Repeat.
- Do not write code until the breakdown is explicitly approved.

Reach for it when decomposing is the expensive part rather than the code — a migration whose slicing decides how reviewable the result is, work whose surface you are unsure of, anything where being wrong costs more than one run.

Do not pass it to a run nobody is watching. A launcher firing a wave of deliverables in parallel wants each one building, not each one holding a breakdown up to an empty pane.

