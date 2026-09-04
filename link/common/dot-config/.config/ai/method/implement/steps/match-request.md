## Match the branch against the request

The audit checked whether the code is correct and whether it matches the brief. Neither it nor the verifier checked whether the branch delivers **what you were asked for** — every criterion it was judged against came from a breakdown written from the request rather than from the request itself. This is the only step that reads the request, so it is the only place a breakdown that quietly narrowed it is caught.

This costs a read, not an agent, because you are already here. Re-read the request **verbatim, from `request` in the step reply** — not your memory of it, and not the brief you wrote from it — then read `git log --oneline` and the branch diff, and answer four questions:

- What does the request ask for that this branch does not do?
- Where does the branch satisfy a task's acceptance criteria by measuring a **proxy** for what was asked rather than the thing itself?
- Where did a criterion that the request stated as a category — "any construct", "each format", "all four patterns" — become a list in the breakdown? Check the list against the source that defines the set, not against the request's examples. The audit cannot catch this: every lens owns changed source files, the breakdown is owned by none, and each lens judges intent from the diff and your brief rather than from the request.
- Which test fails when a criterion is violated? Name one per criterion, and for whatever the request states as its headline, make that test fail — the same injection the build step asks for, against the finished branch. A criterion can be fully delivered and completely unguarded at once, and that pair is invisible to every question above: the feature works when you run it, the suite is green, and nothing would notice if it stopped working. One run's headline criterion was that each card is drawn under the slice that states it. Swapping two cards' positions left the entire repository green, and an audit round caught it only after the branch was otherwise finished.

Quote the request's own words for anything you raise; if you cannot point at the phrase, you are inventing a requirement. Put mismatches to the user as questions and let them decide — you wrote this code, which makes you the worst-placed reader of your own interpretation of the request — and **stop there**, before recording anything. Finding nothing is the common result; say so in a line.

Record it once the reading is done and anything it raised is settled: `clerk step --done match-request`. Clerk holds no state for a mismatch, because the only party who could record one is the party it would constrain; what stops the run is you stopping.

Do this **before** integrating, on the runs where you integrate at all: a mismatch found after the fast-forward is a mismatch found too late.

