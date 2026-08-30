Launch it with `clerk audit run` — it holds the phase order, spawns each lens and refuter, and validates every reply against its schema. The `audit-implement` skill is the same command written out, with what each phase does and what the flags mean; read it if you want the detail, but the launch is the command.

Run it so a tool timeout cannot kill it: a round takes fifteen to twenty-five minutes, and a killed one leaves the phase it was in half-recorded. `--quiet` prints phase results only, which is the easier shape to poll.

Record each round from the report it returns: write it to a file, or pipe it — `clerk audit round --report -` reads stdin.
