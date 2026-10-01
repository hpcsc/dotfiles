## Check a design change

The run recorded a design change: the code differs from the planned design, and `clerk design note` holds the reason. One agent now judges the change on its merits, before the next task builds on it. A wrong type or a wrong name costs one task to correct here. After the build, it costs every task that uses it.

The reason says why the run left the plan. It does not make the result right, and the planned design was a first guess, so the check judges the code and not the distance from the plan.

### The check

1. **Commit the task first** if `clerk finish` staged it and the commit is not made yet. The check reads the task's commit.
2. **Print the prompt:** `clerk design prompt <id>`. It holds the change, its reason, the commit and the design lens.
3. **Spawn one `semantic-reviewer` agent** with that prompt as its task. One agent, for this one change.
4. **Fix each finding that names a real cost.** Fold each fix into the task's commit, as the audit step does: `clerk fixup mark -- <only the files this fix touched>`, then `clerk fixup replay`. For a finding you do not fix, say why in one line.
5. **Keep the words table** the agent returned: write it to a file in the scratchpad and run `clerk design words --file <file>`. Skip this when it found no word with two meanings and no concept with two words.
6. **Close the step:** `clerk step done design-check <id>`, with `--fixed` when you changed code.

Then report the change, what the check found and what you did, in two lines. Write them for a reader who scrolls back later, not for one who watches.

### What not to do

- **Do not wait for a person.** The check is the reader here. A run that nobody watches must not stop on a design change.
- **Do not argue with the plan instead of the code.** A finding that the code differs from the planned design is not a finding: the design change already says so, and gives the reason.
- **Do not check a change twice.** A later design change gets its own check; this one is closed when you mark it done.
