{{seam:frontmatter}}

{{seam:invocation}}

**The request** is everything the caller just handed you: the feature description, plus any flags such as `--in-place`, `--integrate` or `--review-plan`. **Record it verbatim before you do anything else**, and refer to that record from here on. Several steps below need its exact words — the audit is given the request unsummarized, and the validation pass re-reads it against the finished branch — and two steps read flags out of it. Do not rely on being able to recover it later from memory or from a substituted token.

**A flag not in the request may still be on.** All four are also repo settings, because each is as often a property of the repo as of the run: one whose build cannot work from a worktree wants `--in-place` every time. Hand the request to `clerk prepare --request` and it resolves both layers at once, reporting the answers in `flags` — read those, not the request, wherever a step below turns on a flag. It also reports `flag_sources`, naming what decided each one, so a run that behaves unexpectedly can say which file to look in.

| Flag | `flags` key | Off again with |
|---|---|---|
| `--in-place` | `in_place` | `--worktree` |
| `--integrate` | `integrate` | `--no-integrate` |
| `--review-plan` | `review_plan` | `--no-review-plan` |
| `--gears` | `gears` | `--no-gears` |

The request always outranks the files, in both directions — that is what the middle column is for, and why a repo may safely default one on. Say in your opening summary which of the four are on and what set them; a run that quietly builds in place because of a file the user forgot is a surprise they paid for with a dirty checkout.

**You write the code.** This skill does not delegate construction to implementation agents. Review is delegated, at the end, to `audit-implement`.

<!-- GENERATED from ~/.config/ai/method/implement/. Edit the body or a seam, then run
     `task gen:skills` — edits made here are overwritten. -->

---

## Why this shape

Profiling four `implement-flow` runs over one feature — 139 agents, 11.3 hours, average concurrency 1.12 — put **64% of wall clock in construction and its retries**, while the review stages produced nearly all of the value. A comparable feature built directly took **7 minutes**.

Construction is serial, judgment-dense and context-heavy: every delegated agent pays a full context rebuild for work you are already holding in mind. Review is the opposite — embarrassingly parallel, and it *gains* from reviewers who never watched the code being written.

So: build directly, review adversarially at the end.

What that buys is a lopsided run rather than a uniformly cheap one. A four-task feature delivered this way spent 44 minutes on construction and 89 on the audit loop — the 64% is still there, moved onto the half that earns it. Budget for review being the larger number, and read step 2's round count as the main lever you have over how long a run takes.

**The trap this skill exists to avoid.** Nothing hands you the project's guidelines — left to yourself you follow the code you can see and miss the rules you cannot, then find out at review. Phase 0 is not throat-clearing; loading them is the price of writing the code yourself, and it is much cheaper than the findings it prevents.

Use `implement-flow` instead for large mechanical migrations with genuinely disjoint files, or for unattended overnight runs.

**And prefer this one whenever the *what* is not yet settled.** The delegated siblings execute a specification: they prove the code obeys acceptance criteria fixed before any code existed, which is right when the behaviour is known and wrong when the story is the thing under investigation. Being fast is what makes this skill the tool for that case — at minutes per feature, building a version, looking at it and discarding it is a cheaper way to find out whether a requirement is right than arguing about it in a task breakdown.

---

## Certainty, and what it changes

Every task in the breakdown carries two assessments the decomposition made. They answer different questions and fail separately:

- **`certainty`** — `high` / `medium` / `low`. How sure the plan is that the repo already answers *how* to build this. `high` means the task repeats a pattern the breakdown can point at by file and line range. `low` means no instance of it exists here, or the design is itself the thing being decided.
- **`blast_radius`** — `low` / `high`. What being wrong would cost, whatever the odds of being wrong are. Authentication and authorization, money arithmetic, migrations and destructive writes, credential handling, a contract something outside this repo consumes.

Keeping them apart is the point. A task you have written twenty times before, against the payments ledger, is high certainty and high blast radius at once — and only the second argues for slowing down. Collapsed into one "risk" score, that task reads as medium and gets neither the speed it earned nor the care it needs.

**By default they are reported and nothing else.** `clerk status` prints them, this skill announces them per task, and every task is built straight through — which is what the profiling this shape rests on says is right for work whose method you can already see. Naming the exceptions costs a line per task and buys a reader who knows where to look hardest.

**With `gears` on, they change how the run is driven.** Phase 2 says how, in one place. Turn it on when the story's shape is not settled, when the work reaches somewhere expensive to be wrong about, or when someone is actually watching. Leave it off for a wave of deliverables firing into panes nobody is reading, where a pause is indistinguishable from a run that died.

A breakdown planned before these fields existed carries neither, and `clerk status` lists those under `gears.unassessed`. Read them as medium certainty and low blast radius — but **say that you did**, because "not assessed" and "assessed as routine" are otherwise the same silence.

