## Phase 3: Audit, match, close

### 1. Full suite

Run the `default` test command **in the tree that holds this run's commits** — `clerk prepare` reported it as `build_tree`. Unless `in_place` was on you are in a worktree, and the main checkout is on the default branch without a line of this feature in it; a suite run there tests the wrong tree and passes for the wrong reason.

Then record it:

```
clerk receipt --command "<the command you ran>" --passed --output-file <captured output>
```

The receipt is bound to the SHA it describes. That is what lets the gate in step 6 refuse a green taken before later changes, which is otherwise indistinguishable from a green taken after them.

