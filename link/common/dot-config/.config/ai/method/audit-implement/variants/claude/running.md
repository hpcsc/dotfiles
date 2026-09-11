**It takes longer than a tool call may.** Run it with `run_in_background: true` — a
foreground Bash call is capped well below a round's wall clock. A round that is killed
keeps every agent that had landed: `clerk audit run` resumes it and spawns only the rest,
`clerk audit status` says whether its runner is still alive, and what ended it is written
to the round's `incidents`.

**The round runs in a process of its own.** The command only relays it, so whatever stops
that command stops the wait and not the round — and Claude Code's low-memory guard stops
background commands on a busy machine. When the command ends without the round's summary,
run `clerk audit wait` in the background: it waits for the same round and ends on its
summary, even one that already ended. `clerk audit stop` ends a round on purpose. Do not
wrap either in `timeout`; it only ends the wait.

**Then wait, and do not end your turn.** The background completion re-invokes you when the round exits. A turn that ends first can only be restarted by the user, and the round landing does not restart it — so do not poll the progress file between checks.

**Say where it can be watched.** Its first two lines are `progress: <path>`, a file in the
run's ledger that gets every phase, every agent and every tool call whatever the console is
set to, and `watch: clerk watch <path>`, the command that draws that file as phases and
agents rather than a scroll. Copy the `watch:` line into your reply as a fenced command, so
the user has something to paste into a split pane beside the session rather than a temp
file to hunt for. `clerk audit status` prints the same `watch` hint before a round is even
launched.

A round already in flight for this branch is continued rather than restarted; pass
`--restart` to throw it away and begin again.
