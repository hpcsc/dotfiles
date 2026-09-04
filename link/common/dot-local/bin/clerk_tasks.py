"""The breakdown's task record, and the two commands that read and write it.

`status` is progress for a human plus the next unblocked task for the step table; `finish`
marks one task done and stages its files with the task record, so the record and the change
land in one commit. Completion lives in the task record and nowhere else: mirrored into a
markdown checkbox as well, two files carried the one fact a resumed run depends on and
could disagree.
"""

import json
import re
import subprocess
from pathlib import Path

from clerk_lib import die, emit, git, gitout, plugin_bin
from clerk_repo import (breakdown_for, is_ignored, now, run_records_dir, task_record_for, state_dir,
                        tasks_home, tasks_hint, work_tree)

_TASK_HEADING = re.compile(r"^###\s+Task\s+(\d+):")
_CHECKBOX = re.compile(r"^\s*- \[([ xX])\]")


def load_task_record(side):
    try:
        return json.loads(Path(side).read_text())
    except (OSError, json.JSONDecodeError) as e:
        die(f"could not read {side}: {e}")


def criteria_counts(tasks_file):
    """Acceptance criteria per task section, counted from the breakdown. Not run progress:
    the record of which criteria were walked, ticked by hand. Only checkboxes inside a
    `### Task N:` section count, so a legacy progress list above the first is excluded."""
    counts = {}
    n = None
    for line in Path(tasks_file).read_text(errors="replace").splitlines():
        m = _TASK_HEADING.match(line)
        if m:
            n = int(m.group(1))
            counts.setdefault(n, {"total": 0, "ticked": 0})
            continue
        if n is None:
            continue
        m = _CHECKBOX.match(line)
        if m:
            counts[n]["total"] += 1
            if m.group(1) in "xX":
                counts[n]["ticked"] += 1
    return counts


def next_task(tasks):
    """The first task whose dependencies are all done, with the queue's shape."""
    done = {t["n"] for t in tasks if t.get("done") is True}
    open_ = [t for t in tasks if t["n"] not in done]
    ready = [t for t in open_ if all(d in done for d in (t.get("depends_on") or []))]
    first = min(ready, key=lambda t: t["n"]) if ready else None
    return {"done": not open_, "total": len(tasks), "remaining": len(open_),
            "blocked": len(open_) - len(ready), "task": first}


def status_of(tasks_file, side, archived, label=None):
    """Progress, for a human, plus the per-task assessment rolled up as `gears` — reported
    whatever the flag says, since the flag decides how a run drives, never whether the
    assessment is available to read."""
    tasks = load_task_record(side).get("tasks") or []
    crit = criteria_counts(tasks_file)
    done_n = {t["n"] for t in tasks if t.get("done") is True}
    total_c = sum(c["total"] for c in crit.values())
    ticked_c = sum(c["ticked"] for c in crit.values())
    progress = []
    unwalked = []
    for t in tasks:
        k = crit.get(t["n"], {"total": 0, "ticked": 0})
        if t.get("done") is True and k["total"] > k["ticked"]:
            unwalked.append(t["n"])
        progress.append({"n": t["n"], "title": t.get("title"), "done": t.get("done") is True,
                         "certainty": t.get("certainty"), "blast_radius": t.get("blast_radius"),
                         "criteria": {"total": k["total"], "ticked": k["ticked"], "unticked": k["total"] - k["ticked"]},
                         "blocked_by": [d for d in (t.get("depends_on") or []) if d not in done_n]})
    return {"tasks_file": label or tasks_file, "task_record": side, "archived": archived,
            "total": len(tasks), "done": len(done_n), "remaining": len(tasks) - len(done_n),
            "criteria": {"total": total_c, "ticked": ticked_c, "unticked": total_c - ticked_c},
            "done_with_unticked_criteria": unwalked,
            "gears": {"low_certainty": [t["n"] for t in tasks if t.get("certainty") == "low"],
                      "high_blast_radius": [t["n"] for t in tasks if t.get("blast_radius") == "high"],
                      "unassessed": [t["n"] for t in tasks if "certainty" not in t]},
            "progress": progress, "next": next_task(tasks)}


