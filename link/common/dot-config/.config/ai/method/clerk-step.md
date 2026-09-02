# clerk step

`clerk step` makes the order of an `implement` run a property of clerk, not of the model.
The model asks clerk what to do, does that one thing, and asks again. clerk computes the
answer from the repository and from a ledger. A skipped step then becomes a refusal, not a
silent omission.

## Problem

The `implement` skill was 535 lines of prose. clerk enforced the rules inside a few steps,
but no rule enforced the order between steps. A model that does not follow long
instructions well skips a step, and nothing downstream notices.

A clerk refusal enforced these rules:

- one task in flight: `next` exits 3 on a dirty tree
- only the named paths staged: `finish`
- every task done, tree clean, receipt at HEAD before the branch lands: `gate`
- a new receipt after a live rebase: `land`

Prose alone carried the rest: the request record, `prepare`, `guidelines` and the caller
pattern, the branch or worktree, `lint certainty-unevidenced`, the plan table, tests first,
`lint --staged` before each commit, the commit skill, the criteria ticks, the gears pauses,
the audit, the second audit round, the story validation, the Theory section, `verify`, and
the learnings. That is about five enforced transitions against about fifteen that depend
on the model.

## Design

`clerk step` is idempotent. It reads the step table from the top and returns the first
step that is not done, with the instructions for that step. There is no counter. clerk
computes the position on every call from git state and from the ledger, so a stopped run
continues with the same call.

There are three kinds of result:

- **Derived:** clerk checks the world. The model runs the commands, then calls `clerk step`
  again.
- **Asserted:** completion is a judgment. The model records it with
  `clerk step --done <id>`. This is the same mechanism as the `--audit-accepted` flag on
  `gate`. clerk records the assertion with the code tree it applies to, but does not infer
  it.
- **Blocked:** something needs a decision. `step` returns `blocked: true` with a reason,
  and the instruction is to stop and ask: a dirty tree at `ground`, an open story mismatch,
  a dependency cycle. A human gate returns `stop: true`: the model ends its turn, and the
  next `clerk step` is the reader's approval.

The command surface:

```
clerk step --start <slug> --request "<the request, verbatim>"   open a run
clerk step                                                      the step to do now
clerk step --done <id> [options]                                record an asserted step
clerk step --status                                             every row, done or not
clerk step --rm <slug>                                          delete a ledger
clerk audit plan --rounds <n>                                   declare the round count
clerk audit round --report <findings.json>                      record a round
clerk audit accept [--early "<why>"]                            record the acceptance
```

`clerk step`, `clerk audit` and `clerk stats` are three executables over two shared
modules: `clerk_ledger.py` holds the run ledger, the event-log readers and the context
every call resolves, and `clerk_steps.py` holds the step table.

## Run identity

A slug identifies a run. The slug is the branch name. `prepare` already pairs
`resume.worktree` with a breakdown by the same rule, so a run, its branch and its worktree
share one name. The breakdown is bound to the run by path, so its file name is free.

Which ledger `clerk step` reads:

| Where the call runs | Ledger |
|---|---|
| On a feature branch | the ledger named by that branch |
| On the default branch, one unfinished run | that run |
| On the default branch, more than one | refuse with exit 3, list them, take `--run <slug>` |
| On a feature branch with no ledger | `start`, with the open runs listed |

`clerk step --start` refuses when an unfinished ledger exists for the slug and prints its
progress. A finished slug can start again.

## Ledger

The ledger lives in the common git dir, not in the git dir of the worktree:

```
<git-common-dir>/clerk/runs/<slug>/
  run.json          {slug, request, started_at, launch_cwd, launch_branch, harness, finished}
  events.jsonl      one line for each logged clerk command: {cmd, argv, exit, at, head}
  done.json         the asserted completions: ground, pause, verify-run, verify-residue, learn
  breakdown.json    {tasks_file, sidecar, approved, lint_hash}
  audit.json        {rounds_planned, rounds: [{n, code_tree, findings, refuted, coverage_gaps}],
                     accepted: {code_tree, reason}}
  match-request.json {code_tree, mismatches, resolved}
  verify-log.jsonl  one line each time the verify-run row ran the check:
                    {at, code_tree, clean, blocks, warns, not_checked}
  land.json         {archived, integrate, integrate_source, landed}
```

Facts about one checkout stay in the git dir of that worktree, `<git-dir>/clerk/`:
`receipt.json`, `archived.json` and the file lists for each task.

### The event log

