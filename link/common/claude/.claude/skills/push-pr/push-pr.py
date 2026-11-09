#!/usr/bin/env python3
"""push-pr: rebase the current branch onto the latest origin default branch, push it,
and watch its pull request for review comments.

    push-pr.py status   [--base <branch>]
    push-pr.py sync     [--base <branch>] [--force]
    push-pr.py push     [--base <branch>] [--force]
    push-pr.py comments [--pr <n>] [--all]
    push-pr.py watch    [--pr <n>] [--interval <seconds>] [--once]
    push-pr.py reply    <id> --body-file <file> [--pr <n>] [--resolve]

sync fetches, rebases onto the base and pushes. The base is the default branch, or the
branch that --base names. Every command except watch prints one JSON object. watch prints
one line for each new review, review comment and conversation comment from another person,
and stops when the pull request closes. An id is c<n> for a review comment, r<n> for a
review and i<n> for a conversation comment.

Exit codes:
  0  done
  1  error
  2  the rebase stopped on a conflict, and the rebase stays in progress
  3  a check failed: the tree has changes, an operation is in progress, the branch is the
     base, the pull request merges into another branch, or there is nothing to push
  4  the push replaces commits on the remote branch, and needs --force
  5  the remote branch has commits that this checkout never had
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

REMOTE = "origin"
BACKUP_REF = "refs/push-pr/before-rebase/"
DONE, ERROR, CONFLICT, REFUSED, NEEDS_FORCE, UNKNOWN_COMMITS = 0, 1, 2, 3, 4, 5
EXCERPT_LENGTH = 200
MAX_LINES_PER_POLL = 10
FAILURES_BEFORE_REPORT = 3

OPERATIONS = {
    "rebase-merge": "rebase",
    "rebase-apply": "rebase",
    "MERGE_HEAD": "merge",
    "CHERRY_PICK_HEAD": "cherry-pick",
    "REVERT_HEAD": "revert",
}

RANGE_DIFF_ROW = re.compile(r"^\s*(?:\d+|-):\s+(?:[0-9a-f]+|-+)\s+([=!<>])\s+(?:\d+|-):\s+(?:[0-9a-f]+|-+)\s+(.*)$")
RANGE_DIFF_KINDS = {"=": "same", "!": "changed", "<": "dropped", ">": "added"}

PR_QUERY = """
query($owner: String!, $name: String!, $number: Int!) {
  viewer { login }
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      number url state reviewDecision
      reviews(last: 100) { nodes { databaseId state body submittedAt url author { login } } }
      comments(last: 100) { nodes { databaseId body createdAt url author { login } } }
      reviewThreads(first: 100) {
        nodes {
          id isResolved isOutdated path line originalLine
          comments(first: 100) { nodes { databaseId body createdAt url author { login } } }
        }
      }
    }
  }
}
"""

RESOLVE_THREAD = """
mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { isResolved } } }
"""


class Stop(Exception):
    def __init__(self, code, result, **fields):
        super().__init__(result)
        self.code = code
        self.fields = {"result": result, **fields}


class Parser(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        print(f"{self.prog}: error: {message}", file=sys.stderr)
        sys.exit(ERROR)


def run(*args, check=True, stdin=None, env=None):
    given = {"input": stdin} if stdin is not None else {"stdin": subprocess.DEVNULL}
    try:
        done = subprocess.run(args, capture_output=True, text=True, env=env, **given)
    except FileNotFoundError:
        raise Stop(ERROR, "missing-tool", message=f"{args[0]} is not on PATH")
    if check and done.returncode != 0:
        shown = " ".join(arg if len(arg) <= 80 else arg[:79] + "…" for arg in args)
        raise Stop(ERROR, "command-failed", command=shown, stderr=done.stderr.strip())
    return done


def git(*args, check=True):
    return run("git", *args, check=check).stdout.rstrip()


def gh_json(*args, stdin=None):
    out = run("gh", *args, stdin=stdin).stdout
    try:
        return json.loads(out or "null")
    except ValueError:
        raise Stop(ERROR, "bad-json", command=" ".join(args[:2]), stdout=out[:500])


def say(line):
    print(line, flush=True)


def git_path(name):
    return Path(git("rev-parse", "--git-path", name))


def operation_in_progress():
    for name, operation in OPERATIONS.items():
        if git_path(name).exists():
            return operation
    return None


def current_branch():
    branch = git("symbolic-ref", "--quiet", "--short", "HEAD", check=False)
    if branch:
        return branch
    for name in ("rebase-merge", "rebase-apply"):
        head_name = git_path(f"{name}/head-name")
        if head_name.exists():
            return head_name.read_text().strip().removeprefix("refs/heads/")
    return None


def default_branch():
    tracked = git("symbolic-ref", "--quiet", "--short", f"refs/remotes/{REMOTE}/HEAD", check=False)
    if tracked:
        return tracked.split("/", 1)[1]
    for line in git("ls-remote", "--symref", REMOTE, "HEAD").splitlines():
        if line.startswith("ref: refs/heads/"):
            return line.split()[1].removeprefix("refs/heads/")
    raise Stop(ERROR, "no-default-branch", message=f"{REMOTE} names no default branch")


def remote_heads(*branches):
    heads = {}
    for line in git("ls-remote", REMOTE, *[f"refs/heads/{b}" for b in branches]).splitlines():
        sha, ref = line.split("\t")
        heads[ref.removeprefix("refs/heads/")] = sha
    return heads


def has_commit(sha):
    return run("git", "cat-file", "-e", f"{sha}^{{commit}}", check=False).returncode == 0


def is_ancestor(older, newer):
    return run("git", "merge-base", "--is-ancestor", older, newer, check=False).returncode == 0


def count(revision_range):
    return int(git("rev-list", "--count", revision_range))


def fetch(*branches):
    git("fetch", "--quiet", "--no-tags", REMOTE, *branches)


def open_pr(branch):
    prs = gh_json("pr", "list", "--head", branch, "--state", "open", "--json",
                  "number,url,baseRefName,isDraft,reviewDecision,isCrossRepository")
    prs = [pr for pr in prs or [] if not pr.pop("isCrossRepository", False)]
    return prs[0] if prs else None


def base_for(pr, requested):
    if requested:
        return requested
    default = default_branch()
    if pr and pr["baseRefName"] != default:
        raise Stop(REFUSED, "pr-merges-into-another-branch", pr=pr, default_branch=default,
                   message=f"PR #{pr['number']} merges into {pr['baseRefName']}, not {default}. "
                           f"Pass --base to choose the branch to rebase onto")
    return default


def check_ready(branch, base):
    if branch is None:
        raise Stop(REFUSED, "detached-head", message="HEAD is on no branch")
    operation = operation_in_progress()
    if operation:
        raise Stop(REFUSED, f"{operation}-in-progress", branch=branch,
                   message=f"finish or abort the {operation} first")
    if branch == base:
        raise Stop(REFUSED, "on-base-branch", branch=branch,
                   message=f"{branch} is the base branch. Switch to a feature branch")
    changed = run("git", "status", "--porcelain", "--untracked-files=no").stdout.splitlines()
    if changed:
        raise Stop(REFUSED, "uncommitted-changes", branch=branch, files=[line[3:] for line in changed],
                   message="commit the changes or set them aside first")


def range_diff(base, old_head, new_head):
    rows = {kind: [] for kind in RANGE_DIFF_KINDS.values()}
    for line in git("range-diff", "--no-color", base, old_head, new_head).splitlines():
        match = RANGE_DIFF_ROW.match(line)
        if match:
            rows[RANGE_DIFF_KINDS[match.group(1)]].append(match.group(2))
    return {"same": len(rows.pop("same")), **rows}


def rebase(branch, base, base_sha):
    head = git("rev-parse", "HEAD")
    start = git("merge-base", "HEAD", base_sha)
    moved = count(f"{start}..{base_sha}")
    if moved == 0:
        return {"rebased": False, "base": base, "base_sha": base_sha, "head": head}
    git("update-ref", BACKUP_REF + branch, head)
    done = run("git", "-c", "rebase.updateRefs=false", "-c", "rebase.autoStash=false", "rebase", "--quiet", base_sha,
               check=False, env={**os.environ, "GIT_EDITOR": "true"})
    if done.returncode != 0:
        if not operation_in_progress():
            raise Stop(ERROR, "rebase-failed", stderr=done.stderr.strip())
        raise Stop(CONFLICT, "conflict", branch=branch, base=base, base_sha=base_sha,
                   before_rebase=head, backup_ref=BACKUP_REF + branch,
                   stopped_at=git("log", "-1", "--format=%h %s", "REBASE_HEAD", check=False),
                   conflicted_files=git("diff", "--name-only", "--diff-filter=U").splitlines(),
                   message="resolve the files, git add them, then GIT_EDITOR=true git rebase --continue; "
                           "or git rebase --abort")
    new_head = git("rev-parse", "HEAD")
    return {"rebased": True, "base": base, "base_sha": base_sha, "base_moved_by": moved,
            "before_rebase": head, "head": new_head, "backup_ref": BACKUP_REF + branch,
            "commits": range_diff(base_sha, head, new_head)}


def is_clean_merge_of_base(sha, parents, base_sha):
    return (len(parents) > 1
            and all(is_ancestor(parent, base_sha) for parent in parents[1:])
            and not git("diff-tree", "--cc", "--no-commit-id", "-r", sha))


def unknown_commits(branch, remote_sha, base_sha):
    known = set(git("log", "-g", "-n", "1000", "--format=%H", f"refs/heads/{branch}", check=False).split())
    known.update([git("rev-parse", "HEAD"), base_sha])
    listed = git("rev-list", "--no-commit-header", "--format=%H %P%x09%an%x09%s", remote_sha, "--not", *known)
    unknown = []
    for line in listed.splitlines():
        shas, author, subject = line.split("\t", 2)
        sha, *parents = shas.split()
        if not is_clean_merge_of_base(sha, parents, base_sha):
            unknown.append({"sha": sha[:12], "author": author, "subject": subject})
    return unknown


def push_to_remote(branch, lease=None):
    args = ["push", "--quiet", "--set-upstream"]
    if lease:
        args.append(f"--force-with-lease={branch}:{lease}")
    done = run("git", *args, REMOTE, f"refs/heads/{branch}:refs/heads/{branch}", check=False)
    if done.returncode != 0:
        raise Stop(ERROR, "push-failed", stderr=done.stderr.strip())


def push(branch, base_sha, force):
    head = git("rev-parse", "HEAD")
    remote_sha = remote_heads(branch).get(branch)
    if remote_sha == head:
        return {"pushed": "nothing", "head": head}
    if remote_sha is None:
        push_to_remote(branch)
        return {"pushed": "new-branch", "head": head}
    if not has_commit(remote_sha):
        fetch(branch)
    if is_ancestor(remote_sha, head):
        push_to_remote(branch)
        return {"pushed": "fast-forward", "remote_before": remote_sha, "head": head}
    unknown = unknown_commits(branch, remote_sha, base_sha)
    if unknown:
        raise Stop(UNKNOWN_COMMITS, "unknown-remote-commits", remote=remote_sha, commits=unknown,
                   message="the remote branch has commits that this checkout never had. "
                           "A push replaces them, so bring them in first")
    replaced = range_diff(base_sha, remote_sha, head)
    if not force:
        raise Stop(NEEDS_FORCE, "needs-force", remote=remote_sha, head=head, commits=replaced,
                   message="the push replaces the commits on the remote branch. "
                           "Run push --force when the user agrees")
    push_to_remote(branch, lease=remote_sha)
    return {"pushed": "force", "remote_before": remote_sha, "head": head, "commits": replaced}


def cmd_status(args):
    branch = current_branch()
    pr = open_pr(branch) if branch else None
    base = args.base or (pr["baseRefName"] if pr else default_branch())
    heads = remote_heads(*{base, branch} - {None})
    changed = run("git", "status", "--porcelain", "--untracked-files=no").stdout.splitlines()
    status = {"result": "status", "branch": branch, "base": base, "operation": operation_in_progress(),
              "uncommitted_changes": [line[3:] for line in changed], "head": git("rev-parse", "HEAD"),
              "remote_head": heads.get(branch), "pr": pr}
    base_sha = heads.get(base)
    if base_sha and has_commit(base_sha):
        status["ahead_of_base"] = count(f"{base_sha}..HEAD")
        status["behind_base"] = count(f"HEAD..{base_sha}")
    return status


def cmd_sync(args):
    branch = current_branch()
    pr = open_pr(branch) if branch else None
    base = base_for(pr, args.base)
    check_ready(branch, base)
    heads = remote_heads(base, branch)
    if base not in heads:
        raise Stop(ERROR, "no-remote-base", base=base, message=f"{REMOTE} has no branch {base}")
    fetch(*heads)
    base_sha = heads[base]
    rebased = rebase(branch, base, base_sha)
    if count(f"{base_sha}..HEAD") == 0:
        raise Stop(REFUSED, "nothing-to-push", branch=branch, rebase=rebased,
                   message=f"{branch} has no commits that {base} does not have")
    try:
        pushed = push(branch, base_sha, args.force)
    except Stop as stop:
        stop.fields.update(branch=branch, rebase=rebased, pr=pr)
        raise
    return {"result": "done", "branch": branch, "rebase": rebased, "push": pushed, "pr": pr}


def cmd_push(args):
    branch = current_branch()
    pr = open_pr(branch) if branch else None
    base = base_for(pr, args.base)
    check_ready(branch, base)
    base_sha = git("rev-parse", f"refs/remotes/{REMOTE}/{base}")
    try:
        pushed = push(branch, base_sha, args.force)
    except Stop as stop:
        stop.fields.update(branch=branch, pr=pr)
        raise
    return {"result": "done", "branch": branch, "push": pushed, "pr": pr}


def resolve_pr(number):
    if number:
        pr = gh_json("pr", "view", str(number), "--json", "number,url")
    else:
        branch = current_branch()
        pr = open_pr(branch) if branch else None
        if not pr:
            raise Stop(REFUSED, "no-pr", branch=branch,
                       message="this branch has no open pull request. Pass --pr")
    owner, name = pr["url"].split("/")[3:5]
    return owner, name, pr["number"]


def read_pr(owner, name, number):
    data = gh_json("api", "graphql", "-f", f"query={PR_QUERY}", "-f", f"owner={owner}",
                   "-f", f"name={name}", "-F", f"number={number}")
    try:
        return data["data"]["viewer"]["login"], data["data"]["repository"]["pullRequest"]
    except (KeyError, TypeError):
        raise Stop(ERROR, "no-pr-data", message=f"GitHub returned no data for {owner}/{name}#{number}")


def author(node):
    return (node.get("author") or {}).get("login") or "ghost"


def excerpt(text):
    flat = " ".join(text.split())
    return flat if len(flat) <= EXCERPT_LENGTH else flat[:EXCERPT_LENGTH - 1] + "…"


def is_listed_review(review):
    return review["state"] != "PENDING" and (review["state"] != "COMMENTED" or review["body"].strip())


def waits_for_answer(thread, viewer):
    comments = thread["comments"]["nodes"]
    return not thread["isResolved"] and bool(comments) and author(comments[-1]) != viewer


def items_from_others(viewer, pr):
    items = []
    for thread in pr["reviewThreads"]["nodes"]:
        place = f"{thread['path']}:{thread['line'] or thread['originalLine']}"
        for comment in thread["comments"]["nodes"]:
            if author(comment) != viewer:
                key = f"c{comment['databaseId']}"
                items.append((key, f"review comment {key} by {author(comment)} on {place}: "
                                   f"{excerpt(comment['body'])} {comment['url']}"))
    for review in pr["reviews"]["nodes"]:
        if author(review) != viewer and is_listed_review(review):
            key = f"r{review['databaseId']}"
            items.append((key, f"review {key} {review['state']} by {author(review)}: "
                               f"{excerpt(review['body']) or '(no text)'} {review['url']}"))
    for comment in pr["comments"]["nodes"]:
        if author(comment) != viewer:
            key = f"i{comment['databaseId']}"
            items.append((key, f"conversation comment {key} by {author(comment)}: "
                               f"{excerpt(comment['body'])} {comment['url']}"))
    return items


def cmd_comments(args):
    owner, name, number = resolve_pr(args.pr)
    viewer, pr = read_pr(owner, name, number)

    def entry(node, prefix, **extra):
        return {"id": f"{prefix}{node['databaseId']}", "author": author(node), "mine": author(node) == viewer,
                **extra, "url": node["url"], "body": node["body"]}

    threads = [{"path": t["path"], "line": t["line"] or t["originalLine"], "outdated": t["isOutdated"],
                "resolved": t["isResolved"], "waits_for_answer": waits_for_answer(t, viewer),
                "comments": [entry(c, "c", created_at=c["createdAt"]) for c in t["comments"]["nodes"]]}
               for t in pr["reviewThreads"]["nodes"] if args.all or not t["isResolved"]]
    reviews = [entry(r, "r", state=r["state"], submitted_at=r["submittedAt"])
               for r in pr["reviews"]["nodes"] if is_listed_review(r)]
    conversation = [entry(c, "i", created_at=c["createdAt"]) for c in pr["comments"]["nodes"]]
    return {"result": "comments", "viewer": viewer,
            "pr": {"number": pr["number"], "url": pr["url"], "state": pr["state"],
                   "review_decision": pr["reviewDecision"]},
            "threads": threads, "reviews": reviews, "conversation": conversation}


def seen_file(owner, name, number):
    common = Path(git("rev-parse", "--git-common-dir")).resolve()
    return common / "push-pr" / f"seen-{owner}-{name}-{number}.json"


def load_seen(path):
    try:
        return set(json.loads(path.read_text()))
    except (FileNotFoundError, ValueError):
        return None


def save_seen(path, seen):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(sorted(seen)))


def cmd_watch(args):
    target = None
    failures = 0
    while True:
        try:
            if target is None:
                target = resolve_pr(args.pr)
                path = seen_file(*target)
                seen = load_seen(path)
            viewer, pr = read_pr(*target)
        except Stop as stop:
            if args.once or stop.code == REFUSED:
                raise
            failures += 1
            if failures == FAILURES_BEFORE_REPORT:
                say(f"PR #{target[2] if target else args.pr or '?'}: the watch cannot read the pull request: "
                    f"{stop.fields.get('stderr') or stop.fields.get('message') or stop.fields['result']}")
            time.sleep(args.interval)
            continue
        number = target[2]
        if failures >= FAILURES_BEFORE_REPORT:
            say(f"PR #{number}: the watch reads the pull request again")
        failures = 0
        items = items_from_others(viewer, pr)
        if seen is None:
            seen = set()
            waiting = sum(waits_for_answer(t, viewer) for t in pr["reviewThreads"]["nodes"])
            say(f"PR #{number}: the watch starts. Review decision: {pr['reviewDecision'] or 'none'}. "
                f"{waiting} unresolved review threads wait for an answer. "
                f"push-pr.py comments shows them")
        else:
            new = [line for key, line in items if key not in seen]
            if len(new) > MAX_LINES_PER_POLL:
                say(f"PR #{number}: {len(new)} new comments. push-pr.py comments shows them")
            else:
                for line in new:
                    say(f"PR #{number}: {line}")
        seen.update(key for key, _ in items)
        save_seen(path, seen)
        if pr["state"] != "OPEN":
            say(f"PR #{number} is {pr['state'].lower()}. The watch stops")
            return None
        if args.once:
            return None
        time.sleep(args.interval)


def thread_of(pr, comment_id):
    for thread in pr["reviewThreads"]["nodes"]:
        if any(c["databaseId"] == comment_id for c in thread["comments"]["nodes"]):
            return thread
    return None


def cmd_reply(args):
    match = re.fullmatch(r"([cri])(\d+)", args.id)
    if not match:
        raise Stop(ERROR, "bad-id", message="an id is c<n>, r<n> or i<n>, as watch and comments print it")
    kind, comment_id = match.group(1), int(match.group(2))
    if args.resolve and kind != "c":
        raise Stop(REFUSED, "cannot-resolve", message="only a review comment has a thread to resolve")
    body = Path(args.body_file).read_text().strip()
    if not body:
        raise Stop(REFUSED, "empty-body", message=f"{args.body_file} is empty")
    owner, name, number = resolve_pr(args.pr)
    repo = f"repos/{owner}/{name}"

    if kind == "c":
        _, pr = read_pr(owner, name, number)
        thread = thread_of(pr, comment_id)
        first = thread["comments"]["nodes"][0]["databaseId"] if thread else comment_id
        posted = gh_json("api", "--method", "POST", f"{repo}/pulls/{number}/comments/{first}/replies",
                         "--input", "-", stdin=json.dumps({"body": body}))
        replied = {"result": "replied", "id": f"c{posted['id']}", "url": posted["html_url"]}
        if args.resolve:
            if thread is None:
                replied.update(resolved=False, message="the watch found no thread for this comment")
            else:
                gh_json("api", "graphql", "-f", f"query={RESOLVE_THREAD}", "-f", f"id={thread['id']}")
                replied["resolved"] = True
        return replied

    source = f"{repo}/issues/comments/{comment_id}" if kind == "i" else f"{repo}/pulls/{number}/reviews/{comment_id}"
    first_line = next((line for line in (gh_json("api", source)["body"] or "").splitlines() if line.strip()), "")
    text = (f"> {excerpt(first_line)}\n\n" if first_line else "") + body
    posted = gh_json("api", "--method", "POST", f"{repo}/issues/{number}/comments",
                     "--input", "-", stdin=json.dumps({"body": text}))
    return {"result": "replied", "id": f"i{posted['id']}", "url": posted["html_url"]}


def main():
    parser = Parser(prog="push-pr.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("status", "sync", "push"):
        command = commands.add_parser(name)
        command.add_argument("--base")
        if name != "status":
            command.add_argument("--force", action="store_true")
    command = commands.add_parser("comments")
    command.add_argument("--pr", type=int)
    command.add_argument("--all", action="store_true")
    command = commands.add_parser("watch")
    command.add_argument("--pr", type=int)
    command.add_argument("--interval", type=int, default=60)
    command.add_argument("--once", action="store_true")
    command = commands.add_parser("reply")
    command.add_argument("id")
    command.add_argument("--body-file", required=True)
    command.add_argument("--pr", type=int)
    command.add_argument("--resolve", action="store_true")
    args = parser.parse_args()

    handlers = {"status": cmd_status, "sync": cmd_sync, "push": cmd_push,
                "comments": cmd_comments, "watch": cmd_watch, "reply": cmd_reply}
    try:
        result = handlers[args.command](args)
    except Stop as stop:
        print(json.dumps(stop.fields, indent=2))
        return stop.code
    if result is not None:
        print(json.dumps(result, indent=2))
    return DONE


if __name__ == "__main__":
    sys.exit(main())