---

## Phase 0: Ground yourself

{{include:shared/prepare.md}}

### Read the guidelines — yourself

```
clerk guidelines
```

The required reading for the languages it detects, cut to the sections that matter and printed as text. Read what it prints; do not re-fetch any of it.

It emits the whole of `comments.md` and the naming guideline — both short, and the two most often broken by default, since a comment that restates the code, or names it by its position in a plan ("task 3", "the new helper") rather than its domain role, is the single most common finding an audit of this work returns. From the long files it takes only what a run must have loaded: "What to Test", the unit-of-behavior section and the assertion section from the language testing guideline, and from `caller-patterns.md` the identification section plus the Quick Reference, along with each file's own section list so you can ask for more.

**Then name your caller pattern.** Which of UI / Inbound / Outbound / Async / Exported API this work has is the one judgment in this step, so it is asked for rather than guessed:

```
clerk guidelines --caller ui        # …or inbound, outbound, async, exported
```

Add `--dom` or `--state` when the task touches the DOM or shared state.

**Read its "Not loaded" section if it prints one.** A guideline that has been reorganised out from under the slot list, or a language with no guideline set at all, is reported there rather than silently omitted — and a section missing from the output otherwise reads exactly like a section the guideline never had.

{{seam:worktree-setup}}

---

## Phase 1: Plan

### Adopt an existing breakdown if there is one

If the request names a file in `tasks/`, or `clerk prepare` reported a `resume`, read that breakdown, present the task list with `clerk status`, and skip decomposition. Tasks with `done: true` in the sidecar are finished — `clerk next` resumes at the first unblocked one that is not.

**Do not decompose a story that already has a breakdown in progress.** A second decomposition produces a different task list against the same code, and the sidecar recording what was already built no longer describes it. `clerk status` tells you where the previous run stopped.

A breakdown written before sidecars existed has no `tasks/<story>.json`, and `clerk next` refuses without one rather than guessing at dependencies. Recover it — and if it carries an old `- [x]` checklist, the recovery seeds `done` from those ticks so the run resumes where it left off:

