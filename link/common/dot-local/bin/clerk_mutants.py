import json
import os
import shutil
import signal
import subprocess
import tempfile
from pathlib import Path

from clerk_audit_panel import MUTATED_FILE_RE, TEST_PATH_RE
from clerk_repo import now

INSTALL = "mise install github:hpcsc/mutants"
NEEDED_FLAGS = ("--caller-gaps", "--proposals", "--proposals-anywhere")
REPORTED = ("LIVED", "NOT COVERED", "TIMED OUT", "INFRA ERROR")
SURVIVED = ("LIVED", "NOT COVERED")
SAVED = "mutants.json"
ACCEPTED = "mutants-accepted.jsonl"
LIMIT_SECONDS = 600
GRACE_SECONDS = 30
TIMED_OUT = 124
RERUN_KILLED = 0
RERUN_SURVIVED = 10


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
            "no_tests": [], "caller_gaps": [], "proposals": None, "by_ref": {}, "killed": []}


def summarise(data, complete=True):
    rows, no_tests, by_ref, killed, inside = [], {}, {}, [], {}
    for m in data.get("mutants") or []:
        for ref in m.get("refs") or []:
            by_ref[ref] = {"status": m.get("status"), "id": m.get("id"), "file": m.get("file"),
                           "line": m.get("line"), "detail": m.get("detail") or ""}
        if m.get("status") == "KILLED":
            killed.append(m.get("id"))
        if m.get("status") not in REPORTED:
            continue
        # mutants gives one detail to each mutant of a group that no test runs, such as a
        # package with no test files.
        if m.get("status") == "NOT COVERED" and m.get("detail"):
            group = no_tests.setdefault(m["detail"], {"mutants": 0, "files": set()})
            group["mutants"] += 1
            group["files"].add(m.get("file"))
            continue
        if m.get("status") == "NOT COVERED" and m.get("inside"):
            inside[m["inside"]] = inside.get(m["inside"], 0) + 1
            continue
        rows.append({"id": m.get("id"), "file": m.get("file"), "line": m.get("line"),
                     "status": m.get("status"), "type": m.get("operator"),
                     "original": m.get("original") or "", "replacement": m.get("replacement") or "",
                     "bug": m.get("bug") or None})
    for row in rows:
        if row["id"] in inside:
            row["uncovered_inside"] = inside[row["id"]]
    proposals = data.get("proposals")
    for rejected in (proposals or {}).get("rejected") or []:
        if rejected.get("ref"):
            by_ref[rejected["ref"]] = {"status": "REJECTED", "id": None, "file": rejected.get("file"),
                                       "line": None, "detail": rejected.get("reason") or ""}
    return {"ran": True, "reason": None, "complete": complete, "base": data.get("base"),
            "mutants": rows,
            "no_tests": [{"detail": d, "mutants": g["mutants"], "files": sorted(g["files"])}
                         for d, g in sorted(no_tests.items())],
            "caller_gaps": [{"file": g.get("file"), "function": g.get("function"),
                             "lines": list(g.get("lines") or []), "callers": list(g.get("callers") or [])}
                            for g in data.get("callerGaps") or []],
            "proposals": proposals, "by_ref": by_ref, "killed": killed}


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


def rerun(cwd, mutant_id, capture=False, base=None):
    exe, reason = locate()
    if not exe:
        return 2, reason
    argv = [exe, "rerun"]
    # an older mutants has no --base on rerun
    if base and "--base" in subprocess.run([exe, "rerun", "--help"], capture_output=True, text=True).stdout:
        argv += ["--base", base]
    r = subprocess.run([*argv, mutant_id], cwd=cwd, text=True, capture_output=capture)
    return r.returncode, (r.stdout + r.stderr) if capture else ""


# --------------------------------------------------------------------------------
# The last run of `clerk mutants`, kept in the run's ledger for `clerk finish`
# --------------------------------------------------------------------------------

def source_file(path):
    return bool(MUTATED_FILE_RE.search(path)) and not TEST_PATH_RE.search(path)


def _git(cwd, *args):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def changed_sources(cwd, base):
    # mutants compares the work tree with the merge base, and reads the untracked files too
    diff = _git(cwd, "diff", "--name-only", "--no-renames", "--diff-filter=d", "--merge-base", base) or ""
    untracked = _git(cwd, "ls-files", "--others", "--exclude-standard") or ""
    return sorted({p for p in (diff + untracked).splitlines() if p and source_file(p)})


def content_hashes(cwd, paths):
    paths = [p for p in paths if (Path(cwd) / p).is_file()]
    if not paths:
        return {}
    out = _git(cwd, "hash-object", "--", *paths)
    return dict(zip(paths, out.split())) if out else {}


def load(ldir):
    p = Path(ldir) / SAVED if ldir else None
    if not p or not p.is_file():
        return None
    try:
        return json.loads(p.read_text())
    except json.JSONDecodeError:
        return None


def _write(ldir, record):
    tmp = Path(ldir) / f"{SAVED}.tmp"
    tmp.write_text(json.dumps(record, indent=2) + "\n")
    tmp.replace(Path(ldir) / SAVED)


