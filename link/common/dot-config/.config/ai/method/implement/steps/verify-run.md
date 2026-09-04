## Verify the run, not the code

`clerk step` runs `clerk verify` when it reaches this step and hands you the result in `verify`: work left staged but uncommitted, a receipt that is missing, stale or hollow, and the commit arithmetic that says whether each task's work stayed in one commit, against the file lists `clerk finish` recorded. It reports what it could **not** check in `not_checked` rather than passing over it silently. A block holds the step until it is fixed.

**Do not run it yourself.** Measured over ten runs it was invoked 53 times, and 33 of those landed before the audit had even been accepted — where a stale receipt is the expected answer rather than a finding. Each call greps the whole diff, so an early one buys a block you already knew about at the price of the real check. Let the step run it at the point its answer can mean something.

{{variant:verify}}

When `not_checked` is reviewed: `clerk step --done verify-run`.

**Then finish the run before you do anything else with the branch.** What follows is two short steps — land or hand over, then write the learnings — and the reply to this one hands you the next. The failure they lose to is not difficulty: measured over six runs, two reached `land` and two reached `learn`, and the other four went straight from a green audit into pushing, PR review and iteration, and never came back. The branch is fine either way. What is lost is the record — and the four runs that skipped it were the four that hit the most mechanical friction, so the ledger under-reports exactly the problems that recur, and the next run in this repo re-learns them from scratch.

Push and open the PR **after** `clerk learn`, not before. Both take a couple of minutes from here and neither survives the context switch.