Most evidence is a clerk command that ran. So clerk's dispatcher appends one line to the
run's `events.jsonl` when one of these commands exits: `worktree`, `branch`, `finish`,
`receipt`, `verify`, `land`, `init`, and the `guidelines`, `lint`, `fixup`, `learn` and
`sidecar` plugins. The line holds the command, its argv, its exit code, the time and HEAD.
Reads are not logged. A command with no run to log against logs nothing, which is every
call outside a step-driven run.

clerk resolves the ledger before the command runs, so `land --integrate`, which ends on
the default branch, still logs to the run it merged. argv travels NUL-separated over
stdin: jq reads its own options from anywhere on the command line, so an argv with
`--command` in it was parsed as jq's.

`clerk step` reads the log for:

- **ground:** a `guidelines` run that exited 0 with `--caller <pattern>`
- **the gears signals:** `finish N --retried`, a `finish N` that exited 1 (a lint refusal),
  or a `lint --staged` that exited 1 after N was finished
- **learn:** a `learn` run that exited 0 with `--title`
- **the plan signals for the reflection:** the tasks the plan called `high` that showed a
  signal, the `low` ones that did not, and the `fixup` calls that exited 3

### Why the common git dir

The ledger must outlive the worktree. The last part of a run, the fast-forward and the
learnings, happens in the main checkout after `git worktree remove`. `git worktree remove`
deletes a ledger that lives in the worktree.

The repository has three tiers of state. The ledger is the third tier:

| Tier | Where | Examples | Properties |
|---|---|---|---|
| Team decisions | `tasks/`, tracked | the breakdown and its sidecar, `clerk.json`, `test-commands.json` | shared, reviewed, goes into the task commit |
| Machine-local preferences | `tasks/.environment`, gitignored | the test command cache, flag defaults | written by hand |
| Internal records | `<git-dir>/clerk/`, `<git-common-dir>/clerk/runs/` | the receipt, the archive record, the ledger | written by commands only, never committed, the model cannot write to it |

The alternatives, and what each costs:

- **`tasks/`:** the step table uses "tree clean" as the signal that a task is committed. A
  tracked ledger makes the tree dirty on every write, so `step` and `next` need path
  exemptions everywhere. The sidecar design avoids that dependency: `finish` stages the
  sidecar with the code, so progress and change go into one commit. A tracked ledger also
  puts session evidence into pull requests, where the model can edit it.
- **`.clerk/` at the repository root:** a directory in the work tree belongs to one
  worktree, so `git worktree remove` deletes it. A directory at `repo_root` survives, but
  it needs an exclude entry and `git clean -fdx` deletes it. The model finds it with `rg`
  and `fd`, and a harness can write to it. The gain is visibility. A command gives that:
  `clerk status` and `clerk step --status`. Whoever owns a format owns its reader.

Precedent for the location: `git-branchless` keeps its state under `.git/branchless/`.
`rr-cache`, `info/exclude` and `logs/` are git's own. git ignores unknown files in its
directory, and `git rev-parse --git-common-dir` resolves gitfile worktrees and
submodules.

## Code tree

The code tree is the hash of the HEAD tree listing minus the plan files under `tasks/`:
the `.md`, `.json`, `.yaml` and `.yml` files there. Code under a directory that happens
to be called `tasks/` still counts as code.

Receipts, audit acceptance, validation and the cached verify pass bind to the code tree,
not to the SHA. Reason: the Theory section and the archive are `tasks/`-only commits that
come after the last receipt. `gate` and `verify` compared the receipt SHA to HEAD, so in a
repository that tracks `tasks/` the Theory commit made the receipt stale, and `land`
refused until the model ran the suite again for a docs-only change. Both now compare by
code tree, through one helper in clerk: `prepare` reports the tree at HEAD and whether
the recorded receipt still describes it, and `clerk step` reads both from there rather
than computing its own. The same goes for the run a call belongs to and the task that is
ready: `prepare` names the run, `clerk next` names the task, and step applies the answer.

## The step table

`clerk step` reads the rows from the top and returns the first row that is not done. A
run that left its branch when it landed evaluates only `land` and `learn`.

The last column is documentation of how each row closes, not a field: a `derived` row
opens when clerk observes the world change and an `asserted` one when the caller records
a judgment, and either way `done_by` on the reply names the command to run. Shipping the
category as well made a caller learn two words to reach the same line of the reply.

