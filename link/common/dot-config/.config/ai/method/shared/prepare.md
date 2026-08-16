### Resolve the environment

```
clerk prepare --request "<the request, verbatim>"
```

One call, one JSON object: `languages` (every marker matched, not just the first), `test_commands` and the resolved `test_command`, `go_tool_prefix`, `learnings_path`, `repo_root`, `work_tree`, `in_worktree`, `default_branch`, `base`, `tasks_file`, `commit_skill`, `flags` with `flag_sources`, and whether the tree is `clean`.

**Pass the request.** It is the top layer of two resolutions below — the run's flags and the learnings path — and handing it over is what lets one command finish them. Quote it and pass it whole; `prepare` reads the tokens it knows and ignores the prose around them.

Read the values rather than re-deriving them. Three carry precedence rules subtle enough that resolving them by hand goes wrong quietly, which is why a command settles them and reports the answer:

- **`test_command`** — `tasks/test-commands.json` (tracked, a team decision) beats `tasks/.environment` (a gitignored machine-local cache) beats detection. A cached command must never shadow one the team committed. Use the entry for the task's language while working on it; use `default` before committing anything that spans languages, and again in Phase 3.
- **`go_tool_prefix`** — whether *this machine* runs Go through mise. Decided once, applied to every Go command, never double-wrapped on a project command that already says `mise exec --`.
- **`learnings_path`** — in-tree when the repo tracks `tasks/`, out-of-tree per-project when it gitignores it, so a shared repo gets steering without polluting teammates' checkouts.
- **`flags`** — the run's flags, request first, then `tasks/clerk.json` (tracked, a team decision), then `tasks/.environment` (gitignored, machine-local), then off. `flag_sources` names what decided each, `request` included. Only whole tokens count, so a description that happens to say "integrate" is prose and not an instruction, and a request carrying both `--integrate` and `--no-integrate` reads as off — off is what a run does with nothing set, so an ambiguous signal must never be what changes it.

**Read the learnings file now.** It holds conventions and recurring findings earlier runs paid for.

**`learnings_path` honours a `--learnings-path` in the request**, and `learnings_path_source` says which you got. That override exists because the path is keyed on the repository, and every worktree of one repo shares a git-common-dir — so several runs dispatched over one story would read and append to a single file at once, each overwriting what the others just added. A caller that fans runs out gives each its own path for that reason. Use the resolved value for both the read here and the write at the end.

If `clerk` is not installed, its resolutions are documented in `~/.config/ai/method/implement/` — but install it rather than hand-executing them; getting `test_command` precedence wrong silently tests the wrong thing.

### Check whether this run already exists

Stopping and restarting is the normal case, not an edge one, and the two ways of getting it wrong are both expensive: a second worktree strands the first one's commits somewhere nobody looks, and a second decomposition produces a different task list against code the first run already changed, so the sidecar recording what was built no longer describes the plan.

`clerk prepare` settles it in **`resume`**, which is either null or the run you are rejoining:

- **`resume.breakdown`** — the breakdown that has started and not finished, with its `done`/`total`. Adopt it in Phase 1 rather than decomposing again.
- **`resume.worktree`** — the worktree whose branch is that breakdown's slug, or null. That is the run's home; enter it rather than creating another. How you enter it is tool-specific and covered below.

**Null covers two different situations, and `breakdowns` tells them apart.** Nothing part-built is a fresh start. Several part-built at once is the normal state of a repo planned as deliverables — choosing between them needs to know which run this is, so `prepare` reports each with its progress and picks none. Read `breakdowns` in that case and name the one you are building with `--tasks-file`.

`clerk status --tasks-file <path>` shows exactly where a previous run stopped.
