### Isolate the work

`clerk prepare` reported whether the tree is `clean`. If it is not, stop and ask — never build on top of someone else's loose work.

Then **work in a worktree**, unless `in_place` is on — from the request, or from the repo settings `clerk prepare` reported in `flags`. This is not ceremony: the whole feature lands on a branch in a directory of its own, so the user's checkout stays free to browse, run and edit while you build, and nothing they do mid-run can end up swept into one of your commits.

**If `clerk prepare` listed a worktree whose branch matches this feature**, that run already has a home — `cd` to its `path` and carry on. Do not `git worktree add` a second one; that is how the first one's commits get stranded.

Otherwise create it:

```
GIT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir)"
WT="$(dirname "$GIT_COMMON")/.worktrees/<kebab-feature-name>"
grep -qxF '.worktrees/' "$GIT_COMMON/info/exclude" 2>/dev/null || printf '.worktrees/\n' >> "$GIT_COMMON/info/exclude"
git worktree add -b <kebab-feature-name> "$WT"
cd "$WT"
```

**The exclude line is not tidiness.** `.worktrees/` sits inside the repo, so without it the new directory shows up as untracked — and `clerk`'s `clean` is `git status --porcelain`, which counts untracked files. The next `clerk prepare` from the main checkout would report a dirty tree and this skill would stop and ask about loose work that is only its own worktree. It goes in `info/exclude` rather than `.gitignore` because editing a tracked file to hide a scratch directory is itself an uncommitted change, and `$GIT_COMMON` resolves to the main `.git` from inside any worktree, so the line is written once per repo.

Once inside, `git` and file operations run against the worktree naturally — no `-C` prefix needed. Re-run `clerk prepare` after `cd`: it reports `repo_root` and `work_tree` separately, and the learnings file and `tasks/test-commands.json` live under the former, not under your cwd.

**A repo that keeps `tasks/` out of history is not a reason to skip the worktree.** A fresh checkout only ever materialises tracked files, so an excluded breakdown will not be in the new worktree — but `clerk` resolves it at the main repo root in that case and every command finds it there. `prepare` says which regime you are in: `tasks_tracked` and `tasks_home`. Building in the main checkout to stay near the breakdown trades the isolation for nothing, and it is the isolation that keeps the audit's verifiers from writing probe files into a tree you are also running a suite in.

With `in_place` on: no worktree. `git switch -c <kebab-feature-name>` if on the default branch, and build in the main checkout. Say so in your opening summary when a config file rather than the request is what turned it on, and name the file — `--worktree` in the request overrules it for one run.
