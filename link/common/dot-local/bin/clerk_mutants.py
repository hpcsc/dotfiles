import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
from pathlib import Path

INSTALL = "mise install github:hpcsc/mutants"
NEEDED_FLAGS = ("--caller-gaps", "--proposals", "--proposals-anywhere")
REPORTED = ("LIVED", "NOT COVERED", "TIMED OUT", "INFRA ERROR")
LIMIT_SECONDS = 600
GRACE_SECONDS = 30
TIMED_OUT = 124
RERUN_KILLED = 0
RERUN_SURVIVED = 10
NO_TEST_FILES = re.compile(r"^package (\S+) has no test files$")


def find_binary():
    explicit = os.environ.get("CLERK_MUTANTS_BIN")
    if explicit is not None:
        return explicit if os.access(explicit, os.X_OK) else None
    on_path = shutil.which("mutants")
    if on_path:
        return on_path
    # mise puts its tools on PATH only in a shell that activates it, which an agent's shell does not.
    if not shutil.which("mise"):
        return None
    r = subprocess.run(["mise", "which", "mutants"], capture_output=True, text=True)
    path = r.stdout.strip()
    return path if r.returncode == 0 and path and os.access(path, os.X_OK) else None


def locate():
    exe = find_binary()
    if not exe:
        return None, f"mutants is not installed: {INSTALL}"
    r = subprocess.run([exe, "run", "--help"], capture_output=True, text=True)
    missing = [f for f in NEEDED_FLAGS if f not in r.stdout + r.stderr]
    if missing:
        return None, f"{exe} has no {', '.join(missing)}: {INSTALL}"
    return exe, None


def not_run(reason):
    return {"ran": False, "reason": reason, "complete": False, "base": None, "mutants": [],
            "no_tests": [], "caller_gaps": [], "proposals": None, "by_ref": {}}


def summarise(data, complete=True):
    rows, no_tests, by_ref = [], {}, {}
    for m in data.get("mutants") or []:
        for ref in m.get("refs") or []:
            by_ref[ref] = {"status": m.get("status"), "id": m.get("id"), "file": m.get("file"),
                           "line": m.get("line"), "detail": m.get("detail") or ""}
        if m.get("status") not in REPORTED:
            continue
        empty = NO_TEST_FILES.match(m.get("detail") or "")
        if empty:
            no_tests[empty.group(1)] = no_tests.get(empty.group(1), 0) + 1
            continue
        rows.append({"id": m.get("id"), "file": m.get("file"), "line": m.get("line"),
                     "status": m.get("status"), "type": m.get("operator"),
                     "original": m.get("original") or "", "replacement": m.get("replacement") or "",
                     "bug": m.get("bug") or None})
    proposals = data.get("proposals")
    for rejected in (proposals or {}).get("rejected") or []:
        if rejected.get("ref"):
            by_ref[rejected["ref"]] = {"status": "REJECTED", "id": None, "file": rejected.get("file"),
                                       "line": None, "detail": rejected.get("reason") or ""}
    return {"ran": True, "reason": None, "complete": complete, "base": data.get("base"),
            "mutants": rows,
            "no_tests": [{"package": p, "mutants": n} for p, n in sorted(no_tests.items())],
            "caller_gaps": [{"file": g.get("file"), "function": g.get("function"),
                             "lines": list(g.get("lines") or []), "callers": list(g.get("callers") or [])}
                            for g in data.get("callerGaps") or []],
            "proposals": proposals, "by_ref": by_ref}


def _limited(argv, cwd, echo):
    proc = subprocess.Popen(argv, cwd=cwd, text=True,
                            stdout=None if echo else subprocess.DEVNULL,
                            stderr=None if echo else subprocess.PIPE)
    try:
        _, err = proc.communicate(timeout=LIMIT_SECONDS + GRACE_SECONDS)
        stopped = False
    except subprocess.TimeoutExpired:
        # mutants stops its test processes on SIGTERM, and cannot on SIGKILL.
        proc.send_signal(signal.SIGTERM)
        try:
            _, err = proc.communicate(timeout=GRACE_SECONDS)
        except subprocess.TimeoutExpired:
            proc.kill()
            _, err = proc.communicate()
        stopped = True
    # mutants exits 130 when a signal stops it, which here means the run did not finish.
    code = TIMED_OUT if stopped or proc.returncode == 130 else proc.returncode
    return code, err or ""


def run(cwd, base, *, proposals=None, anywhere=False, operators=None, caller_gaps=True, echo=False):
    exe, reason = locate()
    if not exe:
        return 2, not_run(reason)
    with tempfile.TemporaryDirectory(prefix="clerk-mutants-") as tmp:
        report = Path(tmp) / "report.json"
        argv = [exe, "run", "--base", base, "--workers", "4", "--limit", f"{LIMIT_SECONDS}s",
                "--json", str(report)]
        if caller_gaps:
            argv.append("--caller-gaps")
        if operators:
            argv.append(f"--operators={operators}")
        if proposals:
            argv += ["--proposals", str(proposals)]
        if anywhere:
            argv.append("--proposals-anywhere")
        code, err = _limited(argv, cwd, echo)
        try:
            data = json.loads(report.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            data = None
    if code not in (0, 10, TIMED_OUT) or not isinstance(data, dict):
        last = next((line for line in reversed(err.splitlines()) if line.strip()), "")
        return (TIMED_OUT if code == TIMED_OUT else 2), not_run(last or f"mutants exited {code} with no report")
    return code, summarise(data, complete=code != TIMED_OUT)


def rerun(cwd, mutant_id, capture=False):
    exe, reason = locate()
    if not exe:
        return 2, reason
    r = subprocess.run([exe, "rerun", mutant_id], cwd=cwd, text=True,
                       capture_output=capture)
    return r.returncode, (r.stdout + r.stderr) if capture else ""