def cmd_status(o):
    from clerk_repo import breakdown_paths
    th = tasks_home()
    if o["--all"]:
        wt = work_tree() or ""
        out = []
        for f in breakdown_paths(th, include_archived=True):
            side = task_record_for(f)
            if not side:
                continue
            arch = "/completed/" in f
            # Relative to the work tree: the identifier every consumer already has.
            label = f[len(wt) + 1:] if f.startswith(wt + "/") else f
            out.append(status_of(f, side, arch, label))
        return {"breakdowns": out}
    tasks, rc = breakdown_for(o["--tasks-file"])
    if rc != 0:
        die(tasks_hint(th, "status"))
    side = task_record_for(tasks)
    if not side:
        die(f"no task record beside {tasks} — a breakdown is bound with its tasks/<story>.json; decompose again, or write one by hand from the task sections")
    return status_of(tasks, side, False)


def cmd_finish(n, files, tasks_override=None):
    th = tasks_home()
    tasks, rc = breakdown_for(tasks_override)
    if rc != 0:
        die(tasks_hint(th, "finish"))
    if not Path(tasks).is_file():
        die(f"task file not found: {tasks}")
    side = task_record_for(tasks)
    if not side:
        die(f"no task record beside {tasks} — a breakdown is bound with its tasks/<story>.json; decompose again, or write one by hand from the task sections")
    data = load_task_record(side)
    entry = next((t for t in data.get("tasks") or [] if t.get("n") == n), None)
    if entry is None:
        die(f"no Task {n} in {Path(side).name}")
    if entry.get("done") is True:
        die(f"Task {n} is already done — a task is never redone")
    for f in files:
        if not Path(f).exists():
            die(f"'{f}' does not exist — stage only what this task actually changed")

    # One task in flight. A finish whose commit never happened leaves its paths in the
    # index, and the next finish would sweep them into its own commit. So a path another
    # task's record claims, still staged and not named here, refuses this one.
    state = state_dir()
    records = Path(run_records_dir(state, tasks))
    owners = {}
    for rec in sorted(records.glob("*.json")) if records.is_dir() else []:
        try:
            r = json.loads(rec.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        for p in r.get("files") or []:
            owners.setdefault(p, r.get("n"))
    held = [f" {p} (task {owners[p]})" for p in (gitout("diff", "--cached", "--name-only") or "").splitlines()
            if p and p not in files and p in owners]
    if held:
        emit({"task": n, "done": False, "reason": "another-task-still-staged",
              "detail": "the index still holds files clerk finish staged for another task:" + "".join(held)
                        + " — commit that task (or unstage them) before finishing this one",
              "named": list(files)}, 3)

    # Explicit paths only: `git add -A` sweeps whatever was left loose into this commit.
    if git("add", "--", *files).returncode != 0:
        die("staging failed — report this and stop; do not stage by hand")

    # The staged set is linted BEFORE the task is marked done, and a finding refuses the
    # whole step with the paths left staged. A lint that cannot run is reported and does
    # not block: hiding a finished task behind a tooling error would be the worse lie.
    lint_state = "clean"
    lint = plugin_bin("lint")
    if lint:
        r = subprocess.run([lint, "--staged", "--json"], capture_output=True, text=True)
        try:
            findings = json.loads(r.stdout) if r.stdout.strip() else []
        except json.JSONDecodeError:
            findings = []
        if r.returncode == 1:
            emit({"task": n, "done": False, "lint_findings": findings, "staged": list(files),
                  "next_step": "fix each finding — a defect, not an opinion — then run clerk finish again; the paths stay staged"}, 1)
        elif r.returncode != 0:
            lint_state = f"could not run (exit {r.returncode})"
    else:
        lint_state = "not installed"

    for t in data["tasks"]:
        if t.get("n") == n:
            t["done"] = True
    try:
        Path(side).write_text(json.dumps(data, indent=2) + "\n")
    except OSError:
        die(f"could not rewrite {side} — report this and stop; do not mark it done by hand")

    # Tracked tasks/: the modified breakdown rides with the commit too, or its ticks are
    # stranded outside it and the dirty tree blocks the next step. Excluded tasks/: neither
    # file is ever committed, so rewriting the task record is the whole of the job.
    staged_tasks, tracked = False, True
    if is_ignored(str(Path(side).parent), Path(side).name):
        tracked = False
    else:
        if git("diff", "--quiet", "--", tasks).returncode != 0:
            if git("add", "--", tasks).returncode != 0:
                die("could not stage the modified breakdown")
            staged_tasks = True
        if git("add", "--", side).returncode != 0:
            die("could not stage the task record — report this and stop. Marking the task done and staging it with its code is precisely what this command exists to do in one step")

    records.mkdir(parents=True, exist_ok=True)
    (records / f"{n}.json").write_text(json.dumps({"n": n, "at": now(), "files": list(files)}) + "\n")
    return {"task": n, "done": True, "task_record": side, "breakdown_staged": staged_tasks,
            "breakdown_tracked": tracked, "lint": lint_state, "staged": list(files),
            "next_step": "invoke the commit skill — the message is judgment, not mechanics"}


_EXIT_MARKER = re.compile(r"(?mi)^\s*clerk_exit=(\d+)\s*$")


def _recorded_exit(tail):
    """The exit code the run wrote into its own output, or None. The last marker wins: a
    command that tees several stages appends one per stage and the suite's is the last."""
    found = _EXIT_MARKER.findall(tail)
    return int(found[-1]) if found else None


def cmd_receipt(command, passed, output_file):
    """Record a suite run against the code tree it describes.

    The output file is the evidence and is required. Without it `passed` is an assertion
    with nothing behind it, and the vacuity check downstream degrades to a hint — which is
    the one shape a receipt exists to make impossible."""
    sha = gitout("rev-parse", "HEAD")
    if not sha:
        die("cannot resolve HEAD")
    state = state_dir()
    if not state:
        die("not a git repository")
    Path(state).mkdir(parents=True, exist_ok=True)
    if not output_file:
        die("--output-file is required: capture the suite's output and pass the file. A "
            "receipt with no output cannot be checked, and an unfalsifiable green is what "
            "this command exists to refuse")
    p = Path(output_file)
    if not p.is_file():
        die(f"no output file at {output_file} — pass the file the suite's output was captured to", 1)
    data = p.read_bytes()
    if not data.strip():
        die(f"{output_file} is empty — that is not evidence the suite ran", 1)
    tail = data[-4000:].decode("utf-8", errors="replace")

    # The suite must have run against the tree being described. An output file older than
    # HEAD was written before this commit existed, so whatever it proves, it is not this.
    head_time = gitout("show", "-s", "--format=%ct", "HEAD")
    mtime = int(p.stat().st_mtime)
    if head_time and mtime < int(head_time):
        die(f"{output_file} was last written {int(head_time) - mtime}s before HEAD ({sha[:8]}) was "
            f"committed, so it describes an earlier tree. Re-run the suite and capture it again", 1)

    # A run that reported its own exit code settles pass/fail; a claim against it is wrong
    # rather than arguable.
    rc = _recorded_exit(tail)
    if rc is not None:
        if passed and rc != 0:
            die(f"the output records clerk_exit={rc} but --passed was given. Do not record a green "
                f"the run itself did not report", 1)
        if not passed and rc == 0:
            die("the output records clerk_exit=0 but --failed was given", 1)

    rec = {"sha": sha, "command": command, "passed": passed, "at": now(), "output_tail": tail,
           "output_file": str(p), "output_bytes": len(data), "exit_code": rc}
    try:
        (Path(state) / "receipt.json").write_text(json.dumps(rec) + "\n")
    except OSError:
        die(f"cannot write {state}/receipt.json")
    return rec