| # | Step | Done when | How the evidence arrives | Kind |
|---|---|---|---|---|
| 0 | `start` | `run.json` exists | `clerk step --start <slug> --request "…"`. Refuses when an unfinished ledger exists for the slug | input |
| 1 | `ground` | a `guidelines --caller <pattern>` run exited 0, or `--done ground --caller` for a repo with no guidelines directory. `prepare.clean` is true, else **blocked** | the event log. The output of `step` includes the `prepare` JSON as `facts`, so there is no prepare step to skip | derived |
| 2 | `isolate` | the current branch is the slug. `mode` says worktree or in-place; `fallback` says in-place without `in_place` on | `clerk worktree <slug>` or `clerk branch <slug>`. From the main checkout, `step` prints "enter `<path>`" until the cwd is the worktree | derived |
| 3 | `decompose` | `breakdown.json` is bound, the sidecar exists, `lint certainty-unevidenced` is clean at the sidecar's present hash, and `approved` is set when `review_breakdown` is on | `clerk step --done decompose --tasks-file <md> [--approved]`. It runs the lint itself and refuses on findings. On success it prints the task table. An archived breakdown reads from `tasks/completed/` | asserted for the bind, derived for the lint |
| 4 | `build N` (repeats) | `done` for N in the sidecar, and the tree is clean | `clerk finish N [--retried] -- <files>` lints the staged set before it sets `done` and refuses with exit 1 on findings. The commit makes the tree clean. The output carries `certainty`, `blast_radius`, `gear`, `pause_after_tests`, the last task's signals, and progress | derived |
| 4a | `pause N` (gears on, and the task is `low` certainty, `high` blast radius, or the run downshifted) | `tests_shown` for N | `clerk step --done pause N`. `step` prints `stop: true` before it | asserted, a pause |
| 5 | `suite` | the receipt passed, and its code tree equals the HEAD code tree | `clerk receipt` | derived |
| 6 | `audit` | `accepted` is present at this code tree | `clerk audit plan --rounds N`; for each round `clerk audit round --report <json>`, which refuses on a stale receipt, a dirty tree, or more rounds than planned without `--replan`; then `clerk audit accept [--early "<why>"]`. `step` prints the request from `run.json` as `request`, with `base` and `test_commands` | asserted for `accept`, derived for the rest |
| 7 | `match-request` | `match-request.json` at this code tree, with no open mismatch | `clerk step --done match-request [--mismatch "…"]…`. `step` prints the request verbatim, `git log --oneline base..HEAD`, and the four questions. A recorded mismatch is **blocked** until `--resolved` | asserted |
| 8 | `explain` | the breakdown contains `## Theory`, and the file is committed when `tasks_tracked` is true | the model writes it. A `tasks/`-only commit does not disturb rows 5 to 7 | derived |
| 9 | `verify-run` | `clerk verify --all-closed` is clean, and `not_checked` is empty or `--done verify-residue` is recorded. `hints` — what the check could not run for want of a flag — never holds the row | `step` runs verify itself when it reaches the row, and caches a pass in `done.json` at its code tree so the archive commit does not run it again | derived, then asserted |
| 10 | `land` | `land.json` says `landed`, or `archived.json` exists and integration is off or done. From the main checkout: the slug is merged and its worktree and branch are gone | `clerk land`. `gate` reads the acceptance from `audit.json` and the verify pass from `done.json`, so `--audit-accepted` is not needed and a `land` called directly cannot walk past `verify-run`. The exit, fast-forward and remove sequence for a worktree becomes printed instructions from the main checkout | derived |
| 11 | `learn` | a `learn` run wrote an entry, or `--done learn --none` | `clerk learn … --feature <slug>`. `step` prints `breakdown_signals` computed from the log | derived, or asserted |
| end | `finished` | every row above | `step` writes `finished: true` into `run.json` | |

## Output

One JSON object. The `instructions` field holds the method text for that step, with the
seams resolved for the harness clerk detects:

```json
{"run": "poller-retry", "step": "task", "n": 3, "title": "…",
 "certainty": "high", "blast_radius": "low", "gear": "normal",
 "pause_after_tests": false, "stop": false, "blocked": false,
 "why_not_done": "task 3 is open",
 "done_by": "clerk finish 3 [--retried] -- <files>; …; then clerk step",
 "code_tree": "…", "harness": "claude",
 "facts": {"…": "clerk prepare for this request"},
 "progress": {"done": 2, "total": 5, "remaining": 3, "blocked": 1},
 "instructions": "…markdown…"}
```

Harness detection: `CLERK_HARNESS`, else `CLAUDECODE` means claude, else an `OPENCODE*`
variable means opencode, else claude. `--harness` overrides one call.

## The method files

`implement/body.md` holds only what is true before any step runs: the shape of the run,
"The loop", the flags, and the injection defense. Everything step-local — including how
each command refuses — lives one step per file under `implement/steps/<id>.md`, with the
seams inside them, so it arrives when it is usable rather than ten steps early. Two
readers use those files:

- `gen-skills.sh` resolves seam and include markers inside an included file, one level
  down, so a step file can carry its seams.
- `clerk step` prints one step file, with the seams resolved at run time.
  `CLERK_METHOD_DIR` points it at another method directory, which the tests use.

