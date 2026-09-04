"""The mechanical half of what the run-verifier agent does.

Three checks that need no judgment: work a task left uncommitted, a green that cannot be
trusted, and a task whose work did not stay in one commit. Anything a check cannot settle
is reported as not checked rather than guessed at, and ground it could not run for want of
a flag is a hint, not a gap.
"""

import json
import re
from pathlib import Path

from clerk_lib import gitout
from clerk_repo import (breakdown_for, default_branch, head_sha, receipt_state, run_records_dir, state_dir,
                        tasks_home)

VACUITY = re.compile(r"no files changed|no tests to run|no test files|0 passed|0 tests|skip running tests|no tests ran", re.I)
_NOT_VACUOUS = re.compile(r"no test files|^ok\s.*no tests to run", re.I)
_OK_LINE = re.compile(r"^ok\s")
_NO_TESTS = re.compile(r"no test files|no tests to run", re.I)


def _lines(text):
    return [ln for ln in (text or "").split("\n") if ln]


def vacuity(tail):
    """The line that says nothing ran, or None. `go test ./...` prints `[no test files]` for
    every package without tests beside the `ok` lines of those with them, and `ok <pkg> [no
    tests to run]` means every test sat behind a build tag; either only counts when no
    package ran."""
    vac = next((ln for ln in tail.splitlines() if VACUITY.search(ln) and not _NOT_VACUOUS.search(ln)), None)
    if vac:
        return vac
    ran = any(_OK_LINE.search(ln) and "no tests to run" not in ln for ln in tail.splitlines())
    if not ran:
        return next((ln for ln in tail.splitlines() if _NO_TESTS.search(ln)), None)
    return None


def scattered_task(records, base, cwd=None):
    """Arithmetic over the file lists `clerk finish` recorded: a task whose exclusive files
    appear in more than one commit was split or swept into another task's commit."""
    findings, gaps = [], []
    recs = []
    for f in sorted(Path(records).glob("*.json")):
        try:
            recs.append(json.loads(f.read_text()))
        except (OSError, json.JSONDecodeError):
            continue
    counts = {}
    for r in recs:
        for p in r.get("files") or []:
            counts[p] = counts.get(p, 0) + 1
    shared = {p for p, c in counts.items() if c > 1}
    commits = _lines(gitout("log", "--format=%H", f"{base}..HEAD", cwd=cwd))
    touched = {c: set(_lines(gitout("show", "--name-only", "--format=", c, cwd=cwd))) for c in commits}
    for r in recs:
        n = r.get("n")
        exclusive = [p for p in (r.get("files") or []) if p not in shared]
        if not exclusive:
            gaps.append(f"scattered-task — every file task {n} recorded was also recorded by another task, so whether its work stayed in one commit cannot be told from the file lists")
            continue
        count = sum(1 for c in commits if touched[c] & set(exclusive))
        if count > 1:
            findings.append({"check": "scattered-task", "severity": "warn",
                             "detail": f"task {n}'s files appear in {count} commits — its work was split or swept into another task's commit"})
    return findings, gaps


def verify(tasks_override=None, cwd=None):
    th = tasks_home(cwd)
    tasks, _ = breakdown_for(tasks_override, cwd)
    state = state_dir(cwd)
    default = default_branch(cwd)
    head = head_sha(cwd)
    base = gitout("merge-base", "HEAD", default, cwd=cwd) if default else None
    findings, gaps, hints = [], [], []

    # 1. uncommitted-work — a task that did not close leaves its work staged, so a plain
    #    `git diff` looks empty and the run reads as finished.
    staged = _lines(gitout("diff", "--cached", "--name-only", cwd=cwd))
    dirty = [ln for ln in _lines(gitout("status", "--porcelain", cwd=cwd)) if not ln.startswith("??")][:10]
    if staged:
        findings.append({"check": "uncommitted-work", "severity": "block",
                         "detail": f"staged but uncommitted: {' '.join(staged)}— an unfinished task, not a stray edit; inspect 'git diff --staged'"})
    elif dirty:
        findings.append({"check": "uncommitted-work", "severity": "warn",
                         "detail": f"tracked files modified but not staged: {';'.join(dirty)}"})

    # 2. unproven-suite — judged from the recorded receipt, because the receipt is what
    #    land trusts and it is what must not be hollow.
    rs = receipt_state(state, head, cwd)
    if not rs["fresh"]:
        findings.append({"check": "unproven-suite", "severity": "block", "detail": rs["why"]})
    else:
        try:
            tail = json.loads((Path(state) / "receipt.json").read_text()).get("output_tail") or ""
        except (OSError, json.JSONDecodeError):
            tail = ""
        vac = vacuity(tail) if tail else None
        if vac:
            findings.append({"check": "unproven-suite", "severity": "block",
                             "detail": f"the receipt's output shows nothing ran: {vac}"})
        elif not tail:
            hints.append("unproven-suite — the receipt carries no output tail, so it could not be checked for vacuity; record it with --output-file")

    # 3. scattered-task
    records = Path(run_records_dir(state, tasks)) if tasks else None
    if records and records.is_dir() and base:
        f, g = scattered_task(records, base, cwd)
        findings += f
        gaps += g
    elif not base:
        hints.append("scattered-task — no merge-base with a default branch, so the run's own commits could not be scoped")
    elif not tasks:
        hints.append(f"scattered-task — no single breakdown under {th}/tasks, so this run's task records could not be identified; name it with --tasks-file")
    else:
        hints.append(f"scattered-task — no per-task file records for {Path(tasks).name.removesuffix('.md')}; run tasks through 'clerk finish' for this check")

    findings.sort(key=lambda f: 0 if f["severity"] == "block" else 1)
    clean = not any(f["severity"] == "block" for f in findings)
    return {"clean": clean, "findings": findings, "not_checked": gaps, "hints": hints}