```
clerk sidecar          # reads the `### Task N:` sections and their `**Depends on:**` lines
```

It prints what it extracted. **Check those dependencies against the breakdown before relying on them** — a misread edge reorders the work silently, which is the one thing this file is the source of truth for. If the breakdown has only a checklist and no task sections, it says so and leaves every `depends_on` empty; that is safe here, since a breakdown is emitted in dependency order and this skill runs one task at a time. Commit the sidecar alongside the breakdown it describes.

### Otherwise decompose

{{seam:decompose}}

It does the codebase exploration and dependency analysis that makes the task list worth having. It writes `tasks/[story-name].md` describing each task, and `tasks/[story-name].json` beside it — the sidecar that carries the dependency graph and the run's progress. The sidecar is the durable record; the markdown is prose and nothing rewrites it.

**Carry the learnings forward.** Pass the learnings file's contents as `Accumulated project learnings`: "These are durable conventions, recurring review findings and constraints from earlier runs in this repo. Fold the relevant ones into each task's `patterns_to_follow`, and do not re-propose work they already cover."

**Pass the guidelines** as `Required Reading` — the text `clerk guidelines` printed you, not a list of paths to go and fetch. Add: "The unit-of-behavior section is the one to decide each task against: whether it delivers independently testable behaviour, or is only meaningful through a downstream consumer."

**One judgment call.** Decomposition costs a full agent (~15 minutes measured). Work that is obviously a single slice does not need it — say so and go straight to building. Anything with more than one deliverable, real dependencies, or an unclear surface gets decomposed.

### Check the plan's evidence

```
clerk lint --rule certainty-unevidenced <the sidecar the decomposition wrote>
```

Seconds, no agent, and it settles the one thing about an assessment that is not a matter of opinion: a task called `high` or `medium` certainty with no precedent named, or one citing a file that is not there. Both mean the same thing — a confidence with nothing behind it, which is how the field drifts to `high` on everything and stops being worth reading.

Pass the sidecar's path; the rule reads the plan rather than the diff, so it is not in what `--staged` would find. Fix a finding by correcting the assessment, not by deleting the reference: a precedent you cannot produce is a task that is `low`.

Run it on an adopted breakdown too, which costs the same and tells you whether the plan you are about to build was checked when it was written.

### Present the plan, then build

Show the task list, in order, with dependencies, **each task with its certainty and blast radius** — then start. **The plan is not a gate.**

Those two columns are the cheapest review the plan ever gets. A task the decomposition called routine that the user knows is not costs them one sentence to say so here, and costs a whole run to find out from the code. Say which tasks would pause were `gears` on, so that sentence can be "turn gears on" rather than a description of what to watch for.

That follows from what this skill is for. Its whole claim is that at minutes per feature, building a version and looking at it is a cheaper way to find out whether a requirement is right than arguing about a task breakdown; stopping to debate the breakdown spends the advantage the speed was bought for. The branch is disposable, the audit reads the finished code against the request rather than against the plan, and a decomposition that turns out wrong costs one short run rather than a negotiation.

**With `review_plan` on, it is a gate:**
- Show the plan and ask the user to approve or request changes.
- On changes, re-spawn the decompose agent with the feedback and present the revised plan. Repeat.
- Do not write code until the plan is explicitly approved.

Reach for it when the decomposition is the expensive part rather than the code — a migration whose slicing decides how reviewable the result is, work whose surface you are unsure of, anything where being wrong costs more than one run.

Do not pass it to a run nobody is watching. A launcher firing a wave of deliverables in parallel wants each one building, not each one holding a plan up to an empty pane.

---

## Phase 2: Build, task by task

**You write the code for every task.** Review happens once, over the finished branch, in Phase 3 — so nothing here waits on a reviewer.

### The loop

```
clerk next
```

Returns the first task whose `depends_on` are all done, plus how many remain and how many are blocked. It **exits 3 while the tree is dirty**, because one task in flight at a time is what keeps a run resumable — a half-finished task on top of another is what makes a run impossible to review. Commit the current one before asking for the next.

Announce which task you are starting, **with its `certainty` and `blast_radius`** — both come back on the task object — so the queue's progress is visible in the transcript rather than only in the file, and so a reader can tell a task built fast because it was routine from one built fast because nobody looked.

If a task turns out to be unnecessary or wrong once you are in the code, **stop and say so**. The plan is the shared contract; revise it with the user rather than quietly building something else.

### 1. Tests first, where they apply

Derive scenarios from the acceptance criteria and the caller pattern you loaded. Write the tests, watch them fail for the reason they name, then implement until they pass.

For a task whose evidence is "the existing suite still passes unchanged" — a pure move or rename — **do not add tests**. A new test there asserts behaviour the suite already covers.

**With `gears` on, a hard task stops here** — tests written, run red, nothing implemented. A task qualifies when its `certainty` is `low`, when its `blast_radius` is `high`, or when the run has downshifted (step 5).

Here, and not at the commit, because the tests are where the theory lives. Everything the task believes about the behaviour is in them before a line of implementation exists, so this is the last moment at which being wrong costs only the tests — and the first at which it is legible, since a red test states an expectation in one line where a diff makes a reader infer it. Show what each test asserts, one line each, not the file: someone checking whether you understood the requirement should not have to read scaffolding to find out.

Name which of the two stopped you, because they ask for different reads. Low certainty asks *is this the right behaviour*. High blast radius asks *is this enough of it* — the tests may be right about everything they cover and the gap be what costs.

Then follow the stopping convention in step 5: state what you would do next and stop, rather than asking and waiting. Someone watching answers and you carry on; nobody watching gets a window that ends on the question instead of a pane parked on it.

### 2. Implement

Follow the guidelines you loaded, and the surrounding code where the guidelines are silent. Keep the change to what the task asked for: structure work that reaches beyond the task's own diff belongs to a deliberate pass, not smuggled in here.

### 3. Prove it, don't narrate it

Run the task's test command and **read the output**. Having written the code is not evidence that it works, and "tests pass" asserted without a run is the claim that costs most when it turns out to be false.

Four checks earlier runs paid for, each of which shipped a defect that a passing suite did not catch:

- **A new guard must be shown to fail.** Inject the violation it claims to catch, watch it fail, revert the injection. A test that cannot fail is worse than no test, because it reads as coverage. **Revert from a copy, never with `git checkout`** — before the task is committed, HEAD is the tree *without* this feature, so restoring a tracked file to it erases the work rather than the injection. Copy the file to the scratchpad first and put it back with `/bin/cp -f`, or commit before mutating. One run's mutation loop ended each case with `git checkout -- <dir>` and wiped a finished task in a second; the remaining cases then printed `ok … [no tests to run]`, which reads like a caught mutation rather than an emptied tree.
- **An absence assertion needs a positive partner.** `expect(x).toBeNull()` on an attribute nothing sets passes when the whole feature is deleted.
- **Moving code can silently invert a source-scanning test.** A test that locates code with `readFileSync` plus `indexOf`/`substring` bounds starts scanning nothing when the bounds cross, and passes forever.
- **Look at UI in a browser.** CSS and layout defects are invisible to a green suite. Run the app, open the page, look at it.

### 4. Commit the task

```
clerk finish <n> -- <every file this task changed>
```

Then check the staged set against the conventions that decide without judgment:

```
clerk lint --staged
```

It reports comments that name code by its plan position or cite a ticket, sibling tests that belong under one umbrella, and a method living apart from the file declaring its type. Each is a rule from the guidelines you already read, and each is settled by looking rather than weighing — so a finding here is a defect, not an opinion to argue with. Fix it and `git add` the file again; do not re-run `clerk finish`, which refuses a task already done.

Run it here rather than leaving it to review. The audit will raise these anyway, and there it costs a lens to find, a verifier to confirm, and a `--fixup` rebase to fold the fix back into the commit that introduced it — against seconds now, while you are still holding the code in mind. If a finding is genuinely wrong, that is a bug in the rule: say so, and fix the rule rather than working around it.

`clerk finish` sets `done: true` on the task in the sidecar and stages it alongside those paths, so the progress record and the change it stands for land in one commit. The sidecar is the only place completion is recorded; the breakdown is prose, and is not rewritten. `clerk status` prints progress when you want to read it. A sidecar committed without its code makes a later run skip work it never did; code committed without the sidecar makes it redo work. `clerk finish` refuses a path that does not exist and refuses a task already done, and it never runs `git add -A` — an unrelated file left loose in the tree would otherwise be swept into your commit, and untangling that later means rewriting history.

Then write the message, which is judgment rather than mechanics:

{{seam:commit}}

The message obeys the `commit` agent's rules: imperative subject, ≤50 chars, capitalised, no trailing period, blank line before a body wrapped at 72 explaining **what and why**; no AI/Claude mention, no `Co-Authored-By`, no generated-with footer, no generic file lists. Apply the repo's own conventions too — read the project's instructions file and any committing guideline, and reuse a cached trailer (e.g. a Linear initiative trailer) if the repo uses one.

Two rules `clerk` cannot enforce for you:

- **One commit per task**, preserving granularity.
- **One concern per commit.** If a task produced both a behaviour-preserving restructure and a feature, land the restructure first as its own commit, then the feature on top. That ordering also lets you prove the restructure by running the *pre-existing* tests against it alone.

### 5. Report and continue

Tick the acceptance criteria you actually walked in this task's section of the breakdown — that is the only per-criterion evidence a reviewer of the finished branch gets, and `clerk finish` stages the file for you once you have edited it. `clerk status` counts them and flags any task marked done that still carries an unwalked criterion; it never gates on that, because whether a criterion is genuinely met is your judgment rather than a box count.

Say what landed in one or two lines and go back to `clerk next`. **Write those lines for someone reading the whole window afterwards rather than watching it arrive** — this run may be one of a wave firing in parallel, and the only reader may be someone scrolling back hours later.

**Then read the task back for the two signals that the plan was wrong about it.** Both are things you have just observed, and both mean the same thing — the theory is not landing where the plan said it would:

- **The implementation needed more than one attempt to go green**, for a reason other than a typo or a missing import. Not the count itself: the fact that the first shape you reached for was the wrong one.
- **`clerk lint --staged` returned a finding.** The guidelines were loaded and still not followed, which is them not landing rather than a rule being obscure.

**Report either in the task's line whatever `gears` says.** It is a fact about the run, and it is exactly what someone deciding whether to trust the branch wants and cannot recover from the diff.

**With `gears` on, either one downshifts the run**: every task from here pauses after its tests, the way a low-certainty task does, regardless of what the plan assessed it as. It upshifts again after two consecutive tasks go green first try with a clean lint — say so when it does.

The upshift is not a courtesy. A run that only ever slows down finishes every story at its slowest, and a pause that arrives on every task carries no information — which is how a gate becomes a keystroke someone acknowledges without reading, and how the flag stops buying anything at all.

Stop and ask only when something genuinely needs a decision, and when you do, **state the decision and stop** rather than asking and waiting. Leave the branch where it is and say what you would need to continue. Either way, do not guess your way past a decision to keep the run moving.

---

## Phase 3: Audit, validate, close

### 1. Full suite

Run the `default` test command **in the tree that holds this run's commits** — `clerk prepare` reported it as `work_tree`. Unless `in_place` was on you are in a worktree, and the main checkout is on the default branch without a line of this feature in it; a suite run there tests the wrong tree and passes for the wrong reason.

Then record it:

```
clerk receipt --command "<the command you ran>" --passed --output-file <captured output>
```

The receipt is bound to the SHA it describes. That is what lets the gate in step 6 refuse a green taken before later changes, which is otherwise indistinguishable from a green taken after them.

### 2. Hand the branch to `audit-implement`

This is where review happens.

{{seam:audit}}

**Nothing else may touch this tree while the audit is in flight.** Its verifiers prove claims by mutating the working tree — reverting a line to check a test still fails, writing a probe file, deleting it again. That is the substitution test doing its job, and it is why the test-integrity lens is worth having. It also means any command you run against the same tree concurrently is reading a tree mid-experiment: a suite that fails because a probe file vanished under it has told you nothing, and reporting that run either way would be false. Start the audit *after* step 1's suite has finished and its receipt is written, then wait.

When it returns, check `git status --porcelain` before running anything. A verifier that died mid-probe leaves residue behind; restore the tree to the branch tip before you trust another run.

Pass it the base ref the work started from, the `test_commands` map, a one-or-two-sentence `brief` on what the feature was meant to do, and `story` — the request, **verbatim and unsummarized**. Do the last one even though you also wrote the brief: the brief is your paraphrase, and if you misread the request the brief encodes the misreading and every lens inherits it. The story is the only thing the audit sees that did not come from you.

**When the request names a breakdown, that is not the story.** A run given `tasks/<story>.md` is being handed a decomposition, and a decomposition came from you — pass the user story it was written from instead, and the breakdown only as well. Handing over the breakdown alone defeats the whole point of the field: a task list that quietly narrowed a criterion is checked against itself, and every lens agrees it is covered. One run passed its breakdown as the story and three adversarial rounds confirmed a set of eight constructs that the story stated as a category of nine.

It fans the applicable lenses over the diff in parallel, reproduces every runtime claim before it counts, and returns ranked findings plus `coverage_gaps`.

**Read `coverage_gaps` and `lenses_not_run` first** — what the audit could not judge is more actionable than what it could. Then work the findings; each carries evidence you can re-run. Skim the refuted list: a wrongly-refuted finding is this shape's failure mode, and the verifier is instructed to refute when uncertain.

**What arrives through the gaps has not been through the gate.** A finding is reproduced before it counts. `coverage_gaps`, `lenses_not_run` and `lens_notes` are the opposite channel — what a lens noticed in passing and was not authorised to judge — and nothing in the audit checked any of it. Treat every claim there as a hypothesis: reproduce it yourself before you act on it, before you put it in your summary, and before you write it into the learnings. One run took a lens's passing note that a documented flag was being discarded by the CLI framework, never ran the command, told the user all four documented invocations were silently broken, and committed that to the learnings file where every later run in the repo would read it. The flag worked exactly as documented.

**A gap that survives a round is yours to close.** Each lens owns changed source files under a language it knows, so a diff's documentation, its fixtures and its breakdown are owned by nobody and come back unreviewed however many rounds you run. The second time you read the same gap, the audit is telling you it will never cover that ground: open those files yourself and run whatever they document, or say in your summary that they went unreviewed. One run had three rounds return an identical `lenses_not_run` naming a README, two docs pages and the breakdown — five files, a third of the branch — and landed without a lens ever reading them.

Fix findings **directly**. Do not launch a workflow to apply them — you have the context and they are usually small.

**Fold each fix into the commit that introduced the defect.** A finding is almost always a defect in one task's work, and the honest place for the correction is that task's commit. Collecting every fix into one trailing "address audit findings" commit leaves the branch reading as though each task was right when it landed and something unnamed happened afterwards, which is the opposite of what occurred.

Mark each fix for the commit it corrects:

```
clerk fixup -- <only the files this fix touched>
```

It finds the commits in `<base>..HEAD` that touch those files, stages them and commits the `fixup!`. Where a file has one commit in range there is nothing to weigh and it just does it.

**A repo whose commit-msg hook rejects `fixup!` subjects still gets the fold.** The marker goes in over a commit the hook accepted — the target's own message — and only the amend that installs it skips the check, so a pre-commit hook still runs over the content and a real objection to the fix still stops everything. The reply says `commit_msg_hook_bypassed` when that happened, which is worth reading: until the replay, the branch carries a subject this repo refuses, so do not push one that has not folded.

**Where there is something to weigh, it refuses and hands you the list.** A file touched by several tasks — a catalog, a shared type, a snapshot — names the last task that edited it, which is not necessarily the one that introduced what the audit found. Read the finding's evidence, then name the commit yourself with `--onto <sha>`. It also refuses, separately, when your files' targets are unambiguous but *different*: run it once per group so each correction lands where it belongs.

When every fix is marked, replay once:

```
clerk fixup --replay
```

This is also what keeps `clerk verify` meaningful rather than noisy. Its commit-boundary check counts how many commits in the branch touch each task's recorded files and warns when the answer is more than one — so a trailing commit that fixes something in task 3's file trips that check by construction, and you would be reading a warning you caused on purpose. Folded, each task's commit stays the whole of that task.

**Fold only what folds cleanly, and it stops rather than forcing it.** A conflicted replay is aborted and the branch left exactly as it was — keep the fix as its own commit there, saying why in the message, because untangling a conflicted replay of your own branch costs more than the tidier history is worth. A range with commits already pushed is refused for the same reason: rewriting it would rewrite history someone else may have, and `--force` is you asserting the branch is yours alone. And a file no commit in range touches is reported as new work rather than a correction, which also wants its own commit.

**Do this before the receipt, not after.** The replay rewrites every SHA from the target commit onward, and a receipt is bound to the SHA it describes; one recorded before the fold describes commits that no longer exist.

**Then re-run the suite and record a new receipt.** Step 1's receipt describes a tree that no longer exists. This is the one place in the skill where code changes land after the last green, which is exactly the vacuous-receipt shape the audit itself hunts for. If you changed nothing, say so and keep the existing receipt.

**Then re-audit, and always pass `recheck`.** Every finding carries the `lens` that raised it. Re-invoke `audit-implement` with `recheck` set to the findings you fixed, plus the same `brief` and `story`. Narrow `lenses` to the raising keys only when every fix was a quality fix — a comment removed, a redundant test folded, a name changed — since those cannot break what another lens owns. That costs the scope pass and those lenses, and skips Verify and Report altogether when nothing is raised.

**A fix that changes a code path needs the whole panel**, because the lens that raised the original finding is not watching for what the fix broke. Expect this to be the common case rather than the exception: most rounds you will pay for the full fan-out, and a round is roughly as expensive as the one before it.

**So say how many rounds you are running before you start the first, and stop there.** Nothing in a round's output tells you whether another would find more, and the rounds do not converge on their own. One run went 7 → 7 → 5 findings over three full rounds, never re-raised a single finding, and turned up fresh medium-severity ones every time — the third round is where it found that the story's headline criterion was unguarded. Two rounds is a reasonable default; three is defensible for behaviour that is hard to see, such as anything rendered. What is not defensible is stopping because the last round felt quiet. Name the last round as the last one and say why, so the user is reading a decision rather than a coincidence — and say what the next round would most likely have looked at.

If the fixes were trivial and confined — a typo, a single call site — skip the re-audit; the post-fix receipt is the evidence that matters.

### 3. Validate against the story

The audit checked whether the code is correct and whether it matches the brief. Neither it nor the verifier checked whether the branch delivers **what you were asked for** — every criterion it was judged against came from a decomposition written from the request rather than from the request itself. This is the only step that reads the request, so it is the only place a decomposition that quietly narrowed the story is caught.

This costs a read, not an agent, because you are already here. Re-read the request **verbatim, from the record you made in Phase 0** — not your memory of it, and not the brief you wrote from it — then read `git log --oneline` and the branch diff, and answer four questions:

- What does the story ask for that this branch does not do?
- Where does the branch satisfy a task's acceptance criteria by measuring a **proxy** for what was asked rather than the thing itself?
- Where did a criterion that the story stated as a category — "any construct", "each format", "all four patterns" — become a list in the breakdown? Check the list against the source that defines the set, not against the story's examples. The audit cannot catch this: every lens owns changed source files, the breakdown is owned by none, and each lens judges intent from the diff and your brief rather than from the story.
- Which test fails when a criterion is violated? Name one per criterion, and for whatever the story states as its headline, make that test fail — the same injection Phase 2 asks for, against the finished branch. A criterion can be fully delivered and completely unguarded at once, and that pair is invisible to every question above: the feature works when you run it, the suite is green, and nothing would notice if it stopped working. One run's headline criterion was that each card is drawn under the slice that states it. Swapping two cards' positions left the entire repository green, and an audit round caught it only after the branch was otherwise finished.

Quote the story's own words for anything you raise; if you cannot point at the phrase, you are inventing a requirement. Put mismatches to the user as questions and let them decide — you wrote this code, which makes you the worst-placed reader of your own interpretation of the request. Finding nothing is the common result; say so in a line.

Do this **before** integrating, on the runs where you integrate at all: a mismatch found after the fast-forward is a mismatch found too late.

### 4. Write down the theory

You are the last reader of this branch who understands it without reading it. Everything that made the design what it is — the alternative you rejected in task 2, the constraint that forced the shape of task 5 — is in your context and in no file. Whoever reviews the branch has the diff and nothing else, and reconstructing a theory from a diff is a different and far more expensive job than checking a diff against one.

That gap is the cost of this shape. Construction stays undelegated because it is fast; the price is that nobody watched it happen, and on a wave of deliverables the reviewer may be reading it hours later with four other branches open.

So append a **`## Theory`** section to the breakdown, above `## Tasks`. Five sentences at most:

