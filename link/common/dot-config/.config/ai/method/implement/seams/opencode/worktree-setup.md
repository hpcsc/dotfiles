### Isolate the work

`clerk prepare` reported whether the tree is `clean`. If it is not, stop and ask — never build on top of someone else's loose work.

Then **work in a worktree**, unless the request carries `--in-place`. This is not ceremony: the whole feature lands on a branch in a directory of its own, so the user's checkout stays free to browse, run and edit while you build, and nothing they do mid-run can end up swept into one of your commits.

**If `clerk prepare` listed a worktree whose branch matches this feature**, that run already has a home — `cd` to its `path` and carry on. Do not `git worktree add` a second one; that is how the first one's commits get stranded.

Otherwise create it:

```
WT="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/../wt-<kebab-feature-name>"
git worktree add -b <kebab-feature-name> "$WT"
cd "$WT"
```

Once inside, `git` and file operations run against the worktree naturally — no `-C` prefix needed. Re-run `clerk prepare` after `cd`: it reports `repo_root` and `work_tree` separately, and the learnings file and `tasks/test-commands.json` live under the former, not under your cwd.

**A repo that keeps `tasks/` out of history is not a reason to skip the worktree.** A fresh checkout only ever materialises tracked files, so an excluded breakdown will not be in the new worktree — but `clerk` resolves it at the main repo root in that case and every command finds it there. `prepare` says which regime you are in: `tasks_tracked` and `tasks_home`. Building in the main checkout to stay near the breakdown trades the isolation for nothing, and it is the isolation that keeps the audit's verifiers from writing probe files into a tree you are also running a suite in.

With `--in-place`: no worktree. `git switch -c <kebab-feature-name>` if on the default branch, and build in the main checkout.
