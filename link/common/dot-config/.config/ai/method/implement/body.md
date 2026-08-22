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

{{include:implement/steps/ground.md}}
{{include:implement/steps/isolate.md}}
---

{{include:implement/steps/plan.md}}
---

{{include:implement/steps/task.md}}
---

{{include:implement/steps/suite.md}}
{{include:implement/steps/audit.md}}
{{include:implement/steps/validate.md}}
{{include:implement/steps/theory.md}}
{{include:implement/steps/verify.md}}
{{include:implement/steps/land.md}}
{{include:implement/steps/learn.md}}
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