- The key abstractions this branch adds or changes, **named**, with where they live.
- The design decision that was not forced — and the alternative you did not take.
- What a reviewer should check hardest, and why that is the part most likely to be wrong.

Write it for someone who has not read the story. No task numbers, no "as planned in task 3", no narration of the run — a reviewer reading it in a pull request has none of that, and a reference they cannot resolve reads as something they are missing. `clerk stack --create` lifts this section into the PR body verbatim, between the deliverable's Story Reference and its Boundaries, so it is the first thing read and the diff is checked against it.

**Commit it when the breakdown is tracked**, as its own commit — it describes the branch rather than any one task, and `clerk land` needs a clean tree. Where the repo gitignores `tasks/` there is nothing to commit and the file simply sits in the main checkout, which is where `clerk stack` reads it from.

**Do this even when you found the run boring.** A run with nothing surprising in it is exactly the one whose theory nobody will think to ask about, and the one whose reviewer will therefore skim.

### 5. Verify the run

```
clerk verify --all-closed
```

Staged-but-uncommitted tails, a vacuous or stale receipt, new exported symbols with no non-test caller, and commit-boundary arithmetic against the file lists `clerk finish` recorded. It reports what it could **not** check in `not_checked` rather than passing over it silently.

{{seam:verify}}

### 6. Close out and land

