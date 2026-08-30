Launch it with `clerk audit run` — it holds the phase order, spawns each lens and refuter, and validates every reply against its schema. The `audit-implement` skill is the same command written out, with what each phase does and what the flags mean; read it if you want the detail, but the launch is the command.

Run it with `run_in_background: true`. A round takes fifteen to twenty-five minutes, well past what a foreground Bash call is allowed, and a killed round leaves the phase it was in half-recorded.
