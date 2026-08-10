### Set up an isolated worktree

`clerk prepare` reported whether the tree is `clean`. If it is not, stop and ask — never build on top of someone else's loose work.

Then **work in a worktree**, unless the request carries `--in-place`. This is not ceremony: the whole feature lands on a branch in a directory of its own, so the user's checkout stays free to browse, run and edit while you build, and nothing they do mid-run can end up swept into one of your commits. That sweep is a real failure mode, not a hypothetical.

**If `clerk prepare` listed a worktree whose branch matches this feature**, that run already has a home: call **EnterWorktree** with its `path` to switch into it, and do not pass `name`. Creating a second one for the same feature is how the first one's commits get stranded.

Otherwise use the **EnterWorktree** tool with a `name` (this skill is the explicit instruction that tool requires). Name it for the feature. It creates the worktree under `.claude/worktrees/`, puts it on a new branch, and switches the session's working directory into it — same window, same session, no new tmux anything. Every command from here runs there, and relative paths work normally.

Two consequences to hold onto:

- **The main repo root is not your cwd.** Re-run `clerk prepare` after entering: it reports `repo_root` and `work_tree` separately for exactly this reason, and `tasks/` and the learnings file live under the former.
- **The worktree branches from `origin/<default-branch>` by default** (`worktree.baseRef`). If the work must sit on top of unpushed local commits, either set `worktree.baseRef: head` or pass `--in-place` and use an ordinary branch.

With `--in-place`: no worktree. Create a feature branch if on the default branch, and build in the main checkout.