```
clerk land                    # archive the breakdown; integrate if the repo says so
clerk land --integrate        # …and put it on the default branch regardless
clerk land --no-integrate     # …and leave the branch standing regardless
```

`land` runs the gate first and refuses if it does not open: every task checked off, the tree clean, a passing receipt **at the current HEAD**, and `--audit-accepted` asserted once the audit's findings are fixed or the user has accepted them. That last one is judgment, so it is asserted rather than inferred — without it the gate simply stays shut.

It archives the breakdown to `tasks/completed/` **on the feature branch, before any integration**, so the archive commit rides with the work it belongs to rather than landing on the default branch behind it. That order is also the only one that works: `git mv` leaves a dirty tree and a dirty tree blocks the rebase.

**Integration is opt-in, and `land` resolves that itself** — bare `clerk land` reads the repo's `integrate` setting, so pass a flag only to overrule it. With integration off the work stays on its branch and you hand it over, naming the branch and the one command that lands it. That default is not timidity: landing is the one irreversible step here and its inputs are all things you assessed about your own work. A branch left standing costs one `merge --ff-only` later; a bad fast-forward costs a history rewrite.

A repo that sets `integrate: true` has decided that trade for itself, and `land` reports `integrate_source` either way so the decision is never anonymous. **The stronger your doubt about the work, the more that setting is the wrong one to inherit silently** — `--no-integrate` overrules it for one run, and a branch handed over is the cheap outcome to be wrong about.

