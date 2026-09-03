# Inside clerk

Seven diagrams of how the implement skill and clerk fit together, drawn for someone about to change them. Green is what clerk decides from evidence; terracotta is what the model judges. The same two fills mean the same two things in the method README.

The whole design is one split. Anything a program does more reliably than a prompt — which test command wins, which task is next, whether a green receipt describes the tree about to land, what step comes after this one — is a clerk command. Writing the code, reviewing it and deciding a fix is right stay with the model.

So the implement skill is one loop: ask `clerk step` what comes next, do that one thing, ask again. clerk answers from git state and a ledger it keeps per run, and the prose for each step arrives in the reply rather than in the skill file.

## One call, repeated

The skill never walks a procedure from memory. Every turn is the same call, and the answer is recomputed from the repository and the ledger, so a stopped run resumes with the call it would have made anyway. Commands that close a step embed the next one in their reply so the model does not spend a round trip asking.

```mermaid
sequenceDiagram
  autonumber
  participant M as model, running the skill
  participant S as clerk step
  participant C as clerk, the dispatcher
  participant L as ledger and git
  M->>S: clerk step --start slug --request "…"
  S->>L: write runs/slug/run.json
  loop until step is finished
    S->>L: prepare, in-process: run.json, tasks/, the receipt, git
    L-->>S: facts: flags, code tree, receipt, run
    S->>S: evaluate the row table top-down
    S-->>M: step, instructions, done_by, stop, blocked
    M->>M: do that one step, nothing after it
    M->>C: the command done_by names (finish, receipt, land …)
    C->>L: run it; append events.jsonl, write its stamp
    C->>S: finish, isolate, land, learn: next_step, in-process
    C-->>M: reply, with next or after_commit
  end
```

**Where it lives:** link/common/dot-local/bin/clerk-step (main_step, cmd_step) · clerk_ledger.py (build_ctx) · clerk_steps.py (evaluate, present) · method/implement/body.md, section "The loop"

**When you would change it:** Adding a field to every reply: `present` in clerk_steps.py. Changing what a fresh call resolves first: `build_ctx`.

## The step table and what closes each row

`clerk step` reads the rows from the top and returns the first one that is not done. A green row closes when clerk observes the world change; a terracotta row closes when the model records a judgment with `--done`, stamped with the code tree it applies to. Nothing moves the position but evidence.

```mermaid
flowchart TD
  start["start<br/>run.json exists"] -->|"clerk step --start"| ground
  ground["ground<br/>a guidelines --caller run is in the event log<br/>tree clean, else blocked"] -->|"clerk guidelines --caller"| isolate
  isolate["isolate<br/>the current branch is the slug"] -->|"clerk isolate"| decompose
  decompose["decompose<br/>breakdown bound, sidecar lint clean<br/>approved when review_breakdown is on"] -->|"clerk step --done decompose --tasks-file"| build
  build["build N, once per task<br/>done in the sidecar and the tree clean"] -->|"clerk finish N -- files, then the commit"| build
  build -. "gears on and the task is hard:<br/>pause N until --done pause N" .-> build
  build -->|"no task left open"| suite
  suite["suite<br/>a passing receipt at this code tree"] -->|"clerk receipt --passed"| audit
  audit["audit<br/>accepted at this code tree"] -->|"clerk audit round … accept"| match
  match["match-request<br/>the request re-read, no open mismatch"] -->|"clerk step --done match-request"| explain
  explain["explain<br/>## Theory in the breakdown, committed"] -->|"write it, commit it"| verify
  verify["verify-run<br/>clerk verify clean, residue reviewed"] -->|"step runs verify itself<br/>--done verify-residue"| land
  land["land<br/>archived; integrated when asked"] -->|"clerk land"| learn
  learn["learn<br/>an entry written, or --done learn --none"] -->|"clerk learn"| fin["finished<br/>run.json: finished true"]
  classDef clerk fill:#D8E6E0,stroke:#2F5D50,stroke-width:1.5px,color:#132520
  classDef you fill:#F2DFD3,stroke:#A8501E,stroke-width:1.5px,color:#3A1A08
  classDef plain fill:#EEF0EC,stroke:#5C645F,stroke-width:1px,color:#1B1F1D
  classDef file fill:#FFFFFF,stroke:#9AA39D,stroke-width:1px,color:#1B1F1D
  class start,ground,isolate,build,suite,audit,explain,verify,land,fin clerk
  class decompose,match,learn you
```

