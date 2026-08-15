### Set up an isolated worktree

`clerk prepare` reported whether the tree is `clean`. If it is not, stop and ask — never build on top of someone else's loose work.

Then **work in a worktree**, unless `in_place` is on — from the request, or from the repo settings `clerk prepare` reported in `flags`. This is not ceremony: the whole feature lands on a branch in a directory of its own, so the user's checkout stays free to browse, run and edit while you build, and nothing they do mid-run can end up swept into one of your commits. That sweep is a real failure mode, not a hypothetical.

**If `clerk prepare` reported a `resume.worktree`**, that run already has a home: call **EnterWorktree** with its `path` to switch into it, and do not pass `name`. Creating a second one for the same feature is how the first one's commits get stranded.

Otherwise create it with git, then enter it:

```
GIT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir)"
WT="$(dirname "$GIT_COMMON")/.worktrees/<kebab-feature-name>"
grep -qxF '.worktrees/' "$GIT_COMMON/info/exclude" 2>/dev/null || printf '.worktrees/\n' >> "$GIT_COMMON/info/exclude"
git worktree add -b <kebab-feature-name> "$WT"
```

Then call **EnterWorktree** with that path as `path` (this skill is the explicit instruction that tool requires). It switches the session's working directory into the worktree — same window, same session, no new tmux anything. Every command from here runs there, and relative paths work normally.

**Pass `path`, never `name`.** `name` is the tool's own creation mode and it puts the worktree under `.claude/worktrees/`, which is compiled in and takes no setting — so `name` is simply unable to honour the location this method uses. Creating it with git first and entering by path is what makes the two harnesses put the work in the same place. The tool accepts any path registered in `git worktree list` for this repo when you enter from the launch directory, which is where this phase runs.

**The exclude line is not tidiness.** `.worktrees/` sits inside the repo, so without it the new directory shows up as untracked — and `clerk`'s `clean` is `git status --porcelain`, which counts untracked files. The next `clerk prepare` from the main checkout would report a dirty tree and this skill would stop and ask about loose work that is only its own worktree. It goes in `info/exclude` rather than `.gitignore` because editing a tracked file to hide a scratch directory is itself an uncommitted change, and `$GIT_COMMON` resolves to the main `.git` from inside any worktree, so the line is written once per repo.

**A repo that keeps `tasks/` out of history is not a reason to skip the worktree.** A fresh checkout only ever materialises tracked files, so an excluded breakdown will not be in the new worktree — but `clerk` resolves it at the main repo root in that case and every command finds it there. `prepare` says which regime you are in: `tasks_tracked` and `tasks_home`. Building in the main checkout to stay near the breakdown trades the isolation for nothing, and it is the isolation that keeps the audit's verifiers from writing probe files into a tree you are also running a suite in.

Two consequences to hold onto:

- **The main repo root is not your cwd.** Re-run `clerk prepare` after entering: it reports `repo_root` and `work_tree` separately for exactly this reason, and the learnings file and `tasks/test-commands.json` live under the former. So does the breakdown itself when `tasks_tracked` is false.
- **The worktree branches from the current HEAD**, because `git worktree add` was given no other base — so the feature sits on whatever the main checkout had checked out, unpushed local commits included. The `worktree.baseRef` setting governs the tool's `name` mode only and has no say here. To branch from somewhere else, pass that ref as a final argument to `git worktree add`.

With `in_place` on: no worktree. Create a feature branch if on the default branch, and build in the main checkout. Say so in your opening summary when a config file rather than the request is what turned it on, and name the file — `--worktree` in the request overrules it for one run.
