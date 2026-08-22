## Phase 2: Build, task by task

**You write the code for every task.** Review happens once, over the finished branch, in Phase 3 — so nothing here waits on a reviewer.

### The loop

`clerk step` returns the task: the first whose `depends_on` are all done, with how many remain and how many are blocked, and — with `gears` on — whether it pauses after its tests. One task in flight at a time is what keeps a run resumable; a task is done when `clerk finish` marked it and its commit left the tree clean, and `clerk step` returns it until then.

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
clerk finish <n> [--retried] -- <every file this task changed>
```

It stages exactly those paths, lints the staged set, and only then sets `done: true` on the task in the sidecar and stages it alongside, so the progress record and the change it stands for land in one commit. **A lint finding refuses the whole step** — exit 1, the findings in the reply, the paths still staged. Each is a rule from the guidelines you already read: a comment that names code by its plan position or cites a ticket, sibling tests that belong under one umbrella, a method living apart from the file declaring its type. Each is settled by looking rather than weighing, so a finding is a defect, not an opinion to argue with: fix it and run the same `clerk finish` again. If a finding is genuinely wrong, that is a bug in the rule — say so, and fix the rule rather than working around it.

Run into it here rather than at review: the audit would raise the same defects, and there each costs a lens to find, a verifier to confirm and a `--fixup` rebase to fold back into the commit that introduced it — against seconds now, while you are still holding the code in mind.

Pass `--retried` when the implementation needed more than one attempt to go green for a reason other than a typo or a missing import — not the count itself, the fact that the first shape you reached for was the wrong one. It is recorded, and with `gears` on it is one of the two signals that downshift the run.

The sidecar is the only place completion is recorded; the breakdown is prose, and is not rewritten. `clerk status` prints progress when you want to read it. A sidecar committed without its code makes a later run skip work it never did; code committed without the sidecar makes it redo work. `clerk finish` refuses a path that does not exist and refuses a task already done, and it never runs `git add -A` — an unrelated file left loose in the tree would otherwise be swept into your commit, and untangling that later means rewriting history.

Then write the message, which is judgment rather than mechanics:

{{seam:commit}}

The message obeys the `commit` agent's rules: imperative subject, ≤50 chars, capitalised, no trailing period, blank line before a body wrapped at 72 explaining **what and why**; no AI/Claude mention, no `Co-Authored-By`, no generated-with footer, no generic file lists. Apply the repo's own conventions too — read the project's instructions file and any committing guideline, and reuse a cached trailer (e.g. a Linear initiative trailer) if the repo uses one.

Two rules `clerk` cannot enforce for you:

- **One commit per task**, preserving granularity.
- **One concern per commit.** If a task produced both a behaviour-preserving restructure and a feature, land the restructure first as its own commit, then the feature on top. That ordering also lets you prove the restructure by running the *pre-existing* tests against it alone.

### 5. Report and continue

Tick the acceptance criteria you actually walked in this task's section of the breakdown — that is the only per-criterion evidence a reviewer of the finished branch gets, and `clerk finish` stages the file for you once you have edited it. `clerk status` counts them and flags any task marked done that still carries an unwalked criterion; it never gates on that, because whether a criterion is genuinely met is your judgment rather than a box count.

Say what landed in one or two lines and call `clerk step`. **Write those lines for someone reading the whole window afterwards rather than watching it arrive** — this run may be one of a wave firing in parallel, and the only reader may be someone scrolling back hours later.

**Then read the task back for the two signals that the plan was wrong about it.** Both are things you have just observed, and both mean the same thing — the theory is not landing where the plan said it would:

- **The implementation needed more than one attempt to go green**, for a reason other than a typo or a missing import. Not the count itself: the fact that the first shape you reached for was the wrong one.
- **`clerk lint --staged` returned a finding.** The guidelines were loaded and still not followed, which is them not landing rather than a rule being obscure.

**Report either in the task's line whatever `gears` says.** It is a fact about the run, and it is exactly what someone deciding whether to trust the branch wants and cannot recover from the diff. Say the first with `--retried` on `clerk finish` as well; the second is a `clerk finish` refusal and is already on the record.

**With `gears` on, either one downshifts the run**: every task from here pauses after its tests, the way a low-certainty task does, regardless of what the plan assessed it as. It upshifts again after two consecutive tasks go green first try with a clean lint — say so when it does. `clerk step` computes the gear from the record and reports it as `gear`; announcing it is yours.

The upshift is not a courtesy. A run that only ever slows down finishes every story at its slowest, and a pause that arrives on every task carries no information — which is how a gate becomes a keystroke someone acknowledges without reading, and how the flag stops buying anything at all.

Stop and ask only when something genuinely needs a decision, and when you do, **state the decision and stop** rather than asking and waiting. Leave the branch where it is and say what you would need to continue. Either way, do not guess your way past a decision to keep the run moving.

