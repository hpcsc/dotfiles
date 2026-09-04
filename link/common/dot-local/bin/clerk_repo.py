"""The repository as clerk sees it: the facts `clerk prepare` reports, the precedence rules
behind them, and the run ledger's writers.

Everything here is a resolution a program does more reliably than a prompt — which test
command wins, where the breakdown lives when tasks/ is excluded, which branch is default,
whether the recorded receipt still describes HEAD. Each is decided once, here, and every
command reads the answer rather than deriving its own.
"""

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

from clerk_lib import die, git, gitout

FLAG_KEYS = ("in_place", "integrate", "review_breakdown", "gears")
# The spelling a request uses for each flag. Kept beside the resolver because the two
# must agree: a token this does not list is a flag the caller can type and watch be
# ignored, which is worse than one that is not offered at all.
FLAG_WORDS = {"in_place": ("--in-place", "--worktree"), "integrate": ("--integrate", "--no-integrate"),
              "review_breakdown": ("--review-breakdown", "--no-review-breakdown"),
              "gears": ("--gears", "--no-gears")}


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# --------------------------------------------------------------------------------
# Where things are
# --------------------------------------------------------------------------------

def work_tree(cwd=None):
    """The tree we are standing in. Inside a worktree it is on another branch entirely,
    and a suite pointed at the main checkout tests code without the feature in it."""
    return gitout("rev-parse", "--show-toplevel", cwd=cwd)