The generated `SKILL.md` is the shape, the loop and the flags. The step text, and each
step's own refusals, arrive only from `clerk step`.

## Tests

`tests/clerk-step-test.sh` builds fixture repositories and walks runs through the table,
one section for each row, plus sections for the event log and the signals. The claim that
no step is reachable without the evidence of the step before it is a set of assertions
there, not a sentence in the prose. `tests/clerk-test.sh` keeps the core cases and adds
the `finish` lint refusal and the code tree comparison.

The step suite takes about two and a half minutes: most of its cases call `clerk step`,
and each call runs `clerk prepare` once on a run branch and twice from the default branch.

## Driving the audit from outside a session

`clerk step` makes the order of a run a property of clerk, and the audit is a phase
machine of its own on the same shape as the step table.
`clerk audit next` returns one phase's batch — the scope pass, then the lens panel, then
dedupe, then the refuters, then the report — with every prompt resolved and every job's
schema named. `clerk audit record --phase <p> --results <file>` takes the replies and
advances. What to run is decided in `clerk_audit_panel.py`: the language table, remits,
the `MIN_REMIT` fold, fix-scoped narrowing, refuter counts, and whether a claim needs a
tree — one file, read by both harnesses, so a change to what a lens is owed cannot reach
one of them and not the other.

`clerk audit run` closes the loop, and it is what both skills launch. It walks the
machine in-process and shells out to a headless agent only where a judgment is wanted:

| Harness | Invocation |
|---|---|
| Claude Code | `claude -p --agent <name> --output-format json --permission-mode acceptEdits` |
| opencode | `opencode run --agent <name> --format json` |

Both resolve user-defined agents, so every lens the panel names is reachable. Two
measured constraints are baked in. `--bare` is not used: it skips the discovery that
finds user-defined agents and leaves five built-ins, so the panel silently cannot run.
And a permission mode is passed, because a lens that reads the diff otherwise stops on a
prompt nobody is there to answer.

What the harness supplies to an in-session subagent and not to a headless one is supplied
here: a reply is parsed out of whatever prose surrounds it and validated against
`schemas.json` with three attempts and the reason fed back each time; and a git worktree is created for any job whose claim can
only be settled by mutating a checkout. A job that never returns a usable reply is
reported failed by name, because a lens missing from a panel reads exactly like a lens
that found nothing.

`--dry-run` prints the phase it would spawn, with each job's agent, isolation and schema,
and spawns nothing.

The `implement` skill is unchanged and still drives the audit through the harness. This
is a second entry point, for a round run from outside a session — a terminal, a cron
entry, a machine with no interactive harness open.

## Harness hooks, not built

Hooks are a second layer for what clerk cannot see, and each harness has its own:

- **Claude Code `Stop` hook:** blocks a stop while `clerk step` is neither `finished` nor
  `stop: true`, with the current instructions as the reason.
- **Claude Code `PreToolUse` hook:** denies `git commit` in Bash during a run, and denies
  Edit and Write while the audit has the tree.
- **opencode:** a plugin on session idle can prompt again. `tool.execute.before` covers the
  tool denials. Neither blocks a stop.

## Language and migration

`clerk step`, `clerk audit` and `clerk stats` are Python, standard library only, next
to the other Python plugins, sharing the ledger and the step table through
`clerk_ledger.py` and `clerk_steps.py`. The bash core gained the event log, the
`code_tree` helper, the lint inside `finish`, and the ledger read in `gate`. What every plugin does the same way
— die and emit, git, the `clerk prepare` call, breakdown resolution, argument parsing as
`clerk <name>` — lives in `clerk_lib.py` beside them, imported by path so it works
stowed or not.

The direction stays one Python package: the core is bash 3.2 with `jq` calls that build
JSON by hand, 9 of the 10 `clerk-*` files are Python already, and the ledger is JSON that
every subcommand reads and writes. `tests/clerk-test.sh` is black-box, so it is the
contract for a port one subcommand at a time. Rules for the port:

- One `git()` helper with `cwd`, captured output, and die() for the error — `clerk_lib`'s.
- Never `shell=True`. Argument lists keep the request and the paths out of a shell.
- Use shell from Python in two cases only: a fixed pipeline with no decisions and no user
  input, or a whole bash subcommand not yet ported. Never split one subcommand across the
  two languages.

## Open questions

- Facts for each task that a reviewer must see, `lint_findings_first_pass` and `retried`,
  can go into the sidecar at `finish` time. They then go into the task commit, where
  `profile-run` and `clerk stack` can read them.
- The opencode environment variable for harness detection, or a `--harness` flag in its
  command wrapper.