**Where it lives:** clerk_steps.py: ROWS and the row_* functions · clerk-step: the DONE handlers · method/clerk-step.md, section "The step table"

**When you would change it:** A new row is one `row_<name>` function returning `row(id, done, …)` plus its place in ROWS, a step file under method/implement/steps/, and a section in tests/clerk-step-test.sh.

## Four places state lives, and who writes each

Tracked files under tasks/ are team decisions and go into commits. The environment file is one machine's. The two directories under .git are clerk's own records: per checkout for what one worktree knows, per run in the common git dir so the ledger outlives the worktree that is removed at the end.

```mermaid
flowchart LR
  subgraph T["tasks/ — tracked, team decisions"]
    bd["story.md<br/>the breakdown"]
    sc["story.json<br/>sidecar: depends_on, done"]
    cj["clerk.json<br/>flag defaults"]
    tc["test-commands.json"]
    lp["learnings.md"]
  end
  subgraph E["tasks/.environment — gitignored, this machine"]
    env["test_command, go_tool_prefix,<br/>flag overrides, worktree_dir"]
  end
  subgraph G["&lt;git-dir&gt;/clerk/ — this checkout"]
    rc["receipt.json"]
    ar["archived.json"]
    tr["tasks/story/N.json<br/>files each task staged"]
  end
  subgraph R["&lt;git-common-dir&gt;/clerk/runs/slug/ — this run"]
    rj["run.json<br/>request, harness, finished"]
    ev["events.jsonl<br/>every logged command"]
    dn["done.json<br/>asserted steps"]
    bj["breakdown.json"]
    aj["audit.json<br/>rounds, live round, acceptance"]
    mr["match-request.json"]
    lj["land.json"]
    sh["shown.json<br/>which step text this session saw"]
    pl["progress.log · runner.json"]
  end
  finish["clerk finish"]:::clerk -->|marks done, stages| sc
  finish -->|records| tr
  receipt["clerk receipt"]:::clerk --> rc
  land["clerk land"]:::clerk --> ar
  land --> lj
  logged["every logged command"]:::clerk -->|appends| ev
  step["clerk step --start · --done"]:::clerk --> rj
  step --> dn
  step --> bj
  step --> mr
  audit["clerk audit"]:::clerk --> aj
  run["clerk run · clerk audit run"]:::clerk --> pl
  model["the model"]:::you -->|ticks criteria, writes Theory| bd
  model -->|clerk learn| lp
  classDef clerk fill:#D8E6E0,stroke:#2F5D50,stroke-width:1.5px,color:#132520
  classDef you fill:#F2DFD3,stroke:#A8501E,stroke-width:1.5px,color:#3A1A08
  classDef plain fill:#EEF0EC,stroke:#5C645F,stroke-width:1px,color:#1B1F1D
  classDef file fill:#FFFFFF,stroke:#9AA39D,stroke-width:1px,color:#1B1F1D
```

**Where it lives:** clerk_repo.py: state_dir, ledger_dir, run_records_dir, ledger_log · clerk_ledger.py: Run · method/clerk-step.md, section "Ledger"

**When you would change it:** A new per-run fact goes in the ledger through `Run.write` or `Run.mark`, never in tasks/: a tracked ledger would dirty the tree on every write and put session evidence into PRs.

## Files, and which imports which

One Python dispatcher runs `clerk-<name>` executables, the way git runs `git-<name>`. Every call between commands is an import: the repo's facts, the sidecar, the checks, the landing and the step table are modules beside the executables, imported by path so they work stowed or not. The only subprocesses left are git, the harness, and a command another command deliberately runs as a program — `clerk-lint` from finish, the executables from the dispatcher — so nothing calls back up the stack.

