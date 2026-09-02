**It takes longer than a tool call may.** Run it with `run_in_background: true` — a
foreground Bash call is capped well below a round's wall clock, and a killed round leaves
the phase it was in half-recorded.

**Say where it can be watched.** Its first two lines are `progress: <path>`, a file in the
run's ledger that gets every phase, every agent and every tool call whatever the console is
set to, and `watch: clerk watch <path>`, the command that draws that file as phases and
agents rather than a scroll. Copy the `watch:` line into your reply as a fenced command, so
the user has something to paste into a split pane beside the session rather than a temp
file to hunt for. `clerk audit status` prints the same `watch` hint before a round is even
launched.

A round already in flight for this branch is continued rather than restarted; pass
`--restart` to throw it away and begin again.
