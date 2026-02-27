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
/cd-implement ──────────────┬───> decompose-to-tasks (planning)
                            ├───> cd-orchestrator (lifecycle)
                            │       ├──> go-expert or general-purpose (impl)
                            │       ├──> cd-review-orchestrator (review)
                            │       │      ├──> cd-semantic-reviewer (logic)
                            │       │      │    or cd-semantic-go-reviewer (Go)
                            │       │      ├──> cd-security-reviewer
                            │       │      ├──> cd-performance-reviewer
                            │       │      └──> cd-concurrency-reviewer
                            │       └──> commit (committing)
                            └───> (user approval gates between steps)
/pcommit ───────────────────────> (standalone, no agent)
/review-go-tests ───────────────> (standalone, no agent)
/test-go ───────────────────────> (standalone, no agent)
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
/pcommit              Commit completed work
```

### CD Pipeline (orchestrator-managed)

```
/write-user-story     Write user stories, save to user-stories/
        │
        ▼
/cd-implement         Decompose, implement, review (4 parallel reviewers),
                      and commit -- all orchestrator-managed with human gates
```

Each stage produces artifacts the next stage consumes:
- `/write-user-story` outputs `user-stories/[feature].md`
- `/decompose-to-tasks` outputs `tasks/[story].md`
- `/implement`, `/tdd`, and `/cd-implement` accept either a description or a `tasks/` file directly

## Skills

### Implementation Skills

| Skill | Invocation | Description |
|-------|------------|-------------|
| **implement** | `/implement <feature>` | Implement with quality-assured testing. Delegates planning, review, and commits to agents. |
| **cd-implement** | `/cd-implement <feature>` | Orchestrator-managed implementation with 4 parallel reviewers (semantic, security, performance, concurrency) and human approval gates. |
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
| **decompose-to-tasks** | `/decompose-to-tasks`, `/implement`, `/tdd`, `/cd-implement` | Explores codebase, decomposes stories into ordered tasks. |

### CD Orchestration Agents

| Agent | Used By | Model | Description |
|-------|---------|-------|-------------|
| **cd-orchestrator** | `/cd-implement` | haiku | Session lifecycle, context assembly, delegation, pipeline-red enforcement. Does NOT write code. |
| **cd-review-orchestrator** | `cd-orchestrator` | haiku | Coordinates 4 review sub-agents in parallel, validates JSON schemas, produces aggregated pass/block verdict. |

### CD Review Sub-Agents

All review sub-agents output structured JSON: `{decision: "pass|block", findings: [{file, line, issue, why}]}`.

| Agent | Used By | Model | Scope |
|-------|---------|-------|-------|
| **cd-semantic-reviewer** | `cd-review-orchestrator` | inherit | Logic correctness, edge cases, intent alignment, test quality. |
| **cd-semantic-go-reviewer** | `cd-review-orchestrator` | inherit | Same as semantic reviewer, with Go-specific testing guidelines. |
| **cd-security-reviewer** | `cd-review-orchestrator` | sonnet | Injection patterns, authorization gaps, audit trails, secret exposure. |
| **cd-performance-reviewer** | `cd-review-orchestrator` | haiku | Missing timeouts, resource leaks, unbounded operations, graceful degradation. |
| **cd-concurrency-reviewer** | `cd-review-orchestrator` | sonnet | Shared state synchronization, race conditions, idempotency, deadlocks. |

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
| **commit** | `/tdd`, `/implement`, `cd-orchestrator` | Creates commits with well-crafted messages and user approval. |

### Domain Agents

| Agent | Used By | Description |
|-------|---------|-------------|
| **go-expert** | `/cd-implement` (Go projects) | Senior Go engineer with clean architecture and DDD expertise. |
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

## Data Exchange Patterns

| Boundary | Format | Why |
|----------|--------|-----|
| Skill → Agent | Text (structured bundle) | LLMs consume prose natively |
| Agent → Agent (context) | Text (task description, diffs) | Open-ended guidance for LLM |
| Review sub-agent → Review orchestrator | JSON `{decision, findings[]}` | Programmatic branching and aggregation |
| Review orchestrator → Orchestrator | JSON `{decision, findings[]}` | Gate logic (pass/block) |
| Decompose agent → Disk | Markdown `tasks/[name].md` | Human-readable persistent artifact |
