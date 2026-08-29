### 4. Explain the branch to its reviewer

You are the last reader of this branch who understands it without reading it. Everything that made the design what it is — the alternative you rejected in task 2, the constraint that forced the shape of task 5 — is in your context and in no file. Whoever reviews the branch has the diff and nothing else, and reconstructing a theory from a diff is a different and far more expensive job than checking a diff against one.

That gap is the cost of this shape. Construction stays undelegated because it is fast; the price is that nobody watched it happen, and on a wave of deliverables the reviewer may be reading it hours later with four other branches open.

So append a **`## Theory`** section to the breakdown, above `## Tasks`. Five sentences at most:

- The key abstractions this branch adds or changes, **named**, with where they live.
- The design decision that was not forced — and the alternative you did not take.
- What a reviewer should check hardest, and why that is the part most likely to be wrong.

Write it for someone who has not read the story. No task numbers, no "as planned in task 3", no narration of the run — a reviewer reading it in a pull request has none of that, and a reference they cannot resolve reads as something they are missing. `clerk stack --create` lifts this section into the PR body verbatim, between the deliverable's Story Reference and its Boundaries, so it is the first thing read and the diff is checked against it.

**Commit it when the breakdown is tracked**, as its own commit — it describes the branch rather than any one task, and `clerk land` needs a clean tree. Where the repo gitignores `tasks/` there is nothing to commit and the file simply sits in the main checkout, which is where `clerk stack` reads it from.

**Do this even when you found the run boring.** A run with nothing surprising in it is exactly the one whose theory nobody will think to ask about, and the one whose reviewer will therefore skim.