With `--integrate` it rebases onto the default branch, and **stops if the rebase actually replayed commits onto a moved base** — green-before-rebase is not green-after, so it returns exit 3 and asks for a fresh suite run and receipt before it will fast-forward. On conflict it aborts the rebase and leaves the branch exactly as it was; do not resolve someone else's merge for them. It never pushes.

{{seam:worktree-teardown}}

### 7. Reflect and persist learnings

Distil what generalises: a codebase convention, a recurring finding, a constraint, a reusable pattern. **Falsifiable filter** — keep a candidate only if you can name in one sentence the specific future mistake it prevents. Otherwise it is noise.

**Include what step 3 turned up.** Audit findings and diffs only ever teach implementation conventions. A story mismatch — a criterion that measured a proxy, a task boundary drawn in the wrong place, an assumption the story made that the codebase contradicts — teaches how a story in this repo gets *decomposed* wrong, and the next run reads this file while planning, before any code exists. That is the more valuable class; write it so a planner can act on it. It is exempt from wanting two observations, not from the falsifiable filter.

**And include where the plan mis-read the work.** Three observations from this run say the decomposition, not the code, was wrong, and all three are only visible from here:

- **A task the plan called high certainty that took several attempts to get right**, or arrived with a lint finding. Whatever the plan thought made it routine, does not.
- **A task the plan called low certainty that was boring.** This one is worth as much and gets recorded far less, because nothing went wrong to prompt it. Left unwritten, the next story over the same ground pauses on it again for nothing, and the pause keeps costing until someone notices.
- **A `clerk fixup` that came back `ambiguous`** in step 2. Several commits in range touched one file, which is a task boundary drawn across something the codebase treats as one thing.

