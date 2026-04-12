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
| `/commit` | Commit staged changes | `~/.claude/skills/pcommit/SKILL.md` |
| `/pcommit` | Commit via commit agent (alias) | `~/.claude/skills/pcommit/SKILL.md` |
| `/implement` | Implement a feature with quality gates | `~/.claude/skills/implement/SKILL.md` |
| `/tdd` | Test-driven development | `~/.claude/skills/tdd/SKILL.md` |
| `/refactor-go` | Go refactoring with review | `~/.claude/skills/refactor-go/SKILL.md` |
| `/model-events` | Interactive event modeling | `~/.claude/skills/model-events/SKILL.md` |
| `/write-user-story` | Generate user stories for a feature | `~/.claude/skills/write-user-story/SKILL.md` |
| `/decompose-to-tasks` | Decompose story into implementation tasks | `~/.claude/skills/decompose-to-tasks/SKILL.md` |
| `/review-go-tests` | Review Go tests | `~/.claude/skills/review-go-tests/SKILL.md` |
| `/review-go` | Review a Go package against guidelines | `~/.claude/skills/review-go/SKILL.md` |
| `/implement-go-interface` | Create Go interface test doubles | `~/.claude/skills/implement-go-interface/SKILL.md` |
| `/test-go` | Write Go tests | `~/.claude/skills/test-go/SKILL.md` |
| `/write` | Write or edit articles/notes | `~/.claude/skills/write/SKILL.md` |

## Agents

| Agent | Description |
|---|---|
| **commit** | Creates commits with well-crafted messages |
| **decompose-to-tasks** | Decomposes stories into ordered tasks |
| **test-case-designer** | Designs test cases from acceptance criteria |
| **go-implementer** | Writes Go tests first, then production code |
| **go-expert** | Senior Go engineer for direct use |
| **go-refactorer** | Improves Go code structure while keeping tests green |
| **refactorer** | Language-agnostic refactoring agent |
| **semantic-reviewer** | Logic correctness, edge cases, test quality |
| **go-semantic-reviewer** | Same + Go testing guidelines |
| **concurrency-reviewer** | Shared state, races, deadlocks |
| **go-concurrency-reviewer** | Same + Go concurrency guidelines |
| **performance-reviewer** | Missing timeouts, resource leaks, graceful degradation |
| **go-performance-reviewer** | Same + Go performance guidelines |
| **go-guidelines-reviewer** | Go naming, architecture, workflow conventions |
| **go-mutation-reviewer** | Runs go-gremlins mutation testing, surfaces actionable test gaps |
| **security-reviewer** | Injection patterns, authorization gaps, audit trails |
| **go-test-reviewer** | Go tests against testing guidelines |
| **test-reviewer** | Tests across all languages |
| **tdd-test-writer** | TDD red phase |
| **tdd-implementer** | TDD green phase |
| **tdd-refactorer** | TDD refactor phase |
| **domain-modeler** | Domain modeling and bounded contexts |
| **solution-architect** | Event sourcing, distributed patterns |
| **cue-expert** | CUE schema validation and testing |

## Syncing Changes

When updating skills or agents:

1. **Skills** — edit `~/.claude/skills/<name>/SKILL.md`. Opencode picks up changes automatically via `@` reference.
2. **User-invocable skills** — if adding a new user-invocable skill, create a thin command wrapper in `~/.config/opencode/commands/<name>.md` that `@`-references the Claude skill.
3. **Agents** — edit both `~/.claude/agents/<name>.md` and `~/.config/opencode/agents/<name>.md`. Keep bodies identical, only frontmatter differs.
4. **Guidelines** — edit `~/.config/ai/guidelines/`. Both tools read from the same path.
