**Do NOT run `git commit` via Bash.** Use the Skill tool.

Detect which skill: `test -f .claude/skills/commit/SKILL.md && echo exists || echo missing` (relative to the project root). Confirm the file exists — do not speculatively invoke `commit` to find out.

- `exists` → invoke `commit` with the task description and any ticket context from `$ARGUMENTS`.
- `missing` → invoke `pcommit` (which delegates to the `commit` agent).