```mermaid
flowchart LR
  subgraph D["dispatcher"]
    core["clerk<br/>runs clerk-&lt;name&gt;, logs the ones that are evidence,<br/>embeds the next step in four replies"]
  end
  subgraph P["commands: clerk-&lt;name&gt;"]
    step["clerk-step"]
    audit["clerk-audit"]
    runp["clerk-run"]
    mech["prepare · status · finish · receipt<br/>isolate · verify · land"]
    others["stats · lint · guidelines · learn<br/>fixup · story · watch"]
  end
  subgraph S["shared modules: clerk_*.py"]
    lib["clerk_lib<br/>die, emit, git, parse, plugin_bin"]
    repo["clerk_repo<br/>the repo's facts, prepare, the event log"]
    tasks["clerk_tasks<br/>the sidecar: status, next task, finish, receipt"]
    verify["clerk_verify<br/>the mechanical checks"]
    landm["clerk_land<br/>isolate, the gate, landing"]
    ledger["clerk_ledger<br/>Run, Ctx, build_ctx, event readers"]
    steps["clerk_steps<br/>the row table, instructions"]
    method["clerk_method<br/>seam and include renderer"]
    panel["clerk_audit_panel<br/>lenses, remits, refuters"]
    harness["clerk_harness<br/>spawn claude -p or opencode"]
    render["clerk_render<br/>progress lines, beat file"]
    st["clerk_stats<br/>time and tokens"]
  end
  core -->|"runs, as a process"| P
  core -.->|"next step, in-process"| steps
  step --> steps --> ledger --> repo --> lib
  steps --> method
  steps --> tasks
  steps --> verify
  mech --> repo
  mech --> tasks
  mech --> verify
  mech --> landm --> repo
  audit --> panel
  audit --> render
  audit --> st
  audit --> steps
  runp --> harness
  runp --> render
  others --> lib
  others -.->|"facts(), in-process"| repo
  classDef clerk fill:#D8E6E0,stroke:#2F5D50,stroke-width:1.5px,color:#132520
  classDef you fill:#F2DFD3,stroke:#A8501E,stroke-width:1.5px,color:#3A1A08
  classDef plain fill:#EEF0EC,stroke:#5C645F,stroke-width:1px,color:#1B1F1D
  classDef file fill:#FFFFFF,stroke:#9AA39D,stroke-width:1px,color:#1B1F1D
  class core,step,audit,runp,mech,others clerk
```

**Where it lives:** link/common/dot-local/bin/ · clerk_lib.py for what every command does the same way

**When you would change it:** A new command is a new clerk-<name> executable with a first docstring line reading `clerk <name> — …`; the dispatcher lists it without being told. Put the logic in a clerk_*.py module and keep the executable to argument parsing, so another command can import it rather than run it.

## A command's round trip through the dispatcher

Commands whose running is evidence are run rather than exec'd, so their exit is appended to the run's event log on the way out, and four of them get the next step computed in the dispatcher's own process and added to their reply. The ledger is resolved before the command runs, because `land --integrate` ends on a branch the run is no longer named by. A usage error, exit 2 everywhere, is not evidence and is not logged.

```mermaid
flowchart TD
  cmd["clerk &lt;name&gt; args"]:::plain --> found{"clerk-&lt;name&gt; on PATH,<br/>or beside clerk?"}
  found -->|"no"| unknown["unknown command, exit 2"]:::plain
  found -->|"yes"| lg{"in LOGGED?<br/>isolate finish receipt verify land<br/>guidelines lint fixup learn"}
  lg -->|"no"| exec["exec it: its stdio and exit are clerk's"]:::clerk
  lg -->|"yes"| runit["resolve ledger_dir first,<br/>then run it, capturing the reply"]:::clerk
  runit --> log["ledger_log: cmd, argv, exit, at, head<br/>to events.jsonl — never for exit 2"]:::clerk
  log --> nxt{"in INLINE_NEXT, exit 0?<br/>finish isolate land learn"}
  nxt -->|"yes"| embed["next_step(build_ctx()) in this process,<br/>added as next, or after_commit for finish"]:::clerk
  nxt -->|"no"| out["print the reply, exit with the command's code"]:::clerk
  embed --> out
  reads["prepare, status, step, audit …<br/>are reads: never logged"]:::plain
  classDef clerk fill:#D8E6E0,stroke:#2F5D50,stroke-width:1.5px,color:#132520
  classDef you fill:#F2DFD3,stroke:#A8501E,stroke-width:1.5px,color:#3A1A08
  classDef plain fill:#EEF0EC,stroke:#5C645F,stroke-width:1px,color:#1B1F1D
  classDef file fill:#FFFFFF,stroke:#9AA39D,stroke-width:1px,color:#1B1F1D
```

**Where it lives:** link/common/dot-local/bin/clerk: LOGGED, INLINE_NEXT, run_logged

**When you would change it:** A command whose running should count as evidence for a row goes into LOGGED, and the row reads it through an event reader in clerk_ledger.py such as `guidelines_read`.

## The audit is a second machine of the same shape

