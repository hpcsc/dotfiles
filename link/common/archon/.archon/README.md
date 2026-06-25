# `implement` — Archon workflow

A global Archon port of the autonomous test-first implementation loop: decompose a
story into tasks, approve the plan once, then run gated per-task
test → implement → refactor → review cycles with a commit gate each.

It is **runtime-agnostic**: the heavy AI work runs on either Claude Code or OpenCode,
selected at run time. Both runtimes resolve the same agent names from their own
registries, so the workflow never hard-codes a runtime.

## Files (all under `~/.archon/`, all new — nothing existing was modified)

| File | Role |
|---|---|
| `workflows/implement.yaml` | The DAG: decompose → plan gate → per-task loop → suite → cleanup → summary |
| `scripts/implement` | Runtime dispatcher — routes one unit of work to Claude or OpenCode |
| `commands/implement-decompose.md` | Prompt for the `decompose-to-tasks` agent |
| `commands/implement-task-cycle.md` | Per-task orchestration → delegates to the `task-implementer` agent |
| `commands/implement-commit.md` | Prompt for the `commit` agent |

The workflow reuses your existing, **untouched** agents (`decompose-to-tasks`,
`task-implementer`, `commit`, and the language-specific implementer/refactorer/
reviewer agents) from `~/.claude/agents` and `~/.config/opencode/agents`. The command
files above are independent duplicates of the orchestration logic, so the original
`implement-auto` skill and its agents are never read or changed.

## Run it

```sh
# default runtime = Claude Code
archon workflow run implement "Add rate limiting to the public API"

# same workflow, OpenCode as the worker
IMPL_RUNTIME=opencode archon workflow run implement "Add rate limiting to the public API"
```

Gates surface in whatever surface you launch from (CLI, Web UI, Slack…): one plan
approval, then one approval per task before its commit.

## Runtime switch (env, read by `scripts/implement`)

| Var | Default | Meaning |
|---|---|---|
| `IMPL_RUNTIME` | `claude` | `claude` or `opencode` — which runtime does the work |
| `IMPL_MODEL` | (runtime default) | model override forwarded to the runtime |
| `IMPL_CLAUDE_PERMISSION` | `acceptEdits` | `claude --permission-mode` value |
| `IMPL_COMMANDS` | `../commands` | command directory override |

## Design notes / caveats

- **`provider: claude` in the YAML is the orchestration layer only** — the loop
  controller, `on_reject`, and the final summary. The real implementation work is
  dispatched by `scripts/implement` to `IMPL_RUNTIME` and is independent of it. (OpenCode
  is not a native Archon provider, which is why the worker is invoked via a `bash`
  dispatch rather than an AI node.)
- **The per-task commit gate lives inside the loop node.** Archon can't interleave a
  separate approval node per iteration, so the controller is a small state machine:
  it presents task N, and the human's approve/revise reply arrives as
  `$LOOP_USER_INPUT` on the next iteration. State is recovered each iteration from the
  task file + `tasks/.cycles/` scratch files (which is why those survive
  `fresh_context: true`).
- **Verify headless subagent spawning** for your runtime: the cycle works only if
  `claude --print` / `opencode run` can spawn the `task-implementer` subagent, which
  in turn spawns its inner agents. (The interactive skill already does this; confirm
  the headless path does too.)
- **Claude hooks fire only on the Claude path.** When `IMPL_RUNTIME=claude`, your
  `SubagentStart`/`PostToolUse` steering hooks fire inside the dispatched process.
  On the OpenCode path they don't — the OpenCode agent prompts must carry their own
  guideline/commit discipline (as they presumably already do today).
- **`worktree.enabled: false`** matches the skill's shared-checkout behavior. Flip it
  to `true` for per-run git-worktree isolation — a capability the skill lacks.
- **CLI vs server**: the Archon CLI reads these `~/.archon` files directly. A remote
  server reads from a synced workspace clone, so home-scoped files must exist on the
  host running it. `archon` and `opencode` are not installed on this machine — these
  files are config for wherever the runtimes actually live.
