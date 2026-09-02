"""The run ledger, and the facts every clerk command reads from it.

A run lives under <git-common-dir>/clerk/runs/<slug>/ and its slug is the branch name,
which is the pairing `clerk prepare` already uses to match a worktree to its breakdown. It
sits in the common dir rather than the worktree's because the last steps of a run — the
fast-forward and the learnings — happen in the main checkout after the worktree is gone.

Most evidence of a run's position is a clerk command having run, so the core appends one
line per command to the run's events file and the readers here turn that log into the
signals the step table and the reflection want. `Ctx` is the rest: `clerk prepare`'s
facts for this tree, resolved once per call, with the run this call belongs to.
"""

import json
import os
import subprocess
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from clerk_lib import clerk, die, emit, git, gitout

CALLERS = ("ui", "inbound", "outbound", "async", "exported")


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# --------------------------------------------------------------------------------
# git
# --------------------------------------------------------------------------------

def ref_exists(branch, cwd):
    return git("show-ref", "--verify", "--quiet", f"refs/heads/{branch}", cwd=cwd).returncode == 0


def is_ancestor(branch, of, cwd):
    return git("merge-base", "--is-ancestor", branch, of, cwd=cwd).returncode == 0


def detect_harness():
    h = os.environ.get("CLERK_HARNESS")
    if h:
        return h
    if os.environ.get("CLAUDECODE"):
        return "claude"
    if any(k.startswith("OPENCODE") for k in os.environ):
        return "opencode"
    return "claude"


# --------------------------------------------------------------------------------
# The ledger
# --------------------------------------------------------------------------------

class Run:
    def __init__(self, path):
        self.dir = Path(path)
        self.slug = self.dir.name

    def exists(self):
        return (self.dir / "run.json").exists()

    def read(self, name, default=None):
        p = self.dir / name
        if not p.exists():
            return default
        try:
            return json.loads(p.read_text())
        except json.JSONDecodeError:
            die(f"ledger file {p} is not valid JSON — report this and stop; do not repair it by hand")

    def write(self, name, obj):
        self.dir.mkdir(parents=True, exist_ok=True)
        tmp = self.dir / f"{name}.tmp"
        tmp.write_text(json.dumps(obj, indent=2) + "\n")
        tmp.replace(self.dir / name)

    def append(self, name, obj):
        self.dir.mkdir(parents=True, exist_ok=True)
        with (self.dir / name).open("a") as fh:
            fh.write(json.dumps(obj) + "\n")

    @property
    def meta(self):
        return self.read("run.json", {})

    @property
    def finished(self):
        return bool(self.meta.get("finished"))

    @property
    def done(self):
        return self.read("done.json", {})

    def mark(self, key, record):
        d = self.done
        d[key] = record
        self.write("done.json", d)


def runs_root(common):
    return Path(common) / "clerk" / "runs"


def run_summary(run, cwd):
    bd = run.read("breakdown.json")
    progress = None
    side_path = Path(bd["sidecar"]) if bd else None
    if side_path and not side_path.exists():
        cand = side_path.parent / "completed" / side_path.name
        side_path = cand if cand.exists() else side_path
    if side_path and side_path.exists():
        side = json.loads(side_path.read_text())
        tasks = side.get("tasks", [])
        progress = {"done": sum(1 for t in tasks if t.get("done")), "total": len(tasks)}
    return {"slug": run.slug, "request": run.meta.get("request"), "started_at": run.meta.get("started_at"),
            "finished": run.finished, "branch_exists": ref_exists(run.slug, cwd),
            "breakdown": bd["tasks_file"] if bd else None, "tasks": progress}


# --------------------------------------------------------------------------------
# The event log: what clerk commands ran for this run, appended by clerk itself
# --------------------------------------------------------------------------------

def events(run):
    p = run.dir / "events.jsonl"
    if not p.exists():
        return []
    out = []
    for line in p.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def flag_value(argv, flag):
    if flag in argv:
        i = argv.index(flag)
        if i + 1 < len(argv):
            return argv[i + 1]
    return None


def guidelines_read(run):
    """The `clerk guidelines` run that counts: it succeeded and named the caller pattern."""
    for e in events(run):
        if e.get("cmd") != "guidelines" or e.get("exit") != 0:
            continue
        argv = e.get("argv", [])
        caller = flag_value(argv, "--caller")
        if caller in CALLERS:
            return {"caller": caller, "dom": "--dom" in argv, "state": "--state" in argv, "at": e.get("at"),
                    "source": "clerk guidelines"}
    return None