Each is a fact about *this repo's* work rather than about this story, which is what makes it worth a durable line. Write it so the next decomposition can act on it: name the kind of task, not the task.

Dedup against the learnings file on substance, not wording.

**Write what survives the filter, then show what you appended.** Nothing here waits on approval — the filter is the quality bar, and a learning that turns out to be wrong is cheaper to delete later than one that was never recorded.

```
clerk learn --list          # what is already recorded, to dedup against
clerk learn --type convention --title "<short title>" \
            --learning "<the durable fact, 1–2 sentences>" \
            --apply-when "<the future situation where this is relevant>" \
            --task 3 --feature "<feature name>"
```

`--type` is one of `convention`, `recurring-finding`, `constraint`, `pattern`. Pass `--path` when this run was given its own learnings file; otherwise it writes to the one `clerk prepare` resolved, **which hangs off the repo root and not the worktree you are standing in** — hand-resolving it from here writes a file the next run will never read.

**Dedup is still yours.** It refuses an exact title collision, and that is the whole of what a script can settle; matching on substance is judgment, which is what `--list` is for. `--replace` folds new wording into an entry that already exists.

A clean run produces no learnings, and that is fine — say so rather than manufacturing one to fill the section.

**Committing is a decision; writing is not.** `in_tree` in the output says which regime you are in. When it is true the file is part of the repo's history: offer to commit so teammates inherit it — writing changes what your next run reads, committing changes what everyone's does — and when you leave it uncommitted, say so, because the next run in this repo finds the tree dirty and stops to ask about a file this one left there.

