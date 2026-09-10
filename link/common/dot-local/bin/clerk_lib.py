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
VERSION = "0.5.0"

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


def usage_if_asked(argv, doc, usage=None):
    """Print what the command is and how it is called, then exit, for `-h`/`--help` before
    any parse. `clerk land` had none: a run asked for it, got `unknown argument`, and spent
    two more round trips reading the dispatcher's list instead. The usage is the indented
    block of the module docstring unless one is passed."""
    if not any(a in ("-h", "--help") for a in argv):
        return
    lines = (doc or "").strip().splitlines()
    print(lines[0] if lines else f"clerk {NAME}")
    block = usage or "\n".join(x for x in lines[1:] if x.startswith("    ")).strip("\n")
    if block:
        print("\nUSAGE\n" + block)
    sys.exit(0)


def git(*args, cwd=None):
    """The CompletedProcess, for callers that read the exit code and the output both."""
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)


def gitout(*args, cwd=None):
    """stdout stripped, or None when git said no."""
    r = git(*args, cwd=cwd)
    return r.stdout.strip() if r.returncode == 0 else None


def git_ok(*args, cwd=None):
    return git(*args, cwd=cwd).returncode == 0


def plugin_bin(name):
    """The executable behind `clerk <name>`: clerk-<name> on PATH, else beside this file.
    One resolution for every caller, so a plugin not yet linked into ~/.local/bin is
    found the same way by every command that needs it."""
    import shutil
    found = shutil.which(f"clerk-{name}")
    if found:
        return found
    cand = HERE / f"clerk-{name}"
    return str(cand) if cand.is_file() and cand.stat().st_mode & 0o111 else None


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


def facts(cwd=None, request=None):
    """`clerk prepare`'s facts, resolved in-process. The precedence rules behind them are
    subtle enough to get wrong twice: where the breakdown lives when tasks/ is excluded,
    which branch is default, where the work tree is. clerk_repo decides each once, and
    this reads the answer.

    Ask for this when a caller wants the request applied on top, which is what makes the
    flags and the learnings path what they are. A caller that wants one plain fact about
    the checkout asks `repo()` instead, and pays for that fact alone."""
    from clerk_repo import prepare  # clerk_repo imports this module, so the import waits
    return prepare(cwd, request)


def repo(cwd=None):
    """The checkout, for a caller that wants a fact or two rather than all of them.

    `facts()` resolves every fact a run reads, which is twelve git subprocesses and a
    quarter of a second. Most callers here want one: the work tree, the default branch,
    where the ledger is. They ask this and pay for what they ask.

    The instance answers for the checkout as it stood when it was made. Do not keep one
    across a commit, a switch or a rebase."""
    from clerk_repo import Repo  # clerk_repo imports this module, so the import waits
    return Repo(cwd)


def worktree_for(branch, worktrees):
    """The path of the worktree holding `branch`, from prepare's `worktrees` list."""
    for wt in worktrees or []:
        if wt.get("branch") == branch:
            return wt.get("path")
    return None


def take_verb(argv, verbs, spec=None):
    """(verb, argv-without-it). An operation is a verb, the way `clerk audit round` and
    `clerk step done` spell theirs; flags are for what modifies one. The verb may sit
    either side of a modifier, because which order a caller has to remember is one more
    rule than a command needs — so a token is only the verb when it is not the value of a
    flag that takes one. Returns (None, argv) when no verb is present, and dies naming
    them when the leading token is a word that is not one."""
    takes_value = {k for k, v in (spec or {}).items() if v in ("value", "list")}
    for i, a in enumerate(argv):
        if a in verbs and not (i and argv[i - 1] in takes_value):
            return a, list(argv[:i]) + list(argv[i + 1:])
    for i, a in enumerate(argv):
        if not a.startswith("-") and not (i and argv[i - 1] in takes_value):
            die(f"unknown verb '{a}' — expected one of {', '.join(verbs)}")
    return None, list(argv)


def parse(argv, spec):
    """Tiny flag parser: spec maps --flag to 'bool' | 'value' | 'list'. Returns the
    options and the positional rest; an unknown --flag dies as `clerk <name>`."""
    opts = {k: ([] if t == "list" else (False if t == "bool" else None)) for k, t in spec.items()}
    rest = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and "=" in a and a.split("=", 1)[0] in spec and spec[a.split("=", 1)[0]] != "bool":
            # --flag=value, the spelling every other clerk command takes as well.
            a, v = a.split("=", 1)
            argv = argv[:i] + [a, v] + argv[i + 1:]
        if a in spec:
            t = spec[a]
            if t == "bool":
                opts[a] = True
                i += 1
            else:
                if i + 1 >= len(argv):
                    die(f"{a} needs a value")
                if t == "list":
                    opts[a].append(argv[i + 1])
                else:
                    opts[a] = argv[i + 1]
                i += 2
        elif a.startswith("--") and a not in spec:
            die(f"unknown argument '{a}'")
        else:
            rest.append(a)
            i += 1
    return opts, rest
