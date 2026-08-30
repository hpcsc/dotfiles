**It takes longer than a tool call may.** Run it so a tool timeout cannot kill it — in
the background, polling its output — because a killed round leaves the phase it was in
half-recorded. `clerk audit run --quiet` prints phase results only, which is the easier
shape to poll.

A round already in flight for this branch is continued rather than restarted; pass
`--restart` to throw it away and begin again.
