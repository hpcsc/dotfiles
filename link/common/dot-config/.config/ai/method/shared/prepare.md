### Read the environment off the step

Every `clerk step` reply carries **`facts`** — the whole of `clerk prepare` for this run, resolved on the call you are reading. Do not run `clerk prepare` yourself: it would return the same object, and the reply in front of you already has it with the run's flags applied.

`facts` holds `languages` (every marker matched, not just the first), `test_commands` and the resolved `test_command`, `go_tool_prefix`, `learnings_path`, `repo_root`, `build_tree`, `in_worktree`, `branch`, `default_branch`, `base`, `tasks_file`, `tasks_home`, `tasks_tracked`, `commit_skill`, `flags` with `flag_sources`, `resume`, and whether the tree is `clean`.

Read the values rather than re-deriving them. Three carry precedence rules subtle enough that resolving them by hand goes wrong quietly, which is why a command settles them and reports the answer:

- **`test_command`** — `tasks/test-commands.json` (tracked, a team decision) beats `tasks/.environment` (a gitignored machine-local cache) beats detection. A cached command must never shadow one the team committed. Use the entry for the task's language while working on it; use `default` before committing anything that spans languages, and again in Phase 3.
- **`go_tool_prefix`** — whether *this machine* runs Go through mise. Decided once, applied to every Go command, never double-wrapped on a project command that already says `mise exec --`.
- **`learnings_path`** — always `tasks/learnings.md` in the repo the learnings are about, beside the breakdowns. It hangs off the main checkout, so every worktree of one repo reads and writes the same file. A repo that gitignores `tasks/` keeps its learnings all the same; they simply stay local instead of reaching teammates.
- **`flags`** — the run's flags, request first, then `tasks/clerk.json` (tracked, a team decision), then `tasks/.environment` (gitignored, machine-local), then off. `flag_sources` names what decided each, `request` included. Only whole tokens count, so a description that happens to say "integrate" is prose and not an instruction, and a request carrying both `--integrate` and `--no-integrate` reads as off — off is what a run does with nothing set, so an ambiguous signal must never be what changes it.

The request is the top layer of the last two, and it needs no passing: `clerk step start` recorded it verbatim, and every resolution since reads it from there.

**Read the learnings file now.** It holds conventions and recurring findings earlier runs paid for.

**`learnings_path` honours a `--learnings-path` in the request**, and `learnings_path_source` says which you got. That override exists because the path is one per repository, and every worktree of one repo resolves to it — so several runs dispatched over one story would read and append to a single file at once, each overwriting what the others just added. A caller that fans runs out gives each its own path for that reason. Use the resolved value for both the read here and the write at the end.

### Check whether this run already exists

Stopping and restarting is the normal case, not an edge one, and the two ways of getting it wrong are both expensive: a second worktree strands the first one's commits somewhere nobody looks, and decomposing again produces a different breakdown against code the first run already changed, so the task record recording what was built no longer describes it.

**`facts.resume`** settles it, and is either null or the run you are rejoining:

- **`resume.breakdown`** — the breakdown that has started and not finished, with its `done`/`total`. Adopt it in Phase 1 rather than decomposing again.
- **`resume.worktree`** — the worktree whose branch is that breakdown's slug, or null. That is the run's home; enter it rather than creating another. How you enter it is tool-specific and covered below.

**Null covers two different situations, and the decompose step tells them apart.** Nothing part-built is a fresh start. Several part-built at once is the normal state of a repo planned as deliverables — choosing between them needs to know which run this is, so nothing picks one for you. That step's row carries `breakdowns`, each with its progress; read it there and name the one you are building with `--tasks-file`.

`clerk status --tasks-file <path>` shows exactly where a previous run stopped.
