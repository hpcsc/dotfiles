# Claude Code Skills & Agents

Custom skills and agents for software development workflows.

## Architecture

```
Skills (user-facing)              Agents (autonomous workers)
─────────────────────             ────────────────────────────

/write-user-story ──────────────> (standalone, no agent)
/decompose-to-tasks ────────────> decompose-to-tasks
/implement ────────────────┬────> decompose-to-tasks (planning)
                           ├────> test-case-designer (test design)
                           ├────> go-implementer or general-purpose (impl)
                           ├────> go-refactorer or refactorer (refactoring)
                           ├────> go-semantic-reviewer or semantic-reviewer
                           ├────> go-concurrency-reviewer or concurrency-reviewer
                           ├────> go-performance-reviewer or performance-reviewer
                           ├────> go-guidelines-reviewer (Go only)
                           ├────> go-mutation-reviewer (Go only)
                           └────> commit (committing)
/tdd ──────────────────────┬────> decompose-to-tasks (planning)
                           ├────> tdd-test-writer (red)
                           ├────> tdd-implementer (green)
                           ├────> tdd-refactorer (refactor)
                           └────> commit (committing)
/refactor-go ──────────────┬────> go-refactorer (impl)
                           ├────> go-test-reviewer (review)
                           └────> go-guidelines-reviewer (review)
/commit ───────────────────────> commit
/pcommit ──────────────────────> commit
/model-events ─────────────────> (standalone, no agent)
/review-go-tests ──────────────> (standalone, no agent)
/review-go ────────────────────> (standalone, no agent)
/test-go ──────────────────────> (standalone, no agent)
/implement-go-interface ───────> (standalone, no agent)
```

## Workflow Pipelines

### Standard Pipeline

```
/write-user-story     Write user stories, save to user-stories/
        │
        ▼
/decompose-to-tasks   Break stories into tasks, save to tasks/
        │
        ▼
/implement or /tdd    Implement tasks with quality gates
        │
        ▼
/commit               Commit completed work
```

Each stage produces artifacts the next stage consumes:
- `/write-user-story` outputs `user-stories/[feature].md`
- `/decompose-to-tasks` outputs `tasks/[story].md`
- `/implement` and `/tdd` accept either a description or a `tasks/` file directly

## Skills

### Implementation Skills

| Skill | Invocation | Description |
|-------|------------|-------------|
| **implement** | `/implement <feature>` | Unified implementation pipeline: planning, test design, implementation (language-aware), parallel reviewers, human approval gates, and commit. |
| **tdd** | `/tdd <feature>` | Test-driven development with Red-Green-Refactor cycles. Supports hands-off and ping-pong modes. |
| **commit** | `/commit` | Delegate to the commit agent for staged changes. |
| **pcommit** | `/pcommit` | Delegate to the commit agent (alias for projects without a project-level commit skill). |
| **refactor-go** | `/refactor-go <target>` | Go refactoring with investigation, planning, implementation via go-refactorer, and review by go-test-reviewer and go-guidelines-reviewer. |

### Planning Skills

| Skill | Invocation | Description |
|-------|------------|-------------|
| **write-user-story** | `/write-user-story <feature>` | Generate INVEST-compliant user stories. Saves to `user-stories/`. |
| **decompose-to-tasks** | `/decompose-to-tasks <story>` | Break a user story into ordered, codebase-aware tasks. Saves to `tasks/`. |

### Design & Architecture Skills

| Skill | Invocation | Description |
|-------|------------|-------------|
| **model-events** | `/model-events <requirements or codebase>` | Interactive event modeling: discovers business processes, identifies events in timeline order, storyboards, autonomous components, and message processing patterns. Gated feedback loops at every phase. |
| **domain-design-review** | Auto-triggers | Review designs against 8 architectural anti-patterns. |
| **solution-architect** | Auto-triggers | Guidance on Saga, Process Manager, Choreography, and Outbox patterns. |

### Language & Testing Skills

| Skill | Invocation | Description |
|-------|------------|-------------|
| **test-go** | Auto-triggers | Write Go tests following behavior-driven testing principles. |
| **review-go-tests** | `/review-go-tests` | Review Go tests against testing guidelines. |
| **review-go** | `/review-go <package>` | Review a Go package against project guidelines (naming, architecture, workflow). |
| **cue** | Auto-triggers | Work with CUE configuration files. |
| **implement-go-interface** | `/implement-go-interface` | Create Go interface test doubles. |

### Writing

| Skill | Invocation | Description |
|-------|------------|-------------|
| **write** | Auto-triggers | Write or edit articles/notes following style guidelines. |

