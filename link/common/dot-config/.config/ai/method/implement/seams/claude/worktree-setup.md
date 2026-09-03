### Set up an isolated worktree

`facts.clean` says whether the tree is clean. If it is not, stop and ask — never build on top of someone else's loose work.

Then **work in a worktree**, unless `in_place` is on — from the request, or from the repo settings, resolved together in `facts.flags`. This is not ceremony: the whole feature lands on a branch in a directory of its own, so the user's checkout stays free to browse, run and edit while you build, and nothing they do mid-run can end up swept into one of your commits. That sweep is a real failure mode, not a hypothetical.

**If `facts.resume.worktree` is set**, that run already has a home: call **EnterWorktree** with its `path` to switch into it, and do not pass `name`. Creating a second one for the same feature is how the first one's commits get stranded.

Otherwise create it, then enter it:

```
clerk isolate <kebab-feature-name>
```

It puts the tree beside the git dir — under `.claude/worktrees/` when it can see it is running inside Claude Code, `.worktrees/` under any other harness — branches from HEAD (`--base <ref>` to branch from elsewhere), and adds whichever directory it used to the repo's `info/exclude` so the directory it just made does not read as a dirty tree to the next step. It reports the `path` and the `dir` it chose, and whether it `created` the worktree or `adopted` one that was already there.

Then call **EnterWorktree** with that `path` (this skill is the explicit instruction that tool requires). It switches the session's working directory into the worktree — same window, same session, no new tmux anything. Every command from here runs there, and relative paths work normally.

**Pass `path`, never `name`.** `name` is the tool's own creation mode: it takes its base ref from `worktree.baseRef` — `fresh`, meaning `origin/<default-branch>`, unless the repo says otherwise — and it has no notion of adopting the tree a stopped run left behind, so a resume through it opens a second one and strands the first's commits. `clerk isolate` decides both. The tool accepts any path registered in `git worktree list` for this repo when you enter from the launch directory, which is where this phase runs.

**A path outside `.claude/worktrees/` asks before entering, and that is not a fault to route around.** The tool waves through anything under that directory and prompts for everything else — a safety check no permission rule can allowlist and auto mode may not approve. `clerk` puts new trees there under this harness, so the prompt means you are entering a tree some other harness made, which a resume legitimately does. Approve it. Creating a second tree to dodge the dialog is how a run loses the commits it already has.

**A repo that keeps `tasks/` out of history is not a reason to skip the worktree.** A fresh checkout only ever materialises tracked files, so an excluded breakdown will not be in the new worktree — but `clerk` resolves it at the main repo root in that case and every command finds it there. `facts` says which regime you are in: `tasks_tracked` and `tasks_home`. Building in the main checkout to stay near the breakdown trades the isolation for nothing, and it is the isolation that keeps the audit's verifiers from writing probe files into a tree you are also running a suite in.

Two consequences to hold onto:

- **The main repo root is not your cwd.** Call `clerk step` after entering and read its `facts` again: they report `repo_root` and `build_tree` separately for exactly this reason, and the learnings file and `tasks/test-commands.json` live under the former. So does the breakdown itself when `tasks_tracked` is false.
- **The worktree branches from the current HEAD** unless you pass `--base` — so by default the feature sits on whatever the main checkout had checked out, unpushed local commits included. The `worktree.baseRef` setting governs the tool's `name` mode only and has no say here.

**When the isolation cannot be had, fall back rather than improvise.** `clerk isolate` failing, `EnterWorktree` being unavailable, or the branch already being checked out in the main tree all end the same way: build `--in-place` on a feature branch in the main checkout, and say which you used, because it changes where the user finds the code. Switching the main checkout off that branch is the other way out of the third case — but do not create a second tree for one feature. And if `EnterWorktree` refuses the path, check that `clerk isolate` actually reported one and that you have not already switched trees: it takes a path already in `git worktree list` for this repo, entered from the launch directory.

With `in_place` on, the same `clerk isolate <kebab-feature-name>` makes no worktree, but still a branch: it branches off the default branch when that is where you are standing, switches to the branch if it already exists, and does nothing when you are already off the default branch. **The flag turns off the worktree, not the branch** — skipped once, it put a whole feature and both its audit rounds straight onto the default branch, with nothing reviewable to hand over and, had integration been off, unreviewed work left there permanently.

Then build in the main checkout. Say so in your opening summary when a config file rather than the request is what turned `in_place` on, and name the file — `--worktree` in the request overrules it for one run.
