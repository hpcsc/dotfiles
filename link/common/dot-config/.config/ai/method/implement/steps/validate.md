### 3. Validate against the story

The audit checked whether the code is correct and whether it matches the brief. Neither it nor the verifier checked whether the branch delivers **what you were asked for** — every criterion it was judged against came from a decomposition written from the request rather than from the request itself. This is the only step that reads the request, so it is the only place a decomposition that quietly narrowed the story is caught.

This costs a read, not an agent, because you are already here. Re-read the request **verbatim, from the record you made in Phase 0** — not your memory of it, and not the brief you wrote from it — then read `git log --oneline` and the branch diff, and answer four questions:

- What does the story ask for that this branch does not do?
- Where does the branch satisfy a task's acceptance criteria by measuring a **proxy** for what was asked rather than the thing itself?
- Where did a criterion that the story stated as a category — "any construct", "each format", "all four patterns" — become a list in the breakdown? Check the list against the source that defines the set, not against the story's examples. The audit cannot catch this: every lens owns changed source files, the breakdown is owned by none, and each lens judges intent from the diff and your brief rather than from the story.
- Which test fails when a criterion is violated? Name one per criterion, and for whatever the story states as its headline, make that test fail — the same injection Phase 2 asks for, against the finished branch. A criterion can be fully delivered and completely unguarded at once, and that pair is invisible to every question above: the feature works when you run it, the suite is green, and nothing would notice if it stopped working. One run's headline criterion was that each card is drawn under the slice that states it. Swapping two cards' positions left the entire repository green, and an audit round caught it only after the branch was otherwise finished.

Quote the story's own words for anything you raise; if you cannot point at the phrase, you are inventing a requirement. Put mismatches to the user as questions and let them decide — you wrote this code, which makes you the worst-placed reader of your own interpretation of the request. Finding nothing is the common result; say so in a line.

Record it: `clerk step --done validate`, with `--mismatch "<the story's words>"` once per mismatch. A recorded mismatch parks the run until the user decides; then `clerk step --done validate --resolved`.

Do this **before** integrating, on the runs where you integrate at all: a mismatch found after the fast-forward is a mismatch found too late.

