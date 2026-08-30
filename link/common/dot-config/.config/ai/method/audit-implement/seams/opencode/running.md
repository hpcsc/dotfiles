**It takes longer than a tool call may.** Run it so a tool timeout cannot kill it — in
the background, polling its output — because a killed round leaves the phase it was in
half-recorded.

**Say where it can be watched.** Its first line is `progress: <path>`, a file in the run's
ledger that gets every phase, every agent and every tool call whatever the console is set
to. Put that path in your reply so the user can `tail -f` it. `clerk audit status` prints
it too, before a round is even launched, and `clerk watch` draws it as phases and agents
rather than a scroll.

A round already in flight for this branch is continued rather than restarted; pass
`--restart` to throw it away and begin again.
