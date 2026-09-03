"""Landing, and the branch or worktree a run builds on.

`isolate` gives the run somewhere of its own: a worktree beside the git dir, or a branch
in the main checkout when `in_place` is on. `land` archives the breakdown on the feature
branch and, only when asked, puts the branch on the default one. Integration is opt-in
because it is the one irreversible step and every input to it is something the caller
assessed about its own work: a branch left standing costs one fast-forward later, a bad
fast-forward costs a history rewrite.
"""

import json
import os
import shutil
import subprocess
from pathlib import Path

from clerk_lib import die, emit, git, gitout, plugin_bin
from clerk_repo import (breakdown_for, common_dir, current_branch, default_branch, env_get, head_sha,
                        is_ignored, ledger_dir, ledger_put, now, receipt_state, repo_root, resolve_flag,
                        run_records_dir, sidecar_for, state_dir, tasks_home, tasks_hint, work_tree)


# --------------------------------------------------------------------------------
# isolate
# --------------------------------------------------------------------------------

def worktree_dir(root):
    """CLERK_WORKTREE_DIR, then `worktree_dir` in tasks/.environment, then the harness's
    own directory: Claude Code's EnterWorktree waves through a path under
    `.claude/worktrees/` and prompts for every other one, and no other harness has a
    reason to carry Claude's directory in its repos."""
    if os.environ.get("CLERK_WORKTREE_DIR"):
        return os.environ["CLERK_WORKTREE_DIR"].rstrip("/")
    v = env_get(Path(root) / "tasks" / ".environment", "worktree_dir")
    if v:
        return v.rstrip("/")
    return ".claude/worktrees" if os.environ.get("CLAUDECODE") else ".worktrees"


def _usable_name(name):
    if not name:
        die("name the feature, in kebab-case")
    if git("check-ref-format", "--branch", name).returncode != 0:
        die(f"'{name}' is not a usable branch name")


def make_worktree(name, base=None):
    _usable_name(name)
    common = common_dir()
    if not common:
        die("not a git repository")
    parent = str(Path(common).parent)
    d = worktree_dir(parent)
    path = f"{parent}/{d}/{name}"

    # Already has a home: adopt it. The main checkout is in the list too, and it is the one
    # match that must not be adopted — that is --in-place arrived at by accident.
    existing = None
    p = None
    for line in (gitout("worktree", "list", "--porcelain") or "").splitlines():
        if line.startswith("worktree "):
            p = line[len("worktree "):]
        elif line == f"branch refs/heads/{name}":
            existing = p
            break
    if existing == parent:
        die(f"'{name}' is checked out in the main tree at {parent} — switch it away, or build there with --in-place")
    if existing:
        return {"mode": "worktree", "path": existing, "branch": name, "created": False, "adopted": True,
                "excluded": None, "note": "this feature already has a worktree; enter it rather than creating a second"}

    excluded = False
    exclude = Path(common) / "info" / "exclude"
    lines = exclude.read_text().splitlines() if exclude.is_file() else []
    if f"{d}/" not in lines:
        exclude.parent.mkdir(parents=True, exist_ok=True)
        with exclude.open("a") as fh:
            fh.write(f"{d}/\n")
        excluded = True

    if Path(path).exists():
        die(f"{path} exists but is not a worktree of this repo")
    branch_exists = git("show-ref", "--verify", "--quiet", f"refs/heads/{name}").returncode == 0
    if branch_exists:
        # A run whose tree was removed and whose commits are still on the branch: a resume.
        if git("worktree", "add", path, name).returncode != 0:
            die(f"git worktree add failed for existing branch '{name}'")
    else:
        if git("worktree", "add", "-b", name, path, *([base] if base else [])).returncode != 0:
            die(f"git worktree add failed (is '{name}' checked out elsewhere?)")
    return {"mode": "worktree", "path": path, "branch": name, "dir": d, "created": not branch_exists,
            "adopted": branch_exists, "excluded": excluded, "base": base or None,
            "note": ("the branch already existed; its commits are here" if branch_exists
                     else "branched from HEAD" + (f" via {base}" if base else ""))}


def make_branch(name):
    """The in-place counterpart: a feature branch when standing on the default one, a
    switch when it already exists, a no-op when already off the default branch. The flag
    turns off the worktree, not the branch."""
    _usable_name(name)
    if not gitout("rev-parse", "--git-dir"):
        die("not a git repository")
    default = default_branch()
    cur = current_branch()
    if cur != default:
        return {"mode": "in-place", "branch": cur, "default_branch": default, "created": False, "switched": False,
                "note": "already off the default branch; the work has somewhere of its own to land"}
    if git("show-ref", "--verify", "--quiet", f"refs/heads/{name}").returncode == 0:
        if git("switch", "-q", name).returncode != 0:
            die(f"could not switch to existing branch '{name}'")
        return {"mode": "in-place", "branch": name, "default_branch": default, "created": False, "switched": True,
                "note": "the branch already existed; its commits are here"}
    if git("switch", "-qc", name).returncode != 0:
        die(f"could not create '{name}'")
    return {"mode": "in-place", "branch": name, "default_branch": default, "created": True, "switched": True,
            "note": "branched from the default branch; the work lands here rather than on it"}


