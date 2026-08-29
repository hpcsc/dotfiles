## Phase 0: Ground yourself

{{include:shared/prepare.md}}

### Read the guidelines — yourself

Nothing else hands you the project's rules. Left to yourself you follow the code you can see and miss the rules you cannot, then find out at review — so this is not throat-clearing. Loading them is the price of writing the code yourself, and it is much cheaper than the findings it prevents.

```
clerk guidelines
```

The required reading for the languages it detects, cut to the sections that matter and printed as text. Read what it prints; do not re-fetch any of it.

It emits the whole of `comments.md` and the naming guideline — both short, and the two most often broken by default, since a comment that restates the code, or names it by its position in the breakdown ("task 3", "the new helper") rather than its domain role, is the single most common finding an audit of this work returns. From the long files it takes only what a run must have loaded: "What to Test", the unit-of-behavior section and the assertion section from the language testing guideline, and from `caller-patterns.md` the identification section plus the Quick Reference, along with each file's own section list so you can ask for more.

**Then name your caller pattern.** Which of UI / Inbound / Outbound / Async / Exported API this work has is the one judgment in this step, so it is asked for rather than guessed:

```
clerk guidelines --caller ui        # …or inbound, outbound, async, exported
```

Add `--dom` or `--state` when the task touches the DOM or shared state.

**Read its "Not loaded" section if it prints one.** A guideline that has been reorganised out from under the slot list, or a language with no guideline set at all, is reported there rather than silently omitted — and a section missing from the output otherwise reads exactly like a section the guideline never had.

