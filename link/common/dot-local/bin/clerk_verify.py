"""The mechanical half of what the run-verifier agent does.

Three of its four checks need no judgment, and one a script does more correctly than the
agent: the agent hunts dead code with a word search, which the guidelines forbid for
symbol questions because text matches prefixes, comments and strings. Text search IS
sound in one direction though — no textual match anywhere means no reference — and only
that direction is used here. Anything it cannot settle is reported as not checked rather
than guessed at, and ground it could not run for want of a flag is a hint, not a gap.
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

# A method that satisfies a standard-library interface is called by the runtime or by a
# package that never spells its name, so zero textual matches proves nothing about it.
INTERFACE_METHODS = {"MarshalJSON", "UnmarshalJSON", "MarshalText", "UnmarshalText", "MarshalYAML",
                     "UnmarshalYAML", "MarshalBinary", "UnmarshalBinary", "String", "Error", "GoString",
                     "Format", "Unwrap", "Is", "As", "Scan", "Value", "Close", "Read", "Write", "ReadFrom",
                     "WriteTo", "Seek", "ServeHTTP", "Len", "Less", "Swap"}
# A fixture package exists to be consumed by _test.go files and nothing else, so asking it
# to prove a non-test caller asks the one thing it never can.
FIXTURE_DIRS = {"test", "tests", "testutil", "testutils", "testhelper", "testhelpers", "testfixtures", "fixtures"}
_DECL = [(re.compile(r"^\+func ([A-Z][A-Za-z0-9_]*)\("), "func"),
         (re.compile(r"^\+func \([^)]*\) ([A-Z][A-Za-z0-9_]*)\("), "func"),
         (re.compile(r"^\+type ([A-Z][A-Za-z0-9_]*) "), "type")]


def _lines(text):
    return [ln for ln in (text or "").split("\n") if ln]


def _grep_files(pattern, *paths, word=False, cwd=None):
    args = ["grep", "-l"]
    args.append("-w" if word else "-E")
    args += ["--", pattern, "HEAD", "--", *paths]
    return [ln.split(":", 1)[1] if ":" in ln else ln for ln in _lines(gitout(*args, cwd=cwd))]


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


def dead_code(base, all_closed, cwd=None):
    """(findings, gaps) for new exported Go symbols with no reference outside their own
    file and the tests, and the languages the check does not extract."""
    findings, gaps = [], []
    gofiles = _lines(gitout("diff", "--name-only", f"{base}..HEAD", "--", "*.go", ":!*_test.go", cwd=cwd))
    if gofiles:
        decls = set()
        for ln in (gitout("diff", f"{base}..HEAD", "--", "*.go", ":!*_test.go", cwd=cwd) or "").split("\n"):
            for rx, kind in _DECL:
                m = rx.match(ln)
                if m:
                    decls.add(f"{kind}:{m.group(1)}")
        for decl in sorted(decls):
            kind, sym = decl.split(":", 1)
            if sym in INTERFACE_METHODS:
                continue
            # The declaration, not the first file that mentions it: tree order names a
            # caller far more often than the definition.
            defs = _grep_files(rf"^(func (\([^)]*\) )?{sym}\(|type {sym}[ \t])", "*.go", cwd=cwd)
            deffile = defs[0] if defs else (_grep_files(sym, "*.go", word=True, cwd=cwd) or [""])[0]
            if Path(deffile).parent.name in FIXTURE_DIRS:
                hits = len(_grep_files(sym, "*.go", word=True, cwd=cwd))
            else:
                hits = len(_grep_files(sym, "*.go", ":!*_test.go", word=True, cwd=cwd))
            if hits > 1:
                continue
            foreign = _grep_files(sym, ":!*.go", ":!*.md", ":!*.txt", ":!tasks/*", word=True, cwd=cwd)
            if foreign:
                gaps.append(f"dead-code — {sym} has no Go caller but is named in {foreign[0]}; a caller in "
                            f"another language is not something this check can follow")
            elif all_closed and kind == "func":
                # Reported, never gated on: a deliverable in a stack is finished with its
                # first consumer still one PR away, and the check cannot tell that from dead code.
                findings.append({"check": "dead-code", "severity": "warn",
                                 "detail": f"{sym} is defined but referenced nowhere outside its own file and the tests — dead, or waiting on a consumer this branch does not contain ({deffile})"})
            elif kind == "type":
                findings.append({"check": "dead-code", "severity": "warn",
                                 "detail": f"type {sym} is referenced nowhere outside its own file and the tests — check the constructors, wrapper types and struct fields that reach it before removing it ({deffile})"})
            else:
                findings.append({"check": "dead-code", "severity": "warn",
                                 "detail": f"{sym} has no non-test caller yet — a later task may still wire it ({deffile})"})
    # Keyed on what this branch changed, not on what the repository contains.
    changed_ext = {f.rsplit(".", 1)[-1] for f in _lines(gitout("diff", "--name-only", f"{base}..HEAD", cwd=cwd))}
    for lang, exts in (("JavaScript/TypeScript", ("js", "jsx", "ts", "tsx", "mjs", "cjs")), ("Elixir", ("ex", "exs"))):
        if changed_ext & set(exts):
            gaps.append(f"dead-code — {lang} symbols this branch adds were not checked; only Go exported funcs and types are extracted mechanically")
    return findings, gaps


def commit_boundary(records, base, cwd=None):
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
            gaps.append(f"commit-boundary — every file task {n} recorded was also recorded by another task, so whether its work stayed in one commit cannot be told from the file lists")
            continue
        count = sum(1 for c in commits if touched[c] & set(exclusive))
        if count > 1:
            findings.append({"check": "commit-boundary", "severity": "warn",
                             "detail": f"task {n}'s files appear in {count} commits — its work was split or swept into another task's commit"})
    return findings, gaps


def verify(all_closed=False, tasks_override=None, cwd=None):
    th = tasks_home(cwd)
    tasks, _ = breakdown_for(tasks_override, cwd)
    state = state_dir(cwd)
    default = default_branch(cwd)
    head = head_sha(cwd)
    base = gitout("merge-base", "HEAD", default, cwd=cwd) if default else None
    findings, gaps, hints = [], [], []

    # 1. staged-tail — a task that did not close leaves its work staged, so a plain
    #    `git diff` looks empty and the run reads as finished.
    staged = _lines(gitout("diff", "--cached", "--name-only", cwd=cwd))
    dirty = [ln for ln in _lines(gitout("status", "--porcelain", cwd=cwd)) if not ln.startswith("??")][:10]
    if staged:
        findings.append({"check": "staged-tail", "severity": "block",
                         "detail": f"staged but uncommitted: {' '.join(staged)}— an unfinished task, not a stray edit; inspect 'git diff --staged'"})
    elif dirty:
        findings.append({"check": "staged-tail", "severity": "warn",
                         "detail": f"tracked files modified but not staged: {';'.join(dirty)}"})

    # 2. vacuous-receipt — judged from the recorded receipt, because the receipt is what
    #    the gate trusts and it is what must not be hollow.
    rs = receipt_state(state, head, cwd)
    if not rs["fresh"]:
        findings.append({"check": "vacuous-receipt", "severity": "block", "detail": rs["why"]})
    else:
        try:
            tail = json.loads((Path(state) / "receipt.json").read_text()).get("output_tail") or ""
        except (OSError, json.JSONDecodeError):
            tail = ""
        vac = vacuity(tail) if tail else None
        if vac:
            findings.append({"check": "vacuous-receipt", "severity": "block",
                             "detail": f"the receipt's output shows nothing ran: {vac}"})
        elif not tail:
            hints.append("vacuous-receipt — the receipt carries no output tail, so it could not be checked for vacuity; record it with --output-file")

    # 3. dead-code
    if base:
        f, g = dead_code(base, all_closed, cwd)
        findings += f
        gaps += g
    else:
        hints.append("dead-code — no merge-base with a default branch, so the run's own commits could not be scoped")

    # 4. commit-boundary
    records = Path(run_records_dir(state, tasks)) if tasks else None
    if records and records.is_dir() and base:
        f, g = commit_boundary(records, base, cwd)
        findings += f
        gaps += g
    elif not base:
        hints.append("commit-boundary — no merge-base with a default branch, so the run's own commits could not be scoped")
    elif not tasks:
        hints.append(f"commit-boundary — no single breakdown under {th}/tasks, so this run's task records could not be identified; name it with --tasks-file")
    else:
        hints.append(f"commit-boundary — no per-task file records for {Path(tasks).name.removesuffix('.md')}; run tasks through 'clerk finish' for this check")

    findings.sort(key=lambda f: 0 if f["severity"] == "block" else 1)
    clean = not any(f["severity"] == "block" for f in findings)
    return {"clean": clean, "findings": findings, "not_checked": gaps, "hints": hints}
