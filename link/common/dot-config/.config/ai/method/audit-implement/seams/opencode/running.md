## Phase 0: Scope it yourself

You have a shell. Do not spend a subagent on what a few git commands answer.

1. **Resolve the range.**
   - Default: this branch's own work. `git merge-base HEAD main` (fall back to `master`, then whatever `git symbolic-ref --short refs/remotes/origin/HEAD` reports) as the base, `git rev-parse HEAD` as the head.
   - If `$ARGUMENTS` names a base ref, prefer it. If it says `staged`, the range is `git diff --cached` and there is no base commit.
   - **If the base resolves to HEAD, stop and say so** — the branch has already been landed, and the caller needs to name the ref the work started from. An empty diff audited silently is worse than no audit.

2. **List the changed files**: `git diff --name-only <base>...<head>`.

3. **Classify.** If *every* changed file is documentation, config or build plumbing (`.md`/`.txt`/`.rst`, `.json`/`.yaml`/`.toml`/`.ini`/`.lock`, `Makefile`/`Taskfile`/`*.mk`, images), there is nothing a code lens can assess. Report that and stop.

4. **Determine the languages** of the changed code files, and resolve how to run tests — verifiers need it. Same order the `implement` skill uses: `tasks/test-commands.json` (tracked, per-language) first, `tasks/.environment` -> `test_command` only when there is no config file, detection last. Take `go_tool_prefix` from `.environment` regardless of which won; it is gitignored because it records whether *this machine* runs Go through mise.

5. **Decide the two specialist signals, strictly, from the diff itself:**
   - **Concurrency** — only if the diff adds or changes goroutines, threads, async over shared state, channels, locks, transactions, shared mutable state. A file that merely lives in a concurrent codebase is not a signal.
   - **Performance** — only if the diff adds or changes I/O, database queries, loops over unbounded input, hot-path allocation, or there is a benchmark that could measure it.

   Be strict. Each `true` costs a full agent, and a specialist lens with nothing to judge returns nothing — measured five times out of five in earlier runs. Each `false` is reported as a coverage gap, which is the honest way to skip something.

6. **Run `clerk lint --json`** over the same range — `--staged` for staged changes, otherwise `--base <the base you resolved>`. It exits 1 when it finds something, which is a result rather than a failure. Keep its findings; they are deterministic, need no verification, and go straight into the report with `lens: "clerk-lint"`. If the command does not exist, note that — a lens may only stand down on the strength of it having actually run.

7. **Write a two-sentence summary** of what the change set does. Every lens gets it.