## Agents

Agents run in isolated sub-processes, delegated to by skills or spawned directly.

### Planning Agents

| Agent | Used By | Description |
|-------|---------|-------------|
| **decompose-to-tasks** | `/decompose-to-tasks`, `/implement`, `/tdd` | Explores codebase, decomposes stories into ordered tasks. |

### Test Design Agents

| Agent | Used By | Description |
|-------|---------|-------------|
| **test-case-designer** | `/implement` | Designs test cases from task acceptance criteria. Outputs structured test plan for user approval — does not write code. |

### Implementation Agents

| Agent | Used By | Description |
|-------|---------|-------------|
| **go-implementer** | `/implement` (Go projects) | Writes tests first, then production code. Follows project Go guidelines. |
| **go-expert** | (direct use) | Senior Go engineer with clean architecture and DDD expertise. |

### Refactoring Agents

| Agent | Used By | Description |
|-------|---------|-------------|
| **go-refactorer** | `/implement` (Go), `/refactor-go` | Improves Go code structure while keeping tests green. Follows project Go guidelines. |
| **refactorer** | `/implement` (non-Go) | Language-agnostic refactoring agent. Improves code structure while keeping tests green. |

### Review Agents

All review agents output structured JSON: `{decision: "pass|block", findings: [{file, line, issue, why}]}`.

| Agent | Used By | Scope |
|-------|---------|-------|
| **semantic-reviewer** | `/implement` | Logic correctness, edge cases, intent alignment, test quality. |
| **go-semantic-reviewer** | `/implement` (Go) | Same as semantic reviewer, with Go-specific testing guidelines. |
| **concurrency-reviewer** | `/implement` | Shared state synchronization, race conditions, idempotency, deadlocks. |
| **go-concurrency-reviewer** | `/implement` (Go) | Same as concurrency reviewer, with Go concurrency guidelines (goroutine lifecycle, channel discipline, sync primitives). |
| **performance-reviewer** | `/implement` | Missing timeouts, resource leaks, lack of graceful degradation. |
| **go-performance-reviewer** | `/implement` (Go) | Same as performance reviewer, with Go-specific performance guidelines. |
| **go-guidelines-reviewer** | `/implement` (Go) | Naming patterns, architecture principles, development workflow conventions. |
| **go-mutation-reviewer** | `/implement` (Go) | Runs go-gremlins mutation testing, interprets survived mutants, surfaces actionable test gaps. |
| **security-reviewer** | `/implement` | Injection patterns, authorization gaps, audit trail verification. |
| **go-test-reviewer** | `/refactor-go`, (direct use) | Reviews Go tests against behavior-driven testing guidelines. |
| **test-reviewer** | (direct use) | Reviews tests across all languages against testing guidelines. |

### TDD Agents

| Agent | Used By | Description |
|-------|---------|-------------|
| **tdd-test-writer** | `/tdd` | Red phase: writes a failing test for expected behavior. |
| **tdd-implementer** | `/tdd` | Green phase: minimum code to make the test pass. |
| **tdd-refactorer** | `/tdd` | Refactor phase: structural improvements while keeping tests green. |

### Commit Agent

| Agent | Used By | Description |
|-------|---------|-------------|
| **commit** | `/tdd`, `/implement`, `/commit`, `/pcommit` | Creates commits with well-crafted messages and user approval. |

### Domain Agents

| Agent | Used By | Description |
|-------|---------|-------------|
| **domain-modeler** | (direct use) | Domain modeling: aggregates, bounded contexts, boundaries. |
| **solution-architect** | (direct use) | Event sourcing, distributed processes, and integration patterns. |
| **cue-expert** | (direct use) | CUE schema validation, testing, and configuration. |

## Skill vs Agent

| Type | Discovery | Context | Best For |
|------|-----------|---------|----------|
| **Skill** | Auto or `/name` | Main conversation | Orchestrating workflows, user interaction |
| **Agent** | Delegated by skills | Isolated sub-process | Focused autonomous work |

Skills orchestrate the user-facing workflow. Agents do the autonomous work within each step.

## Data Exchange Patterns

| Boundary | Format | Why |
|----------|--------|-----|
| Skill → Agent | Text (structured bundle) | LLMs consume prose natively |
| Agent → Agent (context) | Text (task description, diffs) | Open-ended guidance for LLM |
| Review agent → Skill | JSON `{decision, findings[]}` | Programmatic branching and aggregation |
| Decompose agent → Disk | Markdown `tasks/[name].md` | Human-readable persistent artifact |