def isolate(name, in_place=None, base=None):
    """A worktree, or a branch in the main checkout when `in_place` is on — from the
    flag typed here, else from the run's request and the repo's settings."""
    if in_place is None:
        root = repo_root()
        if not root:
            die("not a git repository")
        from clerk_repo import request_from_ledger
        in_place, _ = resolve_flag(root, "in_place", request_from_ledger() or "")
    return make_branch(name) if in_place else make_worktree(name, base)


# --------------------------------------------------------------------------------
# The gate: what the step table does not look at
# --------------------------------------------------------------------------------

def gate(audit_accepted=False, tasks_override=None):
    wt = work_tree()
    state = state_dir()
    head = head_sha()
    checks = []

    tasks, _ = breakdown_for(tasks_override)
    archived = Path(state) / "archived.json"
    if not tasks and archived.is_file():
        # Archiving is gated on every task closing, so the archive record IS that evidence,
        # and a second `land` after a rebase does not refuse a run that already satisfied it.
        ok, detail = True, f"breakdown already archived at {json.loads(archived.read_text()).get('path')}"
    elif not tasks:
        ok, detail = False, f"no task file found under {wt}/tasks (pass --tasks-file to name it)"
    elif not Path(tasks).is_file():
        ok, detail = False, f"task file not found: {tasks}"
    else:
        side = sidecar_for(tasks)
        if side:
            open_ = [t for t in (json.loads(Path(side).read_text()).get("tasks") or []) if t.get("done") is not True]
            if not open_:
                ok, detail = True, f"every task marked done in {Path(side).name}"
            else:
                ok, detail = False, f"{len(open_)} task(s) still open in {Path(side).name}"
        else:
            ok, detail = False, f"no sidecar beside {tasks} — run 'clerk sidecar' to recover one"
    checks.append({"name": "tasks-complete", "ok": ok, "detail": detail})

    dirty = [ln for ln in (gitout("status", "--porcelain") or "").split("\n") if ln]
    checks.append({"name": "tree-clean", "ok": not dirty,
                   "detail": "working tree clean" if not dirty else f"uncommitted changes: {';'.join(dirty[:5])}"})

    rs = receipt_state(state, head)
    if rs["fresh"]:
        ok, detail = True, f"green at {(head or '')[:8]}: {rs['command']}"
    else:
        ok, detail = False, rs["why"] or ""
        if not rs["recorded"]:
            detail += " — run the suite and 'clerk receipt --command ... --passed'"
    checks.append({"name": "receipt-fresh", "ok": ok, "detail": detail})

    # The judgment one — asserted, never inferred. In a run driven by `clerk step` the
    # assertion is `clerk audit accept`, and `land` reads it through step's answer.
    checks.append({"name": "audit-accepted", "ok": audit_accepted,
                   "detail": ("caller asserted audit findings are fixed or explicitly accepted" if audit_accepted
                              else "pass --audit-accepted once the audit's findings are fixed or the user has accepted them")})
    return {"ok": all(c["ok"] for c in checks), "checks": checks}


# --------------------------------------------------------------------------------
# land
# --------------------------------------------------------------------------------

def step_says(cwd=None):
    """What `clerk step` answers here, or None when no run ledger or no step command."""
    if not ledger_dir(cwd):
        return None
    step = plugin_bin("step")
    if not step:
        return None
    r = subprocess.run([step], cwd=cwd, capture_output=True, text=True)
    try:
        return json.loads(r.stdout) if r.stdout.strip() else {}
    except json.JSONDecodeError:
        return {}