Reflect comes **last** because it leaves that file modified and uncommitted by design, and a dirty tracked file blocks a rebase.

---

{{include:shared/injection.md}}

## Error Handling

| Scenario | Action |
|---|---|
| Dirty tree at start | Stop; ask the user to stash or commit. Never build on top of someone else's loose work. |
| `clerk` not installed | Stop and say so. Its resolutions have precedence rules that are easy to execute wrongly and silently. |
| `clerk next` exits 3 | A task is in flight. Commit it, or discard it deliberately — do not pass `--allow-dirty` to get past your own unfinished work. |
| `clerk guidelines` prints a "Not loaded" section | A guideline has been reorganised out from under its slot, or a language has no guideline set. Read the headings it lists and load what you need by hand — do not proceed as though the section did not exist. |
| `clerk fixup` exits 3 as `ambiguous` | Several commits in range touch the file. Read the finding's evidence for which one the defect came in with, then pass it as `--onto`. Do not take the newest to get moving. |
| `clerk fixup` exits 3 as `spans-commits` | The files belong to different task commits. Run it once per group it printed. |
| `clerk fixup --replay` refuses or aborts | A conflict, a dirty tree, or a range already pushed. Keep the fix as its own commit and say why in the message — the branch is exactly as it was. |
| `clerk fixup` exits 3 saying a hook rewrote the subject | A `prepare-commit-msg` hook prepends to every message here, so no `fixup!` marker survives and the replay would fold nothing. The commit it made is undone and the fix is staged: keep it as its own commit, naming the commit it corrects. |
| `clerk learn` exits 3 on a repeated title | That title is already recorded. Read it with `--list` and decide on substance: fold your wording in with `--replace`, or give this one its own title. |
| `clerk land` reports the gate shut | Read which predicate failed; each names its own evidence. Fix that, do not work around it. |
| `clerk land --integrate` exits 3 after a rebase | The base moved and the receipt is stale. Re-run the suite, record it, run it again. |
| Rebase conflicts at integrate | Left aborted and the branch untouched. Hand it over; do not resolve someone else's merge for them. |
| `decompose-to-tasks` fails or returns nothing | Retry once. Then decompose yourself and show the user the list you wrote, flagging that it skipped the codebase-exploration pass. |
| `clerk lint --rule certainty-unevidenced` reports a task | The assessment has no evidence behind it. Correct the assessment — a precedent nobody can produce is a task that is `low`. Do not delete the reference to silence it. |
| A task turns out to be wrong or unnecessary once you are in the code | Stop and say so. The plan is the shared contract; revise it with the user rather than silently building something else. |
| The breakdown carries no `certainty` or `blast_radius` | It was planned before those fields existed; `clerk status` lists the tasks under `gears.unassessed`. Read them as medium and low, and say you did — do not go back and re-decompose a run in progress to acquire them. |
| A task's assessment is obviously wrong once you are in the code | Say so and drive on what you found, not on what the plan said — a `high` that is plainly `low` is a reason to slow down even with `gears` off. Record it in step 7; it is a fact about how this repo gets planned wrong. |
| `gears` is on and nobody answers a pause | The run stops there, which is what the flag was turned on for. Leave the branch as it is. Do not turn `gears` off mid-run to get past your own gate. |
| Tests will not go green | Report the real failure output. Do not weaken the test to pass, and do not commit red. |
| `audit-implement` returns findings you disagree with | Say which and why. It refutes when uncertain, so a survivor is usually real — but you have context the lenses do not. |
| `clerk verify` reports a block | Fix it before calling the feature done. |

{{seam:error-handling-extra}}
