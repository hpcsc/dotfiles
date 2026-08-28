## Implementation notes

This skill spawns subagents via the opencode `task` tool with complete, self-contained prompts: `decompose-to-tasks` for planning, `commit` for commits, `run-verifier` for the judgment residue after `clerk verify`, and — through `audit-implement` — the review lenses. Everything else is your own work, which is the point.
