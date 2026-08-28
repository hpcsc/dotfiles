## Implementation notes

This skill spawns subagents with the Agent tool and the Skill tool: `decompose-to-tasks` for planning, the commit skill for each task's message, `run-verifier` for the judgment residue after `clerk verify`, and — through `audit-implement` — the review lenses. Everything else is your own work, which is the point.