`clerk audit next` hands out one phase's batch of agent jobs with every prompt resolved; `record` takes the replies and advances. `clerk audit run` walks that loop in-process and spawns a headless harness only where a judgment is wanted. Each landed reply is written to the live round as it arrives, so a killed round resumes with only the rest.

```mermaid
stateDiagram-v2
  direction LR
  [*] --> scope
  scope --> review: one agent lists files and languages
  review --> dedupe: lenses per language and remit, concurrent
  review --> refute: one candidate, nothing to group
  review --> report: no candidate
  dedupe --> refute: one agent groups same-defect findings
  refute --> report: refuters, concurrent, a worktree each for runtime claims
  report --> done: one agent ranks what survived
  done --> [*]: clerk audit round --report, then accept
  note right of refute
    a refuter that could not run has refuted nothing
    majority of usable verdicts decides
  end note
  note right of done
    another round is earned only by a surviving
    high, or medium runtime, finding not declined
  end note
```

**Where it lives:** clerk-audit: audit_next, audit_record, audit_run, Runner · clerk_audit_panel.py: LANG, remit_for, build_panel, refute_jobs · clerk_harness.py: run_job, run_batch · method/audit-implement/prompts/ and schemas.json

**When you would change it:** What a lens is owed, or how many refuters a claim gets, changes in clerk_audit_panel.py and reaches both harnesses at once. How an agent is spawned changes only in clerk_harness.py's `_argv` and `_envelope`.

## Where the words the model reads come from

The skill file the harness loads is generated, and holds only what is true before any step runs. Each step's method is its own file, rendered for the harness at the moment the step is reached. Both readings go through one resolver, so a seam that renders in the skill renders the same way in the reply.

```mermaid
flowchart LR
  body["method/implement/body.md<br/>the shape, the loop, the flags"]:::file
  seams["method/implement/seams/&lt;harness&gt;/*.md<br/>what differs per harness"]:::file
  shared["method/shared/*.md<br/>prepare, injection defence"]:::file
  stepsf["method/implement/steps/&lt;step&gt;.md<br/>one file per row"]:::file
  gen["scripts/gen-skills.sh<br/>strict: an unresolved marker fails"]:::clerk
  cs["clerk step<br/>lenient: a missing fragment is named in place"]:::clerk
  method["clerk_method.py<br/>seam · include · quote · var"]:::clerk
  skillc[".claude/skills/implement/SKILL.md<br/>generated, do not edit"]:::file
  skillo[".config/opencode/skills/implement/SKILL.md<br/>generated, do not edit"]:::file
  reply["instructions in the step reply<br/>full text once per session, then a pointer"]:::you
  body --> gen
  seams --> gen
  shared --> gen
  gen --> method
  gen --> skillc
  gen --> skillo
  stepsf --> cs
  seams --> cs
  shared --> cs
  cs --> method
  cs --> reply
  classDef clerk fill:#D8E6E0,stroke:#2F5D50,stroke-width:1.5px,color:#132520
  classDef you fill:#F2DFD3,stroke:#A8501E,stroke-width:1.5px,color:#3A1A08
  classDef plain fill:#EEF0EC,stroke:#5C645F,stroke-width:1px,color:#1B1F1D
  classDef file fill:#FFFFFF,stroke:#9AA39D,stroke-width:1px,color:#1B1F1D
```

**Where it lives:** scripts/gen-skills.sh · clerk_method.py · clerk_steps.py: instructions_for, instructions_text · Taskfile: `task common:gen` and `gen:skills:check`

**When you would change it:** Edit the source under method/, never the SKILL.md, then run `task common:gen`. A step's text changes without regenerating anything; a change to body.md or a seam needs the generator, and `--check` fails the build until it has run.

## Contributing a change

- **Run the suites.** `env -u CLAUDECODE tests/clerk-test.sh`, `tests/clerk-step-test.sh` and `tests/clerk-run-test.sh`. They build throwaway repositories and assert on JSON; the step suite takes a few minutes. Inside a Claude Code session the variable has to be unset or six worktree cases fail for no reason of yours.
- **Regenerate the prose.** `task common:gen` after touching anything under method/ that a SKILL.md is built from; `task common:gen:skills:check` is what tells you whether you needed to.
- **Mind the links.** ~/.local/bin/clerk-* are stow symlinks into this working tree. A saved edit is what every other session on the machine runs next, so keep an edit-and-test cycle short.
- **Keep the split.** If a change makes the model remember an order or re-derive a fact, it belongs in a command or a row instead. If it asks a program to judge whether code is right, it belongs with the model.
