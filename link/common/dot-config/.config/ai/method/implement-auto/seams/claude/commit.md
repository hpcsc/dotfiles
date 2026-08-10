**CRITICAL**: Do NOT run `git commit` via Bash. You MUST use the Skill tool to invoke a commit skill.

**Detect which skill to use**: Run `test -f .claude/skills/commit/SKILL.md && echo exists || echo missing` (relative to the project root) to check whether a project-level `commit` skill exists. Do NOT speculatively invoke `commit` to see if it works — you must confirm the file exists first.

- **If the output is `exists`**: use the Skill tool to invoke `commit` with the step description and any ticket context from `$ARGUMENTS`.
- **If the output is `missing`**: use the Skill tool to invoke `pcommit` with the step description and any ticket context from `$ARGUMENTS`.
