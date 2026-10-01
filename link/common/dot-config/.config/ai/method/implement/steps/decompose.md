## Decompose the story into tasks

{{include:shared/reading.md}}

### Adopt an existing breakdown if there is one

If the request names a file in `tasks/`, or the step reported a `resume`, read that breakdown, present it with `clerk status`, and skip decomposing. Tasks with `done: true` in the task record are finished — `clerk step` resumes at the first unblocked one that is not.

**Do not decompose a story that already has a breakdown in progress.** Decomposing again produces a different breakdown against the same code, and the task record recording what was already built no longer describes it. `clerk status` tells you where the previous run stopped.

A breakdown with no `tasks/<story>.json` beside it cannot be bound: `clerk step` refuses rather than guessing at dependencies from prose. Decompose it again, or write the task record by hand from the task sections — one entry per task with its `n`, `title`, `depends_on` and `done` — and commit it alongside the breakdown it describes.

### Otherwise decompose

{{variant:decompose}}

It does the codebase exploration and dependency analysis that makes the breakdown worth having. It writes `tasks/[story-name].md` describing each task, `tasks/[story-name].json` beside it — the task record that carries the dependency graph and the run's progress — and `tasks/[story-name].design.yaml`, the planned design. The task record is the durable one. The markdown is prose, and the run rewrites it only to keep the open tasks true after a design change, as the build step says.

**Carry the learnings forward — the index, not the file.** `clerk learn index --text --match "<terms>"` lists the recorded learnings whose title or apply-when names one of the story's packages, paths or nouns, each as its title, type and apply-when; `clerk learn show "<title>"` returns the body of one. Read the index, pick by apply-when, and pass the picked bodies as `Accumulated project learnings`: "These are durable conventions, recurring review findings and constraints from earlier runs in this repo. Fold them into each task's `patterns_to_follow`, and do not re-propose work they already cover."

Pass the index rather than the whole file, because the file only ever grows and the planner reads all of it. One repo's had reached 225 entries and 40,000 words — sixty-five thousand tokens of history arriving before the story did, on every run. The index is a third of that, and the bodies you actually fetch are a handful.

**An entry that the run proves wrong is `clerk learn drop "<title>"`.** A learning written against code that has since been rewritten still reads as true, and every later run in the repo will act on it — retiring it is as much a part of this step as writing one.

**Pass the guidelines** as `Required Reading` — the text `clerk guidelines` printed you, not a list of paths to go and fetch. Add: "The unit-of-behavior section is the one to decide each task against: whether it delivers independently testable behaviour, or is only meaningful through a downstream consumer."

**If it fails or returns nothing, retry once.** Then decompose yourself and show the user the list you wrote, flagging that it skipped the codebase-exploration pass.

**One judgment call.** Decomposing costs a full agent (~15 minutes measured). Work that is obviously a single slice does not need it — say so and go straight to building. Anything with more than one deliverable, real dependencies, or an unclear surface gets decomposed.

### A deliverable that builds on another

A deliverable of a larger story (`tasks/<story>/<deliverable>/tasks.md`) can start after a prerequisite deliverable is built. That run can have changed the design its tasks assumed. Read the design changes of each prerequisite before you bind: `clerk design corrections --run <the prerequisite's branch>` returns its planned design and the design changes it recorded, with their reasons. Where one changes a type or a name that this deliverable's tasks or planned design use, edit them to match before you bind, and say what you changed when you present the breakdown.

### Bind the breakdown to the run

```
clerk step done decompose --tasks-file <the breakdown>
```

Before it binds anything it runs `clerk lint --rule certainty-unevidenced` over the task record and refuses on a finding. Seconds, no agent, and it settles the one thing about an assessment that is not a matter of opinion: a task called `high` or `medium` certainty with no precedent named, or one citing a file that is not there. Both mean the same thing — a confidence with nothing behind it, which is how the field drifts to `high` on everything and stops being worth reading. Fix a finding by correcting the assessment, not by deleting the reference: a precedent you cannot produce is a task that is `low`. An adopted breakdown goes through the same check, which tells you whether the one you are about to build was checked when it was written.

**A breakdown planned before these fields existed carries neither**, and `clerk status` lists those under `gears.unassessed`. Read them as medium certainty and low blast radius — but **say that you did**, because "not assessed" and "assessed as routine" are otherwise the same silence. Do not re-decompose a run in progress to acquire them.

On success it prints the task table — certainty and blast radius included — which is the breakdown presented, with the first task under `next`.

**Binding also binds the planned design** that the task record names as `design_file`. clerk keeps a copy in the ledger: the build measures the code against the design as it was planned, and the reasons the run gives later are read against it. A planned design that does not read refuses the bind; fix the file, not the task record. A task record with no `design_file` binds with no planned design, and the reply says so: the build then judges no design.

### Present the breakdown, then build

Show the breakdown, in order, with dependencies, **each task with its certainty and blast radius** — then start. **It is not something to wait on.**

Show the planned design too. It is Markdown with a Mermaid diagram, which a terminal does not draw, so write it to a file outside the repository and give the path: `clerk design show --planned --out <file>`. Name the types it plans in one line beside the path. A wrong name costs the reader one line to correct here, and a change in every task that uses it after the build.

Those two columns are the cheapest review the breakdown ever gets. A task the breakdown called routine that the user knows is not costs them one sentence to say so here, and costs a whole run to find out from the code. Say which tasks would pause were `gears` on, so that sentence can be "turn gears on" rather than a description of what to watch for.

That follows from what this skill is for. Its whole claim is that at minutes per feature, building a version and looking at it is a cheaper way to find out whether a requirement is right than arguing about a task breakdown; stopping to debate the breakdown spends the advantage the speed was bought for. The branch is disposable, the audit reads the finished code against the request rather than against the breakdown, and a breakdown that turns out wrong costs one short run rather than a negotiation.

**With `review_breakdown` on, it is a pause:**
- Show the breakdown and ask the user to approve or request changes.
- On changes, re-spawn the decompose agent with the feedback and present the revised plan. Repeat.
- Do not write code until the breakdown is explicitly approved.

Reach for it when decomposing is the expensive part rather than the code — a migration whose slicing decides how reviewable the result is, work whose surface you are unsure of, anything where being wrong costs more than one run.

Do not pass it to a run nobody is watching. A launcher firing a wave of deliverables in parallel wants each one building, not each one holding a breakdown up to an empty pane.

