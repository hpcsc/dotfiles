"""What every clerk-* plugin does the same way: say who failed, answer in JSON, ask git
and clerk, find a breakdown the way the core does.

Imported by path, not installed: each plugin adds its own directory to sys.path before
`import clerk_lib`, and Path(__file__).resolve() follows the ~/.local/bin symlink back to
this directory, so the import works stowed or not. A plugin is still one executable;
what it stopped being is the only copy of these.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLERK = HERE / "clerk"

# `clerk-lint` → "lint"; clerk-audit, a symlink to clerk-step, answers as "audit". The
# prefix is the core's own: `clerk: <cmd>: <msg>`.
NAME = Path(sys.argv[0]).name
if NAME.startswith("clerk-"):
    NAME = NAME[len("clerk-"):]


def die(msg, code=2):
    print(f"clerk: {NAME}: {msg}", file=sys.stderr)
    sys.exit(code)


def emit(obj, code=0):
    print(json.dumps(obj, indent=2))
    sys.exit(code)


class Parser(argparse.ArgumentParser):
    """argparse, speaking as `clerk <name>`. Its own errors go through die(), so an
    unknown flag is refused the way every other plugin error is: on stderr, exit 2,
    naming the command rather than the file."""

    def __init__(self, **kw):
        kw.setdefault("prog", f"clerk {NAME}")
        kw.setdefault("add_help", False)
        super().__init__(**kw)
        self.add_argument("-h", "--help", action="store_true")

    def error(self, message):
        die(message)


def git(*args, cwd=None):
    """The CompletedProcess, for callers that read the exit code and the output both."""
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)


def gitout(*args, cwd=None):
    """stdout stripped, or None when git said no."""
    r = git(*args, cwd=cwd)
    return r.stdout.strip() if r.returncode == 0 else None


def git_ok(*args, cwd=None):
    return git(*args, cwd=cwd).returncode == 0


def clerk(*args, cwd=None, env=None):
    """Run a core command and parse its JSON: (exit code, parsed or None, stderr). Beside
    this file first, then PATH, so a checkout that is not stowed still finds itself."""
    exe = str(CLERK) if CLERK.exists() else "clerk"
    try:
        r = subprocess.run([exe, *args], cwd=cwd, capture_output=True, text=True, env=env)
    except OSError as e:
        return 1, None, str(e)
    data = None
    if r.stdout.strip():
        try:
            data = json.loads(r.stdout)
        except json.JSONDecodeError:
            data = None
    return r.returncode, data, r.stderr.strip()


def facts(*args, cwd=None):
    """`clerk prepare`, which already resolves the facts with precedence rules subtle
    enough to get wrong twice — where the breakdown lives when tasks/ is excluded, which
    branch is default, where the work tree is. A failure passes prepare's own reason
    through: "clerk prepare failed" sent the reader looking at the wrong command when
    what it actually said was "not a git repository"."""
    rc, data, err = clerk("prepare", *args, cwd=cwd)
    if rc != 0 or data is None:
        die(err or f"clerk prepare exited {rc} with no output", rc if rc not in (0, 1) else 2)
    return data


def resolve_tasks_arg(arg, tasks_home):
    """A relative path is written the way the repo reads on disk, but cwd inside a
    worktree is not where an excluded breakdown lives. Try the breakdown home before
    handing the path back as given. The core's resolve_tasks_arg, for plugins."""
    p = Path(arg)
    if p.is_absolute() or p.exists():
        return p
    candidate = Path(tasks_home) / arg
    return candidate if candidate.exists() else p


def worktree_for(branch, worktrees):
    """The path of the worktree holding `branch`, from prepare's `worktrees` list."""
    for wt in worktrees or []:
        if wt.get("branch") == branch:
            return wt.get("path")
    return None
