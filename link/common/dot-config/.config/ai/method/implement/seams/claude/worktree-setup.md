### Set up an isolated worktree

`clerk prepare` reported whether the tree is `clean`. If it is not, stop and ask — never build on top of someone else's loose work.

Then **work in a worktree**, unless `in_place` is on — from the request, or from the repo settings `clerk prepare` reported in `flags`. This is not ceremony: the whole feature lands on a branch in a directory of its own, so the user's checkout stays free to browse, run and edit while you build, and nothing they do mid-run can end up swept into one of your commits. That sweep is a real failure mode, not a hypothetical.

**If `clerk prepare` reported a `resume.worktree`**, that run already has a home: call **EnterWorktree** with its `path` to switch into it, and do not pass `name`. Creating a second one for the same feature is how the first one's commits get stranded.

Otherwise create it, then enter it:

```
clerk worktree <kebab-feature-name>
```

It puts the tree beside the git dir — under `.claude/worktrees/` when it can see it is running inside Claude Code, `.worktrees/` under any other harness — branches from HEAD (`--base <ref>` to branch from elsewhere), and adds whichever directory it used to the repo's `info/exclude` so the directory it just made does not read as a dirty tree to the next `clerk prepare`. It reports the `path` and the `dir` it chose, and whether it `created` the worktree or `adopted` one that was already there.

Then call **EnterWorktree** with that `path` (this skill is the explicit instruction that tool requires). It switches the session's working directory into the worktree — same window, same session, no new tmux anything. Every command from here runs there, and relative paths work normally.

**Pass `path`, never `name`.** `name` is the tool's own creation mode: it takes its base ref from `worktree.baseRef` — `fresh`, meaning `origin/<default-branch>`, unless the repo says otherwise — and it has no notion of adopting the tree a stopped run left behind, so a resume through it opens a second one and strands the first's commits. `clerk worktree` decides both. The tool accepts any path registered in `git worktree list` for this repo when you enter from the launch directory, which is where this phase runs.

**A path outside `.claude/worktrees/` asks before entering, and that is not a fault to route around.** The tool waves through anything under that directory and prompts for everything else — a safety check no permission rule can allowlist and auto mode may not approve. `clerk` puts new trees there under this harness, so the prompt means you are entering a tree some other harness made, which a resume legitimately does. Approve it. Creating a second tree to dodge the dialog is how a run loses the commits it already has.

**A repo that keeps `tasks/` out of history is not a reason to skip the worktree.** A fresh checkout only ever materialises tracked files, so an excluded breakdown will not be in the new worktree — but `clerk` resolves it at the main repo root in that case and every command finds it there. `prepare` says which regime you are in: `tasks_tracked` and `tasks_home`. Building in the main checkout to stay near the breakdown trades the isolation for nothing, and it is the isolation that keeps the audit's verifiers from writing probe files into a tree you are also running a suite in.

Two consequences to hold onto:

- **The main repo root is not your cwd.** Re-run `clerk prepare` after entering: it reports `repo_root` and `work_tree` separately for exactly this reason, and the learnings file and `tasks/test-commands.json` live under the former. So does the breakdown itself when `tasks_tracked` is false.
- **The worktree branches from the current HEAD** unless you pass `--base` — so by default the feature sits on whatever the main checkout had checked out, unpushed local commits included. The `worktree.baseRef` setting governs the tool's `name` mode only and has no say here.

With `in_place` on: no worktree, but still a branch.

```
clerk branch <kebab-feature-name>
```

It branches off the default branch when that is where you are standing, switches to the branch if it already exists, and does nothing when you are already off the default branch. **The flag turns off the worktree, not the branch** — skipped once, it put a whole feature and both its audit rounds straight onto the default branch, with nothing reviewable to hand over and, had integration been off, unreviewed work left there permanently.

Then build in the main checkout. Say so in your opening summary when a config file rather than the request is what turned `in_place` on, and name the file — `--worktree` in the request overrules it for one run.
