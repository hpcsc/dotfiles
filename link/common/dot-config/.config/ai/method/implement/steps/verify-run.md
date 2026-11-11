## Verify the run, not the code

`clerk step` runs `clerk verify` when it reaches this step and hands you the result in `verify`: work left staged but uncommitted, a receipt that is missing, stale or hollow, and the commit arithmetic that says whether each task's work stayed in one commit, against the file lists `clerk finish` recorded. It reports what it could **not** check in `not_checked` rather than passing over it silently. A block holds the step until it is fixed.

**Do not run it yourself.** Before the audit is accepted, a stale receipt is the expected answer and not a finding. Let the step run it at the point its answer can mean something.

{{variant:verify}}

When `not_checked` is reviewed: `clerk step done verify-run`.

**Then finish the run before you do anything else with the branch.** What follows is two short steps — land or hand over, then write the learnings — and the reply to this one hands you the next. A run that skips them loses its record, and the next run in this repo learns the same problems again.

Push and open the PR **after** `clerk learn`, not before. Both take a couple of minutes from here and neither survives the context switch.

