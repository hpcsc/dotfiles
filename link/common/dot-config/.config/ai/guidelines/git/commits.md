# Commits

A branch is a list of logical changes. It is not a record of the order in which you did the work. A
reviewer reads one commit at a time, and a later reader reverts or cherry-picks one commit at a time.
Each commit must make sense alone.

## 1. One logical change in each commit

- A commit does one thing. The build and the tests pass at that commit.
- Put unrelated changes in separate commits, also when one review found all of them.
- When a change adds a capability and connects it to production, put the connection in the last
  commit. Then one revert takes the capability out of production.
- Stage each file by its path. Do not use `git add -A` or `git add .`: they also add files that
  are not part of the change.

## 2. A fix goes into the commit that added the code

When you fix code that an earlier commit on the branch added, fold the fix into that commit. Do not
add a fix commit on top.

This applies to every kind of fix: a review finding, a lint or test failure, a rename, a comment
that you remove, a test that you fold into another test.

- Bad: `Address review feedback`, on top of the three commits that it corrects.
- Good: each correction is part of the commit that it corrects. A reader sees the code and its fix
  in one commit.

Three cases need more than one step:

- When a fix changes code from two commits, split the fix. Each part goes into the commit that
  added that code.
- When a fold gives a conflict, stop the fold (`git rebase --abort`). Keep the fix as its own
  commit, and say in the message what it fixes.
- Code that no commit on the branch added is new work. It gets its own commit.

Before you open a pull request, read the history of the branch. Squash the commits that are one
logical change, for example a commit and the follow-up that completes it.

## 3. A pushed branch

Fold fixes into a branch that you pushed before, in the same way. A fold changes the commits, so
the branch then needs a force push.

- Ask the user before each force push. Say which commits changed, and why.
- Push with `git push --force-with-lease`, not `--force`. `--force-with-lease` refuses when someone
  else pushed to the branch after you.
- Do not rewrite a commit that is already on the remote default branch. A fix for that code is a
  new commit.

## 4. How to fold

| The fix corrects | Do this |
| --- | --- |
| The last commit | Stage the fix. Then `git commit --amend --no-edit` |
| An earlier commit | `git commit --fixup=<sha>`. Then `GIT_SEQUENCE_EDITOR=true git rebase --autosquash <base>` |

`<base>` is the commit that the branch starts from, for example `origin/master`.
`GIT_SEQUENCE_EDITOR=true` accepts the plan that git writes, so the rebase does not wait for an
editor. `--autosquash` without `-i` needs git 2.44 or later.

`clerk fixup` does the same work, and finds the target commit from the files that the fix changed:

```
clerk fixup mark --base <base> -- <the files that the fix changed>
clerk fixup replay --base <base>
```

It also folds in a repository whose commit-msg hook refuses `fixup!` subjects. On a pushed branch,
`replay` refuses until you add `--force`. That flag changes only the local branch. The push after it
is a force push, so ask the user first (section 3).

## 5. The message

The message says what the commit changes and why. It does not say who asked for the change or which
review found the problem: a later reader does not have that context.

"What the commit changes" is what the code does differently, as a user or a reviewer sees it. It is not
a list of each change in the diff. Do not list the types, functions, fields or files that changed, or
what each one got: the diff shows that. Name code only when the reader needs the name to follow the
what or the why.

- Bad: `RetryPolicy gets a Backoff field. Client.Send reads it and calls time.Sleep before each retry.`
- Good: `The first retry now waits 5 seconds, and each later retry waits twice as long as the one before.`

A sentence that says why the code does something unexpected is part of the why, and stays:
`the action is start_search, not search, because search collides with the [keys.search] table`.

For the words, follow `writing/asd-ste100.md`. Where the repository has its own commit conventions,
follow the repository.
