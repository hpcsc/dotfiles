**It takes longer than a tool call may.** Run it with `run_in_background: true` — a
foreground Bash call is capped well below a round's wall clock, and a killed round leaves
the phase it was in half-recorded.

**Say where it can be watched.** Its first line is `progress: <path>`, a file in the run's
ledger that gets every phase, every agent and every tool call whatever the console is set
to. Put that path in your reply so the user can `tail -f` it rather than hunt for the temp
file the background launch happened to pick. `clerk audit status` prints it too, before a
round is even launched.

A round already in flight for this branch is continued rather than restarted; pass
`--restart` to throw it away and begin again.
