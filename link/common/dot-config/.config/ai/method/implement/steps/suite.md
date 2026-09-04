## Run the full suite

Run the `default` test command **in the tree that holds this run's commits** — `facts` reports it as `build_tree`. Unless `in_place` was on you are in a worktree, and the main checkout is on the default branch without a line of this feature in it; a suite run there tests the wrong tree and passes for the wrong reason.

**Capture the output to a file, and write the exit code into it**, because the receipt is refused without both:

```
<the command> 2>&1 | tee /tmp/suite.log; echo "clerk_exit=${PIPESTATUS[0]}" >> /tmp/suite.log
```

Then record it:

```
clerk receipt --command "<the command you ran>" --passed --output-file /tmp/suite.log
```

`--output-file` is required. A receipt is a claim that the suite passed at this code tree, and without the output there is nothing behind the claim — so `clerk receipt` refuses a missing or empty file, one written before the commit it says it describes, and a `clerk_exit=` that contradicts `--passed`. That last one is why the exit code goes in the file: it moves pass and fail from something you report to something the run recorded.

Read the output yourself as well. The receipt checks that a green was possible, not that the branch is right.

The receipt is bound to the code tree it describes. That is what lets `clerk land` refuse a green taken before later changes, which is otherwise indistinguishable from a green taken after them — while a commit touching only `tasks/` leaves it standing, because the code it ran against did not move.
