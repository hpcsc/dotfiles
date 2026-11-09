---
name: push-pr
argument-hint: nothing, or --base <branch>, --yes, --draft, --no-watch
description: Rebase the current branch onto the latest origin default branch (master or main), push it, open a pull request when none is open, then watch the pull request for review comments and act on each one. When a pull request is open already, rebase, push and watch. A script does the git and GitHub steps and stops at each decision. Use when asked to rebase onto the latest master or main and push, to push a branch and raise its PR, or to watch a PR for review comments.
---

Rebase the current branch onto the latest default branch, push it, make sure that it has a pull request, and watch the pull request for review comments: $ARGUMENTS

The script `~/.claude/skills/push-pr/push-pr.py` does every git and GitHub step. At each point that needs a decision, it stops and prints one JSON object and an exit code. Your work is the decisions: a conflict, a force push, the text of a new pull request, and each review comment. Do not do a step by hand when the script has a command for it.

## Arguments

| Argument | Effect |
| --- | --- |
| nothing | Rebase onto the default branch of `origin` |
| `--base <branch>` | Rebase onto this branch. Pass it to each `sync` and `push` |
| `--yes` | The user agrees to the force push after the rebase. Do not ask before that push. Later pushes in this run still need a question |
| `--draft` | Open a new pull request as a draft |
| `--no-watch` | Stop after the push and the pull request |

## The script

In the commands below, `$P` is `python3 ~/.claude/skills/push-pr/push-pr.py`. Run it from the repository.

| Command | What it does |
| --- | --- |
| `$P status` | Shows the branch, the base, the remote head, the open pull request, and the count of commits ahead and behind. Changes nothing |
| `$P sync [--base B] [--force]` | Does the checks, fetches, rebases onto the base, and pushes |
| `$P push [--base B] [--force]` | Does the checks and pushes. It does not rebase |
| `$P comments [--pr N] [--all]` | Shows the unresolved review threads, the reviews and the conversation comments. `--all` adds the resolved threads |
| `$P watch [--pr N] [--interval S]` | Prints one line for each new comment from another person. Stops when the pull request closes |
| `$P reply <id> --body-file F [--resolve]` | Posts a reply. `--resolve` also resolves the review thread |

`sync` and `push` do these things, so you do not do them again:

- `sync` reads the SHA of the base from the remote once, and rebases onto that SHA. Another session can move `origin/master` in a shared clone, and this SHA does not move with it.
- The rebase runs with `rebase.updateRefs=false` and `rebase.autoStash=false`. It writes the old head to `refs/push-pr/before-rebase/<branch>` before it starts.
- A new branch gets a plain push. A branch that only adds commits gets a fast-forward push. Only a push that replaces remote commits needs `--force`. The force push uses `--force-with-lease` with the remote SHA that the script read.
- The push refuses when the remote branch has a commit that this checkout never had. A clean merge of the base into the branch, from the GitHub "Update branch" button, does not count.

Give each `sync` and `push` call a timeout of 10 minutes, because a pre-push hook can run lint or tests.

If the harness denies a script command, do not do that step another way. Give the user the same command with a `!` before it, for example `! python3 ~/.claude/skills/push-pr/push-pr.py push --force`, and continue after the user runs it.

## Step 1: rebase and push

Run `$P sync`. Then act on the exit code and the `result` field:

| Exit | `result` | Do this |
| --- | --- | --- |
| 0 | `done` | Report `rebase.base_moved_by` and `push.pushed`. Go to step 4 |
| 2 | `conflict` | Go to step 3 |
| 3 | `uncommitted-changes` | Show the files. Ask the user to fold them into the commits that they fix, or to stop. After a fold, run `sync` again. Do not stash, discard or `git add -A` them |
| 3 | `pr-merges-into-another-branch` | The pull request is stacked on another branch. Ask the user: rebase onto that branch with `--base <its name>`, or stop. Do not rebase a stacked branch onto the default branch, because the commits of the lower branch then come into this pull request |
| 3 | `rebase-in-progress` and the other operations | Report it and ask the user |
| 3 | `on-base-branch`, `detached-head`, `nothing-to-push` | Report it and stop |
| 4 | `needs-force` | Go to step 2 |
| 5 | `unknown-remote-commits` | Show each commit and its author. Stop and ask the user. A push replaces these commits |
| 1 | any | Show `stderr` and stop. For `push-failed`, show the hook output. Fix it only when the failure is in the code of this branch |

When `rebase.commits.dropped` is not empty, name each dropped commit to the user. Git drops a commit when the base already has its change, for example after the merge of a lower pull request. If the base does not have that change, the work is lost from the branch. Get it back from `refs/push-pr/before-rebase/<branch>`.

## Step 2: the force push

The push replaces the commits on the remote branch. Ask the user before each force push, unless `--yes` covers it. Use AskUserQuestion, and put these facts in the question:

- How many commits the base moved (`rebase.base_moved_by`).
- The commits that are the same, changed, dropped and added (`commits`). After a plain rebase, all of them are the same.
- The review decision of the pull request (`pr.reviewDecision`). When it is `APPROVED`, say that a push can dismiss the approval.

The options are "Force push" and "Stop". After "Force push", run `$P push --force` with the same `--base`. Then go to step 4.

## Step 3: a conflict

The rebase stays in progress. `stopped_at` names the commit that git applies, and `conflicted_files` names the files. For each file:

1. Read the file. `git show REBASE_HEAD -- <file>` shows the change of the branch. `git log --oneline <before_rebase>..<base_sha> -- <file>` shows the commits of the base that changed the file.
2. Keep the change of the base, and put the change of the branch on it. Resolve the file only when the intent of the two sides is clear.
3. Stage the file by its path.

Then run `GIT_EDITOR=true git rebase --continue`, and do the same at each stop. When the rebase completes, build and test the packages of the conflicted files: a merge of two changes can fail when each change alone passes. Then run `$P sync` again. It finds the branch on the base and goes to the push.

Run `git rebase --abort` and ask the user when a resolution is not clear. Do the same when the conflict is in a commit that a merged pull request already has, which happens to a stacked branch after its lower branch merges. For that case, the fix is `git rebase --onto <base_sha> <the old tip of the lower branch>`, and the user decides.

## Step 4: the pull request

- When `pr` is set, report its URL.
- When `pr` is null, use the Skill tool to run `write-pr` with no arguments. With `--draft`, tell it to open a draft. The branch is on the remote now, so `write-pr` creates the pull request. Then run `$P status`, and check that `pr` is set.

## Step 5: the open comments

Do this step only for a pull request that was open before this run. Run `$P comments`. Act on these items as in step 7:

- Each thread where `waits_for_answer` is true.
- Each review with the state `CHANGES_REQUESTED`.
- Each conversation comment from another person after your last comment.

## Step 6: watch

Skip this step with `--no-watch`. Start the Monitor tool with these values:

- `command`: `python3 ~/.claude/skills/push-pr/push-pr.py watch`
- `description`: `review comments on PR #<number>`
- `timeout_ms`: `1800000`

When the monitor expires, start it again with the same values. The script keeps the ids of the comments that it showed in `<git common dir>/push-pr/`, so a new watch shows only the newer comments. When the pull request merges or closes, the watch prints one line and stops. Then report it and end.

These are the lines that the watch prints:

```
PR #8311: the watch starts. Review decision: REVIEW_REQUIRED. 2 unresolved review threads wait for an answer. push-pr.py comments shows them
PR #8311: review comment c4508255133 by alice on collect/a.go:77: <the first 200 characters> <url>
PR #8311: review r5763939985 APPROVED by bob: (no text) <url>
PR #8311: conversation comment i6623306340 by enterprise-claude-reviewer: ## Summary ... <url>
PR #8311: 14 new comments. push-pr.py comments shows them
PR #8311: the watch cannot read the pull request: <error>
PR #8311 is merged. The watch stops
```

The watch leaves out the comments of the `gh` user, so the replies that you post do not come back as events.

## Step 7: act on a comment

1. Run `$P comments` and read the full text of the comment and its thread.
2. Sort the comment:

   | The comment | Do this |
   | --- | --- |
   | An approval with no text | Report it |
   | A bot comment with no finding, for example the Linear link | Nothing |
   | A finding or a requested change, from a person or a review bot | Read the code at that line on the current branch. When the claim is correct, fix it. When it is not correct, write a reply that shows why |
   | A question | Answer it from the code. Write a reply |
   | A design question, or a disagreement | Do not change the code. Write an answer for the user to decide |

3. Fold each fix into the commit that added the code, as `~/.config/ai/guidelines/git/commits.md` sections 2 and 4 say. Use `rebase.base_sha` from the last `sync` as the base of the fold, not `origin/<base>`. Stage files by path. Run the tests of the changed packages.
4. Collect the fixes and replies for the comments that came in together. Then ask the user one question that shows the changed commits, the full text of each reply, and the force push. When the user can be away from the terminal, send a PushNotification first, for example `PR #8311: 2 review comments, fixes ready, need your OK to push`.
5. After "yes", run `$P push --force`. Then write each reply to a file in the scratchpad, and run `$P reply <id> --body-file <file>`. Add `--resolve` only to a thread whose requested change is in the push. Leave questions and disagreements open for the reviewer.

Write each reply in Simplified Technical English (`~/.config/ai/guidelines/writing/asd-ste100.md`), in one to three sentences. Say what changed and in which commit, or give the answer and its evidence. Do not write an `@` mention: GitHub notifies the reviewer of a reply in their thread.

Then go on with the watch.

## Do not

- Run `git push --force`, `git stash` or `git add -A` yourself.
- Rebase onto `origin/<base>` by name. The script pins the SHA.
- Edit the pull request description. `write-pr` owns it.
- Post a reply or push a fix before the user agrees.
