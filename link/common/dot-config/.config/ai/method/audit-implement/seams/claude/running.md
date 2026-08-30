**It takes longer than a tool call may.** Run it with `run_in_background: true` — a
foreground Bash call is capped well below a round's wall clock, and a killed round leaves
the phase it was in half-recorded. Read its output as it goes; `clerk audit run --quiet`
if you only want the phase results.

A round already in flight for this branch is continued rather than restarted; pass
`--restart` to throw it away and begin again.
