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