def learn_written(run):
    for e in events(run):
        if e.get("cmd") == "learn" and e.get("exit") == 0 and "--title" in e.get("argv", []):
            return {"at": e.get("at"), "title": flag_value(e.get("argv", []), "--title"), "source": "clerk learn"}
    return None


def task_signals(run):
    """Per task, the two observed signals the method reads as the plan being wrong about
    it: `clerk finish N --retried` (the first shape reached for was not the one that went
    green) and a lint finding — a `lint --staged` that reported after N was finished, or a
    `finish N` that refused. Returns ({n: {...}}, [n in finish order])."""
    signals = {}
    order = []
    last_done = None
    for e in events(run):
        cmd, argv, rc = e.get("cmd"), e.get("argv", []), e.get("exit")
        if cmd == "lint" and "--staged" in argv and rc == 1 and last_done is not None:
            signals[last_done]["lint_findings"] = True
        if cmd == "finish" and argv and str(argv[0]).isdigit():
            n = int(argv[0])
            sig = signals.setdefault(n, {"retried": False, "lint_findings": False, "attempts": 0})
            sig["attempts"] += 1
            if rc == 1:
                sig["lint_findings"] = True
            elif rc == 0:
                sig["retried"] = sig["retried"] or "--retried" in argv
                if n not in order:
                    order.append(n)
                last_done = n
    return signals, order


def gear(signals, order):
    """`low` once a task showed a signal, `normal` again after two clean tasks in a row —
    a pause that arrives on every task stops carrying information."""
    low, streak = False, 0
    for n in order:
        sig = signals.get(n, {})
        if sig.get("retried") or sig.get("lint_findings"):
            low, streak = True, 0
        else:
            streak += 1
            if low and streak >= 2:
                low, streak = False, 0
    return "low" if low else "normal"


def fixup_ambiguities(run):
    return sum(1 for e in events(run) if e.get("cmd") == "fixup" and e.get("exit") == 3)


# --------------------------------------------------------------------------------
# Context: the facts every step reads
# --------------------------------------------------------------------------------

@dataclass
class Ctx:
    """The facts every step reads, resolved once per call. Most are `clerk prepare`'s —
    the run this tree belongs to, the receipt it holds, HEAD's code tree — so the rule
    behind each lives in clerk and is applied here, not reimplemented."""
    cwd: str
    common: str
    git_dir: str = None
    branch: str = None
    head: str = None
    head_ct: str = None
    default: str = None
    run: Run = None
    prepare: dict = field(default_factory=dict)
    flags: dict = field(default_factory=dict)
    build_tree: str = None
    repo_root: str = None
    in_worktree: bool = False
    harness: str = None
    read_only: bool = False  # --status: look without recording anything
    adhoc: bool = False  # an audit of a branch with no implement run behind it
    full: bool = False  # --full: print the step's text even if this session has seen it
    branch_state: dict = None  # where the run's branch stands, resolved once by clerk_steps.run_branch


