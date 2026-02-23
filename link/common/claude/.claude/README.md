# Claude Code Skills & Agents

Custom skills and agents for software development workflows.

## Architecture

```
Skills (user-facing)              Agents (autonomous workers)
─────────────────────             ────────────────────────────
/write-user-story ──────────────> (standalone, no agent)
/decompose-to-tasks ────────────> decompose-to-tasks
/implement ─────────────────┬───> decompose-to-tasks (planning)
                            ├───> test-go-reviewer (review)
                            └───> commit (committing)
/tdd ───────────────────────┬───> decompose-to-tasks (planning)
                            ├───> tdd-test-writer (red)
                            ├───> tdd-implementer (green)
                            ├───> tdd-refactorer (refactor)
                            └───> commit (committing)
/pcommit ───────────────────────> (standalone, no agent)
/review-go-tests ───────────────> (standalone, no agent)
/test-go ───────────────────────> (standalone, no agent)
```

## Workflow Pipeline

The skills form a pipeline from idea to committed code:

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
/pcommit              Commit completed work
```

Each stage produces artifacts the next stage consumes:
- `/write-user-story` outputs `user-stories/[feature].md`
- `/decompose-to-tasks` outputs `tasks/[story].md`
- `/implement` and `/tdd` accept either a description or a `tasks/` file directly

## Skills

### Implementation Skills

| Skill | Invocation | Description |
|-------|------------|-------------|
| **implement** | `/implement <feature>` | Implement with quality-assured testing. Delegates planning, review, and commits to agents. |
| **tdd** | `/tdd <feature>` | Test-driven development with Red-Green-Refactor cycles. Supports hands-off and ping-pong modes. |
| **pcommit** | `/pcommit` | Draft and execute a commit for staged changes with user approval. |

### Planning Skills

| Skill | Invocation | Description |
|-------|------------|-------------|
| **write-user-story** | `/write-user-story <feature>` | Generate INVEST-compliant user stories. Saves to `user-stories/`. |
| **decompose-to-tasks** | `/decompose-to-tasks <story>` | Break a user story into ordered, codebase-aware tasks. Saves to `tasks/`. |

### Design & Architecture Skills

| Skill | Invocation | Description |
|-------|------------|-------------|
| **event-modeling** | Auto-triggers | Design event-driven systems using Event Modeling methodology. |
| **domain-design-review** | Auto-triggers | Review designs against 8 architectural anti-patterns. |
| **solution-architect** | Auto-triggers | Guidance on Saga, Process Manager, Choreography, and Outbox patterns. |

### Language & Testing Skills

| Skill | Invocation | Description |
|-------|------------|-------------|
| **test-go** | Auto-triggers | Write Go tests following behavior-driven testing principles. |
| **review-go-tests** | `/review-go-tests` | Review Go tests against testing guidelines. |
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

### TDD Agents

| Agent | Used By | Description |
|-------|---------|-------------|
| **tdd-test-writer** | `/tdd` | Red phase: writes a failing test for expected behavior. |
| **tdd-implementer** | `/tdd` | Green phase: minimum code to make the test pass. |
| **tdd-refactorer** | `/tdd` | Refactor phase: structural improvements while keeping tests green. |

### Review Agents

| Agent | Used By | Description |
|-------|---------|-------------|
| **test-go-reviewer** | `/implement` | Reviews Go tests against behavior-driven testing guidelines. |
| **test-reviewer** | (direct use) | Reviews tests across all languages against testing guidelines. |

### Commit Agent

| Agent | Used By | Description |
|-------|---------|-------------|
| **commit** | `/tdd`, `/implement` | Creates commits with well-crafted messages and user approval. |

### Domain Agents

| Agent | Used By | Description |
|-------|---------|-------------|
| **go-expert** | (direct use) | Senior Go engineer with clean architecture and DDD expertise. |
| **domain-modeler** | (direct use) | Domain modeling: aggregates, bounded contexts, boundaries. |
| **event-modeling-expert** | (direct use) | Event-driven system design and visual modeling. |
| **solution-architect** | (direct use) | Event sourcing, distributed processes, and integration patterns. |
| **cue-expert** | (direct use) | CUE schema validation, testing, and configuration. |

## Skill vs Agent

| Type | Discovery | Context | Best For |
|------|-----------|---------|----------|
| **Skill** | Auto or `/name` | Main conversation | Orchestrating workflows, user interaction |
| **Agent** | Delegated by skills | Isolated sub-process | Focused autonomous work |

Skills orchestrate the user-facing workflow. Agents do the autonomous work within each step.
