## Phase 1: Plan

### Adopt an existing breakdown if there is one

If the request names a file in `tasks/`, or `clerk prepare` reported a `resume`, read that breakdown, present it with `clerk status`, and skip decomposing. Tasks with `done: true` in the sidecar are finished — `clerk next` resumes at the first unblocked one that is not.

**Do not decompose a story that already has a breakdown in progress.** Decomposing again produces a different breakdown against the same code, and the sidecar recording what was already built no longer describes it. `clerk status` tells you where the previous run stopped.

A breakdown written before sidecars existed has no `tasks/<story>.json`, and `clerk next` refuses without one rather than guessing at dependencies. Recover it — and if it carries an old `- [x]` checklist, the recovery seeds `done` from those ticks so the run resumes where it left off:

```
clerk sidecar          # reads the `### Task N:` sections and their `**Depends on:**` lines
```

It prints what it extracted. **Check those dependencies against the breakdown before relying on them** — a misread edge reorders the work silently, which is the one thing this file is the source of truth for. If the breakdown has only a checklist and no task sections, it says so and leaves every `depends_on` empty; that is safe here, since a breakdown is emitted in dependency order and this skill runs one task at a time. Commit the sidecar alongside the breakdown it describes.

### Otherwise decompose

{{seam:decompose}}

It does the codebase exploration and dependency analysis that makes the breakdown worth having. It writes `tasks/[story-name].md` describing each task, and `tasks/[story-name].json` beside it — the sidecar that carries the dependency graph and the run's progress. The sidecar is the durable record; the markdown is prose and nothing rewrites it.

**Carry the learnings forward.** Pass the learnings file's contents as `Accumulated project learnings`: "These are durable conventions, recurring review findings and constraints from earlier runs in this repo. Fold the relevant ones into each task's `patterns_to_follow`, and do not re-propose work they already cover."

**Pass the guidelines** as `Required Reading` — the text `clerk guidelines` printed you, not a list of paths to go and fetch. Add: "The unit-of-behavior section is the one to decide each task against: whether it delivers independently testable behaviour, or is only meaningful through a downstream consumer."

**If it fails or returns nothing, retry once.** Then decompose yourself and show the user the list you wrote, flagging that it skipped the codebase-exploration pass.

**One judgment call.** Decomposing costs a full agent (~15 minutes measured). Work that is obviously a single slice does not need it — say so and go straight to building. Anything with more than one deliverable, real dependencies, or an unclear surface gets decomposed.

### Check the breakdown's evidence

```
clerk lint --rule certainty-unevidenced <the sidecar it wrote>
```

Seconds, no agent, and it settles the one thing about an assessment that is not a matter of opinion: a task called `high` or `medium` certainty with no precedent named, or one citing a file that is not there. Both mean the same thing — a confidence with nothing behind it, which is how the field drifts to `high` on everything and stops being worth reading.

Pass the sidecar's path; the rule reads the breakdown rather than the diff, so it is not in what `--staged` would find. Fix a finding by correcting the assessment, not by deleting the reference: a precedent you cannot produce is a task that is `low`.

Run it on an adopted breakdown too, which costs the same and tells you whether the breakdown you are about to build was checked when it was written.

**A breakdown planned before these fields existed carries neither**, and `clerk status` lists those under `gears.unassessed`. Read them as medium certainty and low blast radius — but **say that you did**, because "not assessed" and "assessed as routine" are otherwise the same silence. Do not re-decompose a run in progress to acquire them.

**Then bind it to the run:** `clerk step --done plan --tasks-file <the breakdown>`. It runs this lint itself and refuses on a finding, and on success it prints the task table — certainty and blast radius included — which is the breakdown presented, with the first task under `next`.

### Present the breakdown, then build

Show the breakdown, in order, with dependencies, **each task with its certainty and blast radius** — then start. **It is not something to wait on.**

Those two columns are the cheapest review the breakdown ever gets. A task the breakdown called routine that the user knows is not costs them one sentence to say so here, and costs a whole run to find out from the code. Say which tasks would pause were `gears` on, so that sentence can be "turn gears on" rather than a description of what to watch for.

That follows from what this skill is for. Its whole claim is that at minutes per feature, building a version and looking at it is a cheaper way to find out whether a requirement is right than arguing about a task breakdown; stopping to debate the breakdown spends the advantage the speed was bought for. The branch is disposable, the audit reads the finished code against the request rather than against the breakdown, and a breakdown that turns out wrong costs one short run rather than a negotiation.

**With `review_plan` on, it is a pause:**
- Show the breakdown and ask the user to approve or request changes.
- On changes, re-spawn the decompose agent with the feedback and present the revised plan. Repeat.
- Do not write code until the breakdown is explicitly approved.

Reach for it when decomposing is the expensive part rather than the code — a migration whose slicing decides how reviewable the result is, work whose surface you are unsure of, anything where being wrong costs more than one run.

Do not pass it to a run nobody is watching. A launcher firing a wave of deliverables in parallel wants each one building, not each one holding a breakdown up to an empty pane.