def common_dir(cwd=None):
    return gitout("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=cwd)


def repo_root(cwd=None):
    """The main repo root, which is NOT the work tree inside a worktree. tasks/ and the
    learnings file live here."""
    c = common_dir(cwd)
    return str(Path(c).parent) if c else None


def state_dir(cwd=None):
    """Per-worktree, inside the git dir, so state is never committed and needs no ignore
    entry."""
    gd = gitout("rev-parse", "--absolute-git-dir", cwd=cwd)
    return f"{gd}/clerk" if gd else None


def run_records_dir(state, tasks_file):
    """Where `finish` records which files belonged to which task, one directory per
    breakdown: keyed on the task number alone, a second story's records overwrote the
    first's and outlived the runs that wrote them."""
    return f"{state}/tasks/{Path(tasks_file).name.removesuffix('.md')}"


def default_branch(cwd=None):
    d = ""
    # Without a remote, `rev-parse --abbrev-ref origin/HEAD` echoes the literal back, and a
    # base of HEAD makes every base..HEAD diff silently empty.
    if git("show-ref", "--verify", "--quiet", "refs/remotes/origin/HEAD", cwd=cwd).returncode == 0:
        d = (gitout("rev-parse", "--abbrev-ref", "origin/HEAD", cwd=cwd) or "").removeprefix("origin/")
    if d in ("", "HEAD", "origin/HEAD"):
        d = ""
        for c in ("main", "master"):
            if git("show-ref", "--verify", "--quiet", f"refs/heads/{c}", cwd=cwd).returncode == 0:
                d = c
                break
    return d


def current_branch(cwd=None):
    return gitout("rev-parse", "--abbrev-ref", "HEAD", cwd=cwd) or ""


def head_sha(cwd=None):
    return gitout("rev-parse", "HEAD", cwd=cwd)


def tree_is_clean(cwd=None):
    return not (gitout("status", "--porcelain", cwd=cwd) or "")


def is_ignored(directory, rel):
    """As the repo's own rules see it: .gitignore, info/exclude and a global excludes file
    alike — a repo that keeps tasks/ out of history usually does it through info/exclude."""
    return git("check-ignore", "-q", "--", rel, cwd=directory).returncode == 0


# --------------------------------------------------------------------------------
# The run ledger: which run this tree belongs to, and the writers every command shares
# --------------------------------------------------------------------------------

def runs_dir(cwd=None):
    c = common_dir(cwd)
    return Path(c) / "clerk" / "runs" if c else None


def open_runs(cwd=None):
    """Every run under <git-common-dir>/clerk/runs that has not finished."""
    root = runs_dir(cwd)
    if not root or not root.is_dir():
        return []
    out = []
    for d in sorted(root.iterdir()):
        rj = d / "run.json"
        if not rj.is_file():
            continue
        try:
            finished = json.loads(rj.read_text()).get("finished")
        except (OSError, json.JSONDecodeError):
            finished = None
        if finished is not True:
            out.append(d.name)
    return out


def ledger_dir(cwd=None):
    """The ledger this invocation belongs to, or None. On a feature branch it is the run
    named by the branch; on the default branch it is the one unfinished run, if there is
    exactly one — the rule `clerk step` resolves by, so the two never disagree."""
    root = runs_dir(cwd)
    if not root or not root.is_dir():
        return None
    branch = current_branch(cwd)
    if branch and branch != "HEAD" and branch != default_branch(cwd):
        return str(root / branch) if (root / branch / "run.json").is_file() else None
    open_ = open_runs(cwd)
    return str(root / open_[0]) if len(open_) == 1 else None


def ledger_read(path, default=None):
    """A ledger file, or `default` when it is not there. Malformed is not missing: a run
    whose own record will not parse is in a state nobody knows, and answering from a
    default would act on a guess. Repo config — package.json, tasks/clerk.json — reads
    through `_json_file` instead, where a bad file is the user's to fix and falling back
    to detection is a safe answer."""
    p = Path(path)
    if not p.exists():
        return default
    try:
        return json.loads(p.read_text())
    except json.JSONDecodeError:
        die(f"ledger file {p} is not valid JSON — report this and stop; do not repair it by hand")


def run_section(directory, name, default=None):
    """One of the run's records — its breakdown, its asserted steps, its match-request,
    its land stamp — read out of run.json, where they all live. Ledgers written by an
    older clerk hold each in a <name>.json beside it, so a key run.json does not have
    falls back to that file; drop the fallback once no such ledger is open."""
    if not directory:
        return default
    meta = ledger_read(Path(directory) / "run.json")
    if isinstance(meta, dict) and name in meta:
        return meta[name]
    legacy = ledger_read(Path(directory) / f"{name.replace('_', '-')}.json")
    return default if legacy is None else legacy


def breakdown_side(bd):
    """The task record a run's breakdown points at. Ledgers written before the record was
    renamed hold the path under `sidecar`, and three callers indexed the new name straight
    — so a run started by an older clerk crashed `clerk step` rather than resolving. Drop
    the fallback once no such ledger is open."""
    if not bd:
        return None
    return bd.get("task_record") or bd.get("sidecar")


def ledger_log(directory, cmd, rc, argv, cwd=None):
    """Appends one event. Never fails the command it records: a logging error must not
    turn a finished task into a failed one."""
    if not directory or not Path(directory).is_dir():
        return
    try:
        with (Path(directory) / "events.jsonl").open("a") as fh:
            fh.write(json.dumps({"cmd": cmd, "argv": list(argv), "exit": int(rc), "at": now(),
                                 "head": head_sha(cwd) or ""}) + "\n")
    except OSError:
        pass


# --------------------------------------------------------------------------------
# The code tree and the receipt
# --------------------------------------------------------------------------------

_BREAKDOWN_FILE = re.compile(r"\ttasks/.*\.(md|json|ya?ml)$")


def code_tree(rev, cwd=None):
    """The identity of the code at a revision: its tree listing minus the breakdown files
    under tasks/. The receipt and the acceptance compare by this rather than by SHA, so a
    tasks/-only commit — the Theory, the archive — does not make a green stale."""
    listing = gitout("ls-tree", "-r", rev, cwd=cwd)
    if listing is None:
        return None
    kept = [ln for ln in listing.split("\n") if not _BREAKDOWN_FILE.search(ln)]
    return hashlib.sha1("\n".join(kept).encode()).hexdigest()


def receipt_state(state, head, cwd=None):
    """The recorded suite receipt, and whether it still describes HEAD: it passed, and the
    code it ran against is the code at HEAD by code tree."""
    rec = Path(state) / "receipt.json" if state else None
    if not rec or not rec.is_file():
        return {"recorded": False, "fresh": False, "passed": False, "sha": None, "command": None,
                "at": None, "why": "no suite receipt recorded"}
    try:
        r = json.loads(rec.read_text())
    except (OSError, json.JSONDecodeError):
        r = {}
    sha, passed = r.get("sha") or "", r.get("passed") is True
    fresh, why = False, None
    if not passed:
        why = f"the recorded receipt failed: {r.get('command') or ''}"
    elif sha != head and code_tree(sha, cwd) != code_tree(head, cwd):
        why = (f"the receipt describes {sha[:8]}, HEAD is {(head or '')[:8]} — the tree changed after "
               f"the suite ran, and the code changed with it, not only tasks/; re-run it")
    else:
        fresh = True
    return {"recorded": True, "fresh": fresh, "passed": passed, "sha": sha, "command": r.get("command") or "",
            "at": r.get("at") or "", "why": why}


# --------------------------------------------------------------------------------
# Languages, test commands, the machine-local environment
# --------------------------------------------------------------------------------

def detect_languages(root):
    """Every match, not just the first: a repo with go.mod and package.json is both."""
    r = Path(root)
    out = []
    if (r / "go.mod").is_file():
        out.append("Go")
    if (r / "package.json").is_file():
        out.append("JavaScript/TypeScript")
    if (r / "mix.exs").is_file():
        out.append("Elixir")
    if (r / "Gemfile").is_file() or any(r.glob("*.gemspec")):
        out.append("Ruby")
    if any((r / f).is_file() for f in ("pyproject.toml", "setup.py", "requirements.txt")):
        out.append("Python")
    if (r / "Cargo.toml").is_file():
        out.append("Rust")
    if any(r.glob("*.tf")):
        out.append("HCL")
    return out


def env_get(path, key):
    """A value from tasks/.environment — JSON as the opencode sibling writes it, or
    key=value so a hand-written one works. `has` rather than a default, so a stored false
    can turn a setting off. None when absent or empty."""
    p = Path(path)
    if not p.is_file():
        return None
    try:
        text = p.read_text()
    except OSError:
        return None
    if text.lstrip().startswith("{"):
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            return None
        if not isinstance(data, dict) or key not in data:
            return None
        v = data[key]
        v = v if isinstance(v, str) else json.dumps(v)
        return v or None
    for line in text.splitlines():
        if line.startswith(f"{key}="):
            v = line[len(key) + 1:]
            if v.startswith('"'):
                v = v[1:]
            if v.endswith('"'):
                v = v[:-1]
            return v or None
    return None


def _json_file(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError):
        return None


def resolve_test_commands(root):
    """A team decision beats a machine cache beats a guess."""
    r = Path(root)
    cfg = _json_file(r / "tasks" / "test-commands.json")
    if cfg is not None:
        return cfg
    cmd = env_get(r / "tasks" / ".environment", "test_command")
    if cmd:
        return {"default": cmd, "_source": "tasks/.environment"}
    if (r / "Taskfile.yml").is_file() or (r / "Taskfile.yaml").is_file():
        return {"default": "task test", "_source": "detected: Taskfile"}
    mk = r / "Makefile"
    if mk.is_file() and re.search(r"(?m)^test:", mk.read_text(errors="replace")):
        return {"default": "make test", "_source": "detected: Makefile"}
    pkg = _json_file(r / "package.json")
    if isinstance(pkg, dict) and (pkg.get("scripts") or {}).get("test"):
        return {"default": "npm test", "_source": "detected: package.json"}
    if (r / "go.mod").is_file():
        return {"default": "go test ./...", "_source": "detected: go.mod"}
    return {"_source": "undetected"}


def resolve_go_prefix(root):
    """Whether THIS machine runs Go through mise. Gitignored for that reason, decided
    once, never double-wrapped."""
    r = Path(root)
    p = env_get(r / "tasks" / ".environment", "go_tool_prefix")
    if p:
        return p
    if not (r / "go.mod").is_file():
        return ""
    for name in ("mise.toml", ".mise.toml", "mise.local.toml", ".mise.local.toml"):
        f = r / name
        if f.is_file() and re.search(r"(?m)^\s*go\s*=", f.read_text(errors="replace")):
            return "mise exec -- "
    return ""


def resolve_learnings_path(root):
    """In-tree when the repo tracks tasks/, out-of-tree per project when it gitignores it."""
    if is_ignored(root, "tasks/learnings.md"):
        slug = str(root).replace("/", "-").lstrip("-")
        return f"{Path.home()}/.claude/implement-learnings/{slug}/learnings.md"
    return f"{root}/tasks/learnings.md"


def request_tokens(request):
    return (request or "").split()


def request_learnings_path(request, root):
    """`--learnings-path <p>` or `--learnings-path=<p>` in the request. A caller fanning
    several runs over one story gives each its own file. Relative resolves against the
    repo root, not the cwd."""
    toks = request_tokens(request)
    p = None
    for i, t in enumerate(toks):
        if t.startswith("--learnings-path=") and len(t) > len("--learnings-path="):
            p = t[len("--learnings-path="):]
            break
        if t == "--learnings-path":
            if i + 1 < len(toks) and not toks[i + 1].startswith("--"):
                p = toks[i + 1]
            break
    if not p:
        return None
    return p if p.startswith("/") else f"{root}/{p}"


# --------------------------------------------------------------------------------
# Run flags: request, then tasks/clerk.json, then tasks/.environment, then off
# --------------------------------------------------------------------------------

def truthy(v):
    """Anything unrecognised reads as false: a typo in a config file must never be what
    turns integration on."""
    return str(v).strip().lower() in ("true", "1", "yes", "on")


def request_flag(request, on, off):
    """True, False, or None when the request says nothing. Whole tokens only, and off
    wins a request that says both, since off is what a run does with nothing set."""
    toks = request_tokens(request)
    if off in toks:
        return False
    if on in toks:
        return True
    return None


def resolve_flag(root, key, request=""):
    """(value, source). The source is reported, not decoration."""
    on, off = FLAG_WORDS[key]
    if request:
        v = request_flag(request, on, off)
        if v is not None:
            return v, "request"
    cfg = _json_file(Path(root) / "tasks" / "clerk.json")
    if isinstance(cfg, dict) and key in cfg:
        raw = cfg[key]
        raw = raw if isinstance(raw, str) else json.dumps(raw)
        if raw:
            return truthy(raw), "tasks/clerk.json"
    v = env_get(Path(root) / "tasks" / ".environment", key)
    if v:
        return truthy(v), "tasks/.environment"
    return False, "default"


def resolve_flags(root, request=""):
    flags, sources = {}, {}
    for key in FLAG_KEYS:
        flags[key], sources[key] = resolve_flag(root, key, request)
    return {"flags": flags, "flag_sources": sources}


# --------------------------------------------------------------------------------
# Breakdowns: where they live, and which one a command works on
# --------------------------------------------------------------------------------

def tasks_home(cwd=None):
    """The work tree when tasks/ is tracked — the breakdown is content on the branch and
    the worktree's copy is the one that gets staged. The main repo root when tasks/ is
    excluded — a fresh worktree never materialises an untracked file."""
    root = repo_root(cwd)
    if not root:
        return None
    return root if is_ignored(root, "tasks") else work_tree(cwd)


def breakdown_paths(home, include_archived=False):
    """Every breakdown under tasks/, found rather than globbed: deliverables live one per
    directory. Archived ones only when asked, or any history makes the repo ambiguous."""
    base = Path(home) / "tasks"
    if not base.is_dir():
        return []
    out = []
    for f in sorted(p for p in base.rglob("*.md") if p.is_file()):
        if f.name == "learnings.md":
            continue
        if not include_archived and "completed" in f.relative_to(base).parts[:-1]:
            continue
        out.append(str(f))
    return out


def resolve_tasks_arg(arg, home):
    """A relative --tasks-file written the way the repo reads on disk, tried at the
    breakdown home when cwd inside a worktree is not where an excluded breakdown lives."""
    if arg.startswith("/") or Path(arg).is_file():
        return arg
    cand = Path(home) / arg if home else None
    return str(cand) if cand and cand.is_file() else arg


def find_tasks_file(home):
    """(path, rc): rc 0 with the one breakdown, 1 when there is none, 3 when several."""
    paths = breakdown_paths(home)
    if len(paths) == 1:
        return paths[0], 0
    return None, (1 if not paths else 3)


def tasks_hint(home, cmd):
    """Nothing to work from, and several to choose between, are opposite situations and
    used to share one message."""
    paths = breakdown_paths(home)
    if not paths:
        return f"{cmd}: no breakdown under {home}/tasks — decompose the story first, or name one with --tasks-file"
    listed = "\n".join(f"  {p}" for p in paths)
    return f"{cmd}: {len(paths)} breakdowns under {home}/tasks; name the one this run is building with --tasks-file:\n{listed}"


def ledger_breakdown(cwd=None):
    """The breakdown the open run bound, for a command given none that could not resolve
    one by looking. Only a file still on disk counts."""
    d = ledger_dir(cwd)
    if not d:
        return None
    bd = run_section(d, "breakdown")
    tf = (bd or {}).get("tasks_file") if isinstance(bd, dict) else None
    return tf if tf and Path(tf).is_file() else None


def breakdown_for(override, cwd=None):
    """(path, rc): --tasks-file when given, else the one breakdown under tasks/, else the
    one the ledger bound. rc 1 for none, 3 for several."""
    home = tasks_home(cwd)
    if override:
        return resolve_tasks_arg(override, home), 0
    if not home:
        return None, 1
    found, rc = find_tasks_file(home)
    if rc == 0:
        return found, 0
    lb = ledger_breakdown(cwd)
    if lb:
        return lb, 0
    return None, rc


def task_record_for(tasks_file):
    j = str(tasks_file).removesuffix(".md") + ".json"
    return j if Path(j).is_file() else None


def list_breakdowns(home):
    out = []
    for f in breakdown_paths(home):
        side = f.removesuffix(".md") + ".json"
        data = _json_file(side) if Path(side).is_file() else None
        if isinstance(data, dict):
            tasks = data.get("tasks") or []
            done = sum(1 for t in tasks if t.get("done") is True)
            out.append({"path": f, "task_record": side, "total": len(tasks), "done": done,
                        "started": done > 0, "finished": all(t.get("done") is True for t in tasks)})
        else:
            out.append({"path": f, "task_record": None, "total": None, "done": None, "started": None, "finished": None})
    return out


def commit_skill_for(wt):
    """The project's own commit skill when it defines one — usually to carry a
    convention its history depends on — else the personal one that wraps the same agent."""
    return "commit" if (Path(wt) / ".claude" / "skills" / "commit" / "SKILL.md").is_file() else "pcommit"


def worktrees(cwd=None):
    """Every worktree of this repo with the branch it has checked out; a detached one has
    no branch and is not listed."""
    out = []
    path = None
    for line in (gitout("worktree", "list", "--porcelain", cwd=cwd) or "").splitlines():
        if line.startswith("worktree "):
            path = line[len("worktree "):]
        elif line.startswith("branch "):
            out.append({"path": path, "branch": line[len("branch "):].removeprefix("refs/heads/")})
    return out


def resume_for(breakdowns, trees):
    """The part-built run to rejoin, or None: exactly one breakdown started and not
    finished, paired with the worktree whose branch is its slug."""
    live = [b for b in breakdowns if b.get("started") is True and b.get("finished") is False]
    if len(live) != 1:
        return None
    b = live[0]
    slug = Path(b["path"]).name.removesuffix(".md")
    wt = next((t for t in trees if t.get("branch") == slug), None)
    return {"breakdown": b, "slug": slug, "worktree": wt}


# --------------------------------------------------------------------------------
# prepare
# --------------------------------------------------------------------------------

def request_from_ledger(cwd=None):
    d = ledger_dir(cwd)
    if not d:
        return None
    meta = ledger_read(Path(d) / "run.json")
    return (meta or {}).get("request") or None if isinstance(meta, dict) else None


def prepare(cwd=None, request=None):
    """Every fact a run reads, as one object. The request is the top layer of the flags
    and the learnings path; once a run is open the ledger holds it verbatim, so a call
    without one reads it from there and says so in `request_source`."""
    root = repo_root(cwd)
    if not root:
        die("not a git repository")
    request_source = "argument" if request else "none"
    if not request:
        request = request_from_ledger(cwd)
        if request:
            request_source = "ledger"
    wt = work_tree(cwd)
    th = tasks_home(cwd)
    default = default_branch(cwd)
    branch = current_branch(cwd)
    base = gitout("merge-base", "HEAD", default, cwd=cwd) if default else None
    learn, learn_src = resolve_learnings_path(root), "resolved"
    if request:
        override = request_learnings_path(request, root)
        if override:
            learn, learn_src = override, "request"
    tasks, _ = find_tasks_file(th)
    trees = worktrees(cwd)
    breakdowns = list_breakdowns(th)
    ld = ledger_dir(cwd)
    head = head_sha(cwd)
    facts = {
        "version": None,
        "repo_root": root,
        "build_tree": wt,
        "in_worktree": root != wt,
        "branch": branch,
        "default_branch": default or None,
        "base": base or None,
        "code_tree": code_tree("HEAD", cwd),
        "run": Path(ld).name if ld else None,
        "runs_open": open_runs(cwd),
        "receipt": receipt_state(state_dir(cwd), head, cwd),
        "clean": tree_is_clean(cwd),
        "languages": detect_languages(root),
        "test_commands": resolve_test_commands(root),
        "go_tool_prefix": resolve_go_prefix(root),
        "learnings_path": learn,
        "learnings_path_source": learn_src,
        "request_source": request_source,
        "commit_skill": commit_skill_for(wt),
        "tasks_file": tasks,
        "tasks_home": th,
        "tasks_tracked": not is_ignored(root, "tasks"),
        "breakdowns": breakdowns,
        "worktrees": trees,
        "resume": resume_for(breakdowns, trees),
    }
    tc = facts["test_commands"]
    facts["test_command"] = tc.get("default") if isinstance(tc, dict) else None
    facts.update(resolve_flags(root, request))
    return facts
