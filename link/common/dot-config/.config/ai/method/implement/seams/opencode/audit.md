Launch it with `clerk audit run` — it holds the phase order, spawns each lens and refuter, and validates every reply against its schema. The `audit-implement` skill is the same command written out, with what each phase does and what the flags mean; read it if you want the detail, but the launch is the command.

Run it so a tool timeout cannot kill it: a round takes fifteen to twenty-five minutes. A round that is killed keeps every agent that had landed: `clerk audit run` resumes it and spawns only the rest, `clerk audit status` says whether its runner is still alive, and what ended it is written to the round's `incidents`. `--quiet` prints phase results only, which is the easier shape to poll.

Its first two lines are `progress: <path>` — a file in the run's ledger carrying every phase, agent and tool call — and `watch: clerk watch <path>`, the command that draws that file as phases and agents and redraws it as they land. **Copy the `watch:` line into your reply as a fenced command**, so the round can be followed from a split pane.

Record each round from the report it returns: write it to a file, or pipe it — `clerk audit round --report -` reads stdin.