def save(ldir, cwd, base, result, every_operator):
    """A run of some operators adds its rows and never counts as a read of the content, so it
    cannot stand in for a run of every operator."""
    if not ldir or not Path(ldir).is_dir():
        return
    saved = load(ldir)
    if every_operator:
        record = {"at": now(), "base": base, "ran": result["ran"], "reason": result["reason"],
                  "complete": result["complete"], "rows": result["mutants"], "no_tests": result["no_tests"],
                  "caller_gaps": result["caller_gaps"], "killed": [],
                  "files": content_hashes(cwd, changed_sources(cwd, base)) if result["ran"] else {}}
    elif not result["ran"]:
        return
    elif saved and saved.get("ran"):
        killed = set(result["killed"])
        fresh = {r["id"] for r in result["mutants"]}
        record = dict(saved, rows=[r for r in saved.get("rows") or [] if r["id"] not in killed | fresh]
                      + result["mutants"],
                      killed=sorted(set(saved.get("killed") or []) | killed))
    else:
        record = {"at": now(), "base": base, "ran": True, "reason": None, "complete": result["complete"],
                  "rows": result["mutants"], "no_tests": result["no_tests"],
                  "caller_gaps": result["caller_gaps"], "killed": [], "files": {}}
    _write(ldir, record)


def note_killed(ldir, mutant_id):
    saved = load(ldir)
    if not saved:
        return
    saved["killed"] = sorted(set(saved.get("killed") or []) | {mutant_id})
    _write(ldir, saved)


def gap_key(gap):
    return f"{gap.get('file')}:{gap.get('function')}"


def keys(saved):
    saved = saved or {}
    return ({r.get("id") for r in saved.get("rows") or []}
            | {gap_key(g) for g in saved.get("caller_gaps") or []}
            | {g.get("detail") for g in saved.get("no_tests") or []})


def accept(ldir, key, reason, task=None):
    with (Path(ldir) / ACCEPTED).open("a") as fh:
        fh.write(json.dumps({"key": key, "reason": reason, "at": now(), "task": task}) + "\n")


def accepted(ldir):
    p = Path(ldir) / ACCEPTED if ldir else None
    if not p or not p.is_file():
        return {}
    out = {}
    for line in p.read_text().splitlines():
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(entry, dict) and entry.get("key") and entry.get("reason"):
            out[entry["key"]] = entry["reason"]
    return out


def _one_line(text):
    return " ".join(str(text or "").split())


def finish_check(root, ldir, files):
    """(findings, kind, state): kind is "stale" or "rows" for a refusal, and None for a pass,
    whose state says what was checked."""
    top = Path(root).resolve()
    named = []
    for f in files:
        try:
            named.append(Path(f).resolve().relative_to(top).as_posix())
        except ValueError:
            continue
    sources = [p for p in named if source_file(p)
               and _git(root, "diff", "--quiet", "HEAD", "--", p) is None]
    if not sources:
        return [], None, "not checked: the task changes no Go or Python file outside the tests"
    if not ldir:
        return [], None, "not checked: no run is open"
    saved = load(ldir)
    if saved and not saved.get("ran"):
        return [], None, f"not checked: the last clerk mutants did not run: {saved.get('reason')}"
    hashes = content_hashes(root, sources)
    read = (saved or {}).get("files") or {}
    stale = [p for p in sources if read.get(p) != hashes.get(p)]
    if stale:
        exe, why = locate()
        if not exe:
            return [], None, f"not checked: {why}"
        return [{"file": p, "status": "CHANGED AFTER THE LAST RUN" if p in read else "NOT READ BY A RUN"}
                for p in stale], "stale", None

    taken, mine = accepted(ldir), set(sources)
    closed = set(saved.get("killed") or []) | set(taken)
    findings = []
    for r in saved.get("rows") or []:
        if r.get("status") in SURVIVED and r.get("file") in mine and r.get("id") not in closed:
            text = r["bug"] if r.get("bug") else (f"{r.get('type')}: {_one_line(r.get('original'))} -> "
                                                  f"{_one_line(r.get('replacement')) or '(nothing)'}")
            findings.append({"key": r.get("id"), "file": r.get("file"), "line": r.get("line"),
                             "status": r.get("status"), "row": text})
    for g in saved.get("caller_gaps") or []:
        if g.get("file") in mine and gap_key(g) not in taken:
            findings.append({"key": gap_key(g), "file": g.get("file"), "status": "CALLER GAP",
                             "row": f"lines {','.join(map(str, g.get('lines') or []))} not run by the tests of "
                                    f"{', '.join(g.get('callers') or [])}"})
    for g in saved.get("no_tests") or []:
        if mine & set(g.get("files") or []) and g.get("detail") not in taken:
            findings.append({"key": g.get("detail"), "file": ", ".join(sorted(mine & set(g["files"]))),
                             "status": "NO TESTS", "row": f"{g.get('mutants')} mutants"})
    if findings:
        return findings, "rows", None
    state = "clean"
    if not saved.get("complete", True):
        state += "; the last run stopped at its time limit, so it holds only the mutants that got a verdict"
    return [], None, state
