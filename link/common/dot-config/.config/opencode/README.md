# Opencode Configuration

## How It Works

Opencode shares Claude Code's method and guidelines. Where a definition can be read from
Claude's tree it is; where the two tools need different frontmatter or a different idiom,
both files are generated from one source.

```
~/.config/ai/                <-- Shared across tools
  guidelines/                <-- Read by both, referenced not copied
  method/                    <-- Bodies + per-tool variants; both trees generated from here
~/.claude/skills/            <-- Skill definitions most commands read directly
~/.config/opencode/
  commands/                  <-- Thin wrappers naming the skill to read
  agents/                    <-- Subagent definitions
  skills/                    <-- Skills whose opencode form differs from Claude's
  AGENTS.md                  <-- System prompt (tooling guidelines)
  opencode.json              <-- Permissions and theme
```

Directory names are plural. There are no `agent/` or `command/` singular directories.

### Commands → Skills

User-invocable skills get a thin command wrapper naming the file to read:

```
~/.config/opencode/commands/commit.md
```
```markdown
---
description: Create a git commit for staged changes
---

Read ~/.claude/skills/commit/SKILL.md and follow its instructions using $ARGUMENTS.
```

Most wrappers point straight at `~/.claude/skills/`, so there is one copy of the skill.
`implement` and `implement-flow` point at `~/.config/opencode/skills/` instead, because
their opencode form genuinely differs — Claude's `implement-flow` skill is a launcher for
a JS workflow, opencode's is the method itself.

**`$ARGUMENTS` is substituted into the wrapper, not into the skill.** The skill is read as
a file, so any `$ARGUMENTS` inside it stays literal text. Skills that must act on the
caller's exact words say so directly and tell the reader to record the request up front,
rather than depending on a token being replaced.

### Generated definitions

`implement` and the agents it invokes are rendered from `~/.config/ai/method/` by
`scripts/gen-skills.sh` in the dotfiles repo (`task common:gen:skills`, or
`common:gen:skills:check` to fail on a stale file). The body is shared; only frontmatter
and a handful of variants differ, so the two trees cannot drift.

| | Claude Code | Opencode |
|---|---|---|
| Agent frontmatter | `name`, `tools`, `model`, `color` | `description`, `mode` |
| Tool restriction | enforced by the `tools` allowlist | inherited from `opencode.json` |

That second row is a real asymmetry: `run-verifier` is structurally read-only on Claude
because no write tool is in its allowlist, while on opencode the same guarantee rests on
the prose in its body.

### Guidelines

Both tools read shared guidelines from `~/.config/ai/guidelines/`. Referenced, never
copied — they are consulted on demand and read partially by design.

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
| **task-implementer** | Implements one task end-to-end in a fresh context (used by `/implement-flow`) |
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
