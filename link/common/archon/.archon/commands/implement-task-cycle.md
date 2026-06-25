# implement — task cycle

You orchestrate **one** task's full test → implement → refactor → review cycle, then
delegate the inner work to the `task-implementer` subagent. You do NOT write
production code yourself. Inputs arrive under `=== RUNTIME INPUT ===`:
`TASK_FILE`, `TASK_NUMBER`, and an optional `REVISION_NOTE`.

## 1. Load the task

Read `TASK_FILE` and extract the task whose number is `TASK_NUMBER` — its
`language`, `description`, `behavior`, `acceptance_criteria`, `affected_files`,
`patterns_to_follow`, and `testable`. If `REVISION_NOTE` is non-empty, this is a
re-run: the previous cycle for this task was rejected and must be redone with the
note applied.

## 2. Select agents by the task's language

| Role | Go | JavaScript/TypeScript | Elixir | Generic (all others) |
|---|---|---|---|---|
| Implementer | `go-implementer` | `js-implementer` | `elixir-implementer` | `general` |
| Refactorer | `go-refactorer` | `js-refactorer` | `elixir-refactorer` | `refactorer` |
| Semantic reviewer | `go-semantic-reviewer` | `js-semantic-reviewer` | `elixir-semantic-reviewer` | `semantic-reviewer` |
| Concurrency reviewer | `go-concurrency-reviewer` | `js-concurrency-reviewer` | `elixir-concurrency-reviewer` | `concurrency-reviewer` |
| Performance reviewer | `go-performance-reviewer` | `js-performance-reviewer` | `elixir-performance-reviewer` | `performance-reviewer` |
| Guidelines reviewer | `go-guidelines-reviewer` | `js-guidelines-reviewer` | `elixir-guidelines-reviewer` | _(skip)_ |

## 3. Triage reviewers

Include only those that could plausibly apply to this task:

| Reviewer | Include when |
|---|---|
| Semantic | always |
| Guidelines | the task's language has a guidelines reviewer above |
| Concurrency | task plausibly touches goroutines/threads/async, channels/locks/mutexes, processes/GenServers/ETS, shared mutable state, DB transactions, sync primitives |
| Performance | task plausibly touches HTTP clients, DB queries, file/resource ops, slice/map creation in loops, `io.ReadAll`, retry/polling loops |

Omit concurrency/performance for pure domain logic, UI, or docs. When in doubt, include.

## 4. Detect the test command

Auto-detect from the project (Makefile target, `package.json` scripts, framework
convention). Never hardcode.

## 5. Testing guidelines (progressive disclosure)

Pass these paths to the inner agents with the instruction: "Read line 1 for the
`<!-- index: 1-N -->` range, read the index, then load only the relevant sections —
never the whole file."

- Always: `~/.config/ai/guidelines/testing/caller-patterns.md`
- Go: `~/.config/ai/guidelines/go/testing-patterns.md`
- JavaScript/TypeScript: `~/.config/ai/guidelines/javascript/testing-patterns.md`
- Elixir: `~/.config/ai/guidelines/elixir/testing-patterns.md`

## 6. Delegate to the task-implementer subagent

Spawn the `task-implementer` subagent with a single JSON object. It runs the inner
test-design → implement → refactor → review loop in its own context and writes a
distilled summary to the scratch path.

```json
{
  "task": {
    "n": <TASK_NUMBER>,
    "title": "<short title>",
    "description": "<imperative description>",
    "language": "<task language>",
    "behavior": "<observable behavior>",
    "acceptance_criteria": ["..."],
    "affected_files": ["..."],
    "patterns_to_follow": ["..."],
    "testable": <true|false>
  },
  "language": "<task language>",
  "agents": {
    "test_case_designer": "test-case-designer",
    "implementer": "<from §2>",
    "refactorer": "<from §2>",
    "reviewers": ["<triaged from §3>"]
  },
  "test_command": "<from §4>",
  "testing_guidelines": {
    "paths": ["<from §5>"],
    "instruction": "Read line 1 for the index range, read the index, then load only the relevant sections — never the whole file."
  },
  "checkpoint_path": "tasks/.checkpoint",
  "scratch_path": "tasks/.cycles/task-<TASK_NUMBER>.md",
  "revision_feedback": "<REVISION_NOTE, or omit if empty>"
}
```

## 7. Return

Relay the subagent's status block verbatim as your final output:

```json
{
  "status": "pass" | "block",
  "scratch": "tasks/.cycles/task-<TASK_NUMBER>.md",
  "plan_impact": "none" | "triggered",
  "blocker": "<reason>" | null
}
```

Do not commit, do not mark the task complete, do not read the subagent's inner
transcript — the orchestrating workflow handles the gate, the commit, and the
checkpoint. Your job ends when the scratch file is written and the status returned.
