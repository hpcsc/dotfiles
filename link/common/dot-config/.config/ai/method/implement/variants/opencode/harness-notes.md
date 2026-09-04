## Implementation notes

This skill spawns subagents via the opencode `task` tool with complete, self-contained prompts: `decompose-to-tasks` for planning, `commit` for commits, `run-verifier` for what `clerk verify` could not check, and — through `audit-implement` — the review lenses. Everything else is your own work, which is the point.
