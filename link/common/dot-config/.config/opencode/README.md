# Opencode Configuration

## How It Works

Opencode reuses Claude Code's skills and agents with thin wrappers.

```
~/.claude/skills/          <-- Shared skill definitions (SKILL.md)
~/.config/opencode/
  commands/                <-- Thin wrappers that reference Claude skills
  agents/                  <-- Duplicated from Claude agents (different frontmatter)
  AGENTS.md                <-- System prompt (tooling guidelines)
  opencode.json            <-- Permissions and theme
```

### Skills → Commands

Claude skills live in `~/.claude/skills/<name>/SKILL.md`. User-invocable skills get a thin opencode command wrapper:

```
~/.config/opencode/commands/commit.md
```
```markdown
---
description: Create a git commit for staged changes
---

@~/.claude/skills/commit/SKILL.md
```

The command just includes the Claude skill via `@` reference. No duplication of skill logic.

### Agents

Agents are duplicated because opencode uses different frontmatter (`mode: subagent`) than Claude Code (`name`, `tools`, `model`, `color`). The agent body is identical.

| Claude Code | Opencode |
|---|---|
| `~/.claude/agents/commit.md` | `~/.config/opencode/agents/commit.md` |
| Frontmatter: `name`, `tools`, `model`, `color` | Frontmatter: `description`, `mode: subagent` |

### Guidelines

Both tools read shared guidelines from `~/.config/ai/guidelines/`. No duplication needed.

## Commands (user-invocable)

| Command | Description | Wraps |
|---|---|---|
| `/commit` | Commit staged changes | `~/.claude/skills/commit/SKILL.md` |
| `/implement` | Implement a feature with quality gates | `~/.claude/skills/implement/SKILL.md` |
| `/tdd` | Test-driven development | `~/.claude/skills/tdd/SKILL.md` |
| `/refactor-go` | Go refactoring with review | `~/.claude/skills/refactor-go/SKILL.md` |
| `/review-go-tests` | Review Go tests | `~/.claude/skills/review-go-tests/SKILL.md` |
| `/implement-go-interface` | Create Go interface test doubles | `~/.claude/skills/implement-go-interface/SKILL.md` |
| `/test-go` | Write Go tests | `~/.claude/skills/test-go/SKILL.md` |

## Agents

| Agent | Description |
|---|---|
| **commit** | Creates commits with well-crafted messages |
| **decompose-to-tasks** | Decomposes stories into ordered tasks |
| **test-case-designer** | Designs test cases from acceptance criteria |
| **go-implementer** | Writes Go tests first, then production code |
| **go-expert** | Senior Go engineer for direct use |
| **semantic-reviewer** | Logic correctness, edge cases, test quality |
| **semantic-go-reviewer** | Same + Go testing guidelines |
| **security-reviewer** | Injection, auth gaps, secret exposure |
| **performance-reviewer** | Timeouts, resource leaks, unbounded ops |
| **concurrency-reviewer** | Shared state, races, deadlocks |
| **concurrency-go-reviewer** | Same + Go concurrency guidelines |
| **go-guidelines-reviewer** | Go naming, architecture, workflow conventions |
| **go-test-reviewer** | Go tests against testing guidelines |
| **test-reviewer** | Tests across all languages |
| **tdd-test-writer** | TDD red phase |
| **tdd-implementer** | TDD green phase |
| **tdd-refactorer** | TDD refactor phase |
| **domain-modeler** | Domain modeling and bounded contexts |
| **event-modeling-expert** | Event-driven system design |
| **solution-architect** | Event sourcing, distributed patterns |
| **cue-expert** | CUE schema validation and testing |

## Syncing Changes

When updating skills or agents:

1. **Skills** — edit `~/.claude/skills/<name>/SKILL.md`. Opencode picks up changes automatically via `@` reference.
2. **User-invocable skills** — if adding a new user-invocable skill, create a thin command wrapper in `~/.config/opencode/commands/<name>.md` that `@`-references the Claude skill.
3. **Agents** — edit both `~/.claude/agents/<name>.md` and `~/.config/opencode/agents/<name>.md`. Keep bodies identical, only frontmatter differs.
4. **Guidelines** — edit `~/.config/ai/guidelines/`. Both tools read from the same path.