def land(integrate=None, audit=False, name=None, tasks_override=None, check=False):
    # In a run driven by `clerk step`, whether the branch may land is step's answer: the
    # land row is reached only past the audit's acceptance, the story re-read and the
    # verify pass at this code tree, so a `land` typed directly cannot walk past any of
    # them. The gate then keeps what the table does not look at — a dirty tree, a stale
    # receipt — and the acceptance it would ask to be asserted is step's to vouch for.
    row = step_says()
    if row is not None:
        step_id = row.get("step") or "unknown"
        if step_id != "land":
            emit({"landed": False, "step": step_id, "blocked": bool(row.get("blocked")),
                  "reason": f"the run is at the {step_id} step, not land: "
                            f"{row.get('reason') or row.get('why_not_done') or 'clerk step could not answer'}"}, 1)
        audit = True

    g = gate(audit, tasks_override)
    if check:
        emit(g, 0 if g["ok"] else 1)
    if not g["ok"]:
        emit({"landed": False, "reason": "gate did not open", "gate": g}, 1)

    root, wt, th, state = repo_root(), work_tree(), tasks_home(), state_dir()
    default, branch = default_branch(), current_branch()

    # Nothing typed means the repo decides, after the gate: a config file cannot change
    # whether the branch is fit to land, only whether a fit branch goes on to be merged.
    integrate_src = "request"
    if integrate is None:
        integrate, integrate_src = resolve_flag(root, "integrate")

    tasks, rc = breakdown_for(tasks_override)
    if rc == 3:
        die(tasks_hint(th, "land"))
    if rc != 0:
        tasks = None

    # Archive first, on the feature branch, so the archive commit rides with the work it
    # belongs to. It also has to come before any rebase: `git mv` leaves a dirty tree.
    archived = None
    if tasks and Path(tasks).is_file():
        name = name or Path(tasks).name.removesuffix(".md")
        archive_dir = Path(th) / "tasks" / "completed"
        archive_dir.mkdir(parents=True, exist_ok=True)
        side = Path(tasks).with_suffix(".json")
        if is_ignored(str(Path(tasks).parent), Path(tasks).name):
            # Machine-local: a plain move and no archive commit.
            try:
                shutil.move(tasks, archive_dir / Path(tasks).name)
                if side.is_file():
                    shutil.move(str(side), archive_dir / side.name)
            except OSError:
                die(f"could not archive {tasks}")
            archived = str(archive_dir / Path(tasks).name)
        else:
            if git("mv", tasks, str(archive_dir / Path(tasks).name)).returncode != 0:
                die(f"could not archive {tasks}")
            if side.is_file():
                git("mv", str(side), str(archive_dir / side.name))
            if git("commit", "-qm", f"Archive completed task: {name}").returncode != 0:
                die("archive commit failed")
            archived = f"tasks/completed/{Path(tasks).name}"
        Path(state).mkdir(parents=True, exist_ok=True)
        (Path(state) / "archived.json").write_text(json.dumps({"path": archived, "name": name}) + "\n")
        # The records stop meaning anything once the breakdown has left tasks/.
        shutil.rmtree(run_records_dir(state, tasks), ignore_errors=True)

    ldir = ledger_dir()
    ledger_put(ldir, "land.json", {"archived": archived, "integrate": bool(integrate),
                                   "integrate_source": integrate_src, "landed": False, "at": now()})

    if not integrate:
        emit({"landed": False, "archived": archived, "branch": branch, "default_branch": default,
              "build_tree": wt, "integrate": False, "integrate_source": integrate_src,
              "note": ("integration is opt-in and was not requested" if integrate_src in ("request", "default")
                       else f"integration is off in {integrate_src}"),
              "to_land": f"git -C <main checkout> merge --ff-only {branch} (rebase onto {default} first if the base moved)"})

    if not default:
        die("cannot resolve a default branch")
    if branch == default:
        die(f"already on {default} — nothing to integrate")

    before = head_sha()
    if git("rebase", default).returncode != 0:
        git("rebase", "--abort")
        emit({"landed": False, "reason": f"rebase onto {default} conflicted; branch left exactly as it was",
              "note": "resolve it yourself or hand it to the user — do not resolve someone else's merge"}, 1)
    after = head_sha()
    if before != after:
        # Green-before-rebase is not green-after.
        emit({"landed": False, "rebased": True, "reason": "the rebase replayed commits onto a moved base",
              "was": before, "now": after,
              "next_step": "re-run the full suite, record it with 'clerk receipt', then run 'clerk land --integrate' again"}, 3)

    if root != wt:
        # The branch is checked out here, so it cannot be merged and deleted from inside.
        # Remove the worktree first: `git branch -d` refuses while one has the branch.
        emit({"landed": False, "rebased": False,
              "reason": "this is a worktree; the branch is checked out here so it cannot be merged and deleted from inside it",
              "next_step": "leave the worktree with the branch KEPT (removing it here would delete the branch about to be merged), then run the command below from anywhere",
              "command": f"git -C {root} merge --ff-only {branch} && git -C {root} worktree remove {wt} && git -C {root} branch -d {branch}",
              "worktree": wt}, 3)

    if git("switch", "-q", default).returncode != 0:
        die(f"could not switch to {default}")
    if git("merge", "--ff-only", branch).returncode != 0:
        git("switch", "-q", branch)
        emit({"landed": False, "reason": "merge --ff-only refused: the base moved again",
              "next_step": "rebase and re-run the suite, then retry"}, 1)
    deleted, holder = True, ""
    if git("branch", "-d", branch).returncode != 0:
        deleted = False
        p = None
        for line in (gitout("worktree", "list", "--porcelain") or "").splitlines():
            if line.startswith("worktree "):
                p = line[len("worktree "):]
            elif line == f"branch refs/heads/{branch}":
                holder = p
                break
    ledger_put(ldir, "land.json", {"archived": archived, "integrate": True, "integrate_source": integrate_src,
                                   "landed": True, "deleted_branch": deleted, "at": now()})
    if deleted:
        left = None
    elif holder:
        left = f"{branch} still exists: the worktree at {holder} has it checked out. Remove that worktree, then: git branch -d {branch}"
    else:
        left = f"{branch} still exists: git branch -d refused it. Find out why before deleting it by hand."
    return {"landed": True, "integrate_source": integrate_src, "archived": archived, "base_branch": default,
            "branch": branch, "deleted_branch": branch if deleted else None, "branch_left": left,
            "pushed": False, "log": (gitout("log", "--oneline", "-5") or "").split("\n")}