def build_ctx(explicit_run=None, harness=None, read_only=False, full=False, pick=False):
    cwd = os.getcwd()
    common = gitout("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=cwd)
    if not common:
        die("not a git repository")
    # `clerk prepare` resolves the run this tree belongs to and applies that run's request
    # itself, so one call is the facts with the flags in force. Only a `--run` naming a
    # different run asks again, with that run's request.
    rc, prep, err = clerk("prepare", cwd=cwd)
    if rc != 0 or not prep:
        die(f"clerk prepare failed: {err or 'no output'}")
    ctx = Ctx(cwd=cwd, common=common, git_dir=gitout("rev-parse", "--absolute-git-dir", cwd=cwd),
              branch=prep.get("branch") or None, head=gitout("rev-parse", "HEAD", cwd=cwd),
              default=prep.get("default_branch"), prepare=prep, read_only=read_only, full=full)
    ctx.run = resolve_run(ctx, explicit_run, pick=pick)
    if ctx.run is not None and prep.get("run") != ctx.run.slug:
        rc, prep, err = clerk("prepare", "--request", ctx.run.meta.get("request") or "", cwd=cwd)
        if rc != 0 or not prep:
            die(f"clerk prepare failed: {err or 'no output'}")
        ctx.prepare = prep
    ctx.head_ct = prep.get("code_tree")
    ctx.flags = prep.get("flags", {})
    ctx.build_tree = prep.get("build_tree")
    ctx.repo_root = prep.get("repo_root")
    ctx.in_worktree = bool(prep.get("in_worktree"))
    ctx.harness = harness or (ctx.run.meta.get("harness") if ctx.run else None) or detect_harness()
    return ctx


def resolve_run(ctx, explicit, pick=False):
    """Which ledger this call belongs to: `--run`, else the one `clerk prepare` resolved
    (named by the branch, or the single open run from the default branch). Several open
    runs from there is a choice the caller has to make, the way `prepare` refuses to
    pick between breakdowns — unless the command has its own way of asking (`pick`)."""
    if explicit:
        run = Run(runs_root(ctx.common) / explicit)
        if not run.exists():
            die(f"no run '{explicit}' — `clerk step --status` from the default branch lists them")
        return run
    slug = ctx.prepare.get("run")
    if slug:
        return Run(runs_root(ctx.common) / slug)
    open_runs = ctx.prepare.get("runs_open") or []
    on_feature = ctx.branch and ctx.branch not in (ctx.default, "HEAD")
    if len(open_runs) > 1 and not on_feature:
        if pick:
            return None
        emit({"step": "start", "blocked": True,
              "reason": f"{len(open_runs)} runs are open; name the one this call is for with --run <slug>",
              "open_runs": open_run_summaries(ctx)}, 3)
    return None


def open_run_summaries(ctx):
    return [run_summary(Run(runs_root(ctx.common) / slug), ctx.cwd)
            for slug in ctx.prepare.get("runs_open") or []]


def all_run_summaries(ctx):
    """Every run this repository has kept, finished or not, newest first."""
    root = runs_root(ctx.common)
    runs = [Run(d) for d in root.iterdir() if (d / "run.json").exists()] if root.is_dir() else []
    rows = [run_summary(r, ctx.cwd) for r in runs]
    rows.sort(key=lambda r: r.get("started_at") or "", reverse=True)
    return rows


def session_id():
    return os.environ.get("CLAUDE_CODE_SESSION_ID") or os.environ.get("OPENCODE_SESSION_ID") or None


def age_seconds(at):
    try:
        then = datetime.strptime(at, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return float("inf")
    return (datetime.now(timezone.utc) - then).total_seconds()


def receipt_state(ctx):
    """(fresh, receipt, why) as `clerk prepare` judged it — fresh when the receipt passed
    and describes HEAD's code tree. The same judgment gate and verify make."""
    rs = ctx.prepare.get("receipt") or {}
    rec = rs if rs.get("recorded") else None
    return bool(rs.get("fresh")), rec, rs.get("why")


# --------------------------------------------------------------------------------
# The live audit round's runner
# --------------------------------------------------------------------------------


def live_of(aud):
    return aud.get("live")


def runner_alive(pid):
    """Whether the process a live round names is still the one driving it. The pid alone
    does not say: numbers are reused, and a stranger's process would read as a runner."""
    try:
        os.kill(int(pid), 0)
    except (ProcessLookupError, TypeError, ValueError):
        return False
    except PermissionError:
        return True
    ps = subprocess.run(["ps", "-o", "command=", "-p", str(pid)], capture_output=True, text=True)
    return "clerk" in ps.stdout


def runner_view(lv):
    r = (lv or {}).get("runner")
    if not r:
        return None
    agents = r.get("agents") or {}
    return {"pid": r.get("pid"), "alive": runner_alive(r.get("pid")), "phase": r.get("phase"),
            "started_at": r.get("started_at"), "beat_at": r.get("beat_at"),
            "finished_at": r.get("finished_at"), "died": r.get("died"),
            "landed": sorted(k for k, a in agents.items() if a.get("landed_at")),
            "in_flight": sorted(k for k, a in agents.items() if not a.get("landed_at"))}


def note_runner_dead(ctx, aud):
    """The incident for a runner that is gone without having said so, written once."""
    lv = live_of(aud)
    v = runner_view(lv)
    if not v or v["alive"] or v["finished_at"] or v["died"]:
        return None
    lv["runner"]["died"] = now()
    entry = {"at": now(), "kind": "runner-died", "round": lv["round"], "phase": v["phase"],
             "pid": v["pid"], "last_beat": v["beat_at"], "kept": v["landed"], "lost": v["in_flight"]}
    aud.setdefault("incidents", []).append(entry)
    ctx.run.write("audit.json", aud)
    return entry
