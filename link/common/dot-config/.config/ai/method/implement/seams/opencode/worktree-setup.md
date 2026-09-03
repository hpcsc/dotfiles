### Isolate the work

`facts.clean` says whether the tree is clean. If it is not, stop and ask — never build on top of someone else's loose work.

Then **work in a worktree**, unless `in_place` is on — from the request, or from the repo settings, resolved together in `facts.flags`. This is not ceremony: the whole feature lands on a branch in a directory of its own, so the user's checkout stays free to browse, run and edit while you build, and nothing they do mid-run can end up swept into one of your commits.

**If `facts.resume.worktree` is set**, that run already has a home — `cd` to its `path` and carry on. Do not create a second one; that is how the first one's commits get stranded.

Otherwise create it and step into it:

```
cd "$(clerk isolate <kebab-feature-name> | jq -r .path)"
```

It puts the tree under `.worktrees/` beside the git dir, branches from HEAD (`--base <ref>` to branch from elsewhere), and adds `.worktrees/` to the repo's `info/exclude` so the directory it just made does not read as a dirty tree to the next step. It reports whether it `created` the worktree or `adopted` one that was already there.

Once inside, `git` and file operations run against the worktree naturally — no `-C` prefix needed. Call `clerk step` after the `cd` and read its `facts` again: they report `repo_root` and `build_tree` separately, and the learnings file and `tasks/test-commands.json` live under the former, not under your cwd. A relative path resolved in the wrong checkout is how a file looks deleted while still sitting in the other one.

**A repo that keeps `tasks/` out of history is not a reason to skip the worktree.** A fresh checkout only ever materialises tracked files, so an excluded breakdown will not be in the new worktree — but `clerk` resolves it at the main repo root in that case and every command finds it there. `facts` says which regime you are in: `tasks_tracked` and `tasks_home`. Building in the main checkout to stay near the breakdown trades the isolation for nothing, and it is the isolation that keeps the audit's verifiers from writing probe files into a tree you are also running a suite in.

**When the isolation cannot be had, fall back rather than improvise.** `clerk isolate` failing, or refusing because the branch is already checked out in the main tree, ends the same way: build `--in-place` on a feature branch, and say which you used, because it changes where the user finds the code. Switching the main checkout off that branch is the other way out of the second case — but do not create a second tree for one feature.

With `in_place` on, the same `clerk isolate <kebab-feature-name>` makes no worktree, but still a branch: it branches off the default branch when that is where you are standing, switches to the branch if it already exists, and does nothing when you are already off the default branch. **The flag turns off the worktree, not the branch** — skipped once, it put a whole feature and both its audit rounds straight onto the default branch, with nothing reviewable to hand over and, had integration been off, unreviewed work left there permanently.

Then build in the main checkout. Say so in your opening summary when a config file rather than the request is what turned `in_place` on, and name the file — `--worktree` in the request overrules it for one run.
