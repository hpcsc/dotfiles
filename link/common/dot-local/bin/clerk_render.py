"""Showing a program-driven run as it happens.

`clerk run` walks a story and `clerk audit run` walks a round, and both spend most of
their wall clock inside a headless agent. Without this they are a wait with a number at
the end, which is the one thing a session gives for free and a program does not.

The event vocabulary is `clerk_harness._reduce`'s — a tool call, a line of text, the
turn's result — so this file and that function have to agree, and they live one import
apart for that reason.
"""

import hashlib
import json
import os
import sys
import threading
import time
from dataclasses import asdict, dataclass
from pathlib import Path

from clerk_lib import emit


@dataclass
class Progress:
    """One thing that happened in a run, as the thing itself rather than as the line
    drawn for it.

    There are three readers of a run's progress and they used to share only the text: the
    person watching, the status line, and `clerk watch`. The last two recovered what they
    needed by matching against the drawn line — the status line regexed a dollar amount
    out of a figure that had already been rounded to the cent, so a turn under a cent
    added nothing to it while the ledger counted it, and an error message containing a `$`
    was read as a cost. `clerk watch` reproduced the whole grammar in another file, where
    a changed prefix here would have cost it a screen and no test would have said so.

    So the numbers travel as numbers. `text` stays whatever the caller wants drawn, since
    what reads well differs between a story's turn and one lens of a round; everything a
    reader has to compute from is beside it."""

    kind: str                # step | note | started | activity | result | reply
    text: str = ""
    row: str = None          # which agent or row it is about, where there is one
    ok: bool = None          # a result's verdict
    seconds: int = None
    cost_usd: float = None


# Where a run in flight announces itself. A fixed path rather than the run's ledger,
# because the one reader that matters — the status line — is re-rendered on every
# keystroke and cannot afford the `git rev-parse` that finding a ledger costs.
def active_dir():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return Path(base) / "clerk" / "active"


STALE_AFTER = 3600

# Out of the f-string that uses them: an escape inside one is a backslash, which the
# Python a test runs clerk under refuses to parse.
OK, BAD = "\u2713", "\u2717"


class Out:
    """default — a line per tool call, the step, its result and its cost
       quiet   — steps and results only, for a cron entry with a log to write
       raw     — the harness's own JSONL on stdout, summary last, for piping onward

    Per-tool lines need the event stream reduced, which is done for Claude Code's shapes
    only. Under a harness whose events are not reduced, `raw` still carries every line and
    the other two levels fall back to steps and results — fewer lines, not wrong ones."""

    def __init__(self, level, log_path=None, beat=None):
        self.level = level
        self.lock = threading.Lock()
        # (where it builds, what it is called) for a run that wants to be visible while
        # it runs. Presence is the whole signal: the file is removed when the run ends.
        self.beat = beat
        self.beat_file = None
        self._label, self._done, self._cost = "", 0, 0.0
        if beat:
            key = hashlib.sha1(str(beat["dir"]).encode()).hexdigest()[:12]
            try:
                active_dir().mkdir(parents=True, exist_ok=True)
                self._sweep()
                self.beat_file = active_dir() / f"{beat['slug']}-{key}"
            except OSError:
                self.beat_file = None
        self.log_path = str(log_path) if log_path else None
        self.log = None
        self.records = None
        self.gone = False
        if log_path:
            # Full detail whatever the terminal is set to: a cron entry wants a quiet
            # console and a complete file, and the file is the only way to watch a
            # twenty-minute round that was launched into the background.
            #
            # The same progress lands as data in a .jsonl beside it — beside rather than
            # instead, because the log is what a person tails and `clerk watch` is the
            # one reader that needs the parts.
            try:
                Path(log_path).parent.mkdir(parents=True, exist_ok=True)
                self.log = open(log_path, "w", buffering=1)
                self.records = open(Path(log_path).with_suffix(".jsonl"), "w", buffering=1)
            except OSError:
                self.log, self.log_path, self.records = None, None, None

    def _sweep(self):
        """A run killed outright cannot remove its own file, so the next one to start
        clears what is plainly finished. The reader stays a `read` and a glob."""
        now = time.time()
        for f in active_dir().glob("*"):
            try:
                if now - f.stat().st_mtime > STALE_AFTER:
                    f.unlink()
            except OSError:
                pass

    def _pulse(self, p):
        """What a glance is owed: what it is doing now, how much has landed, what it has
        cost. Read off the record, so neither runner has to report its progress twice and
        the total is the one the run is actually spending rather than the sum of what the
        console happened to round to."""
        if not self.beat_file:
            return
        if p.kind == "step":
            self._label = p.text.split(" · ")[0][:40]
        elif p.kind == "result":
            self._done += 1
            self._cost += p.cost_usd or 0.0
        else:
            return
        try:
            self.beat_file.write_text(
                "\x1f".join([str(self.beat["dir"]), self.beat["slug"], self._label,
                             str(self._done), f"{self._cost:.2f}", str(int(time.time()))]) + "\n")
        except OSError:
            pass

    def _console(self, text, stream):
        """A reader that has gone away must not end the run. `clerk audit run … | head`
        closes the pipe the moment head has its lines, and the next progress write then
        raises BrokenPipeError out of whatever thread wrote it — which killed three
        rounds mid-review, each one leaving its agents running and its report unwritten.
        The round's evidence goes to the ledger and the log file, so a console nobody is
        reading is the one output that can be dropped."""
        if self.gone:
            return
        try:
            print(text, file=stream, flush=True)
        except (BrokenPipeError, ValueError):
            self.gone = True

    def _write(self, text, to_stderr):
        with self.lock:
            if to_stderr:
                self._console(text, sys.stderr)
            if self.log:
                self.log.write(text + "\n")

    @property
    def wants_events(self):
        """Whether a turn is worth streaming. A quiet terminal still wants them when a
        log is being written — quiet console, complete file is the point of the log."""
        return self.level != "quiet" or self.log is not None

    def opening(self):
        """Where to watch, said before anything happens, so it can be tailed from the
        moment the command is launched rather than found afterwards in a transcript."""
        if self.log_path and self.level != "raw":
            self._console(f"progress: {self.log_path}", sys.stderr)
            self._console(f"watch: clerk watch {self.log_path}", sys.stderr)

    def _emit_raw(self, obj):
        self._console(json.dumps(obj, separators=(",", ":")), sys.stdout)

    def step(self, text):
        self._say(Progress("step", text), text)

    def result(self, detail="", *, row=None, ok=True, seconds=None, cost_usd=None):
        """A row that landed. `detail` is what the caller wants said about it \u2014 a story's
        turn and one lens of a round say different things \u2014 and the rest is what the
        status line and `clerk watch` would otherwise read back out of the drawn line."""
        head = f"{row:<20} " if row else ""
        self._say(Progress("result", detail, row=row, ok=ok, seconds=seconds, cost_usd=cost_usd),
                  f"  {OK if ok else BAD} {head}{detail}")

    def started(self, row):
        self._say(Progress("started", row=row), f"  \u00b7 {row} started")

    def note(self, text):
        self._say(Progress("note", text), f"  \u00b7 {text}")

    def reply(self, text):
        self._say(Progress("reply", text), f"    {text}")

    def _say(self, p, line):
        self._pulse(p)
        self._record(p)
        if self.level == "raw":
            # A mechanical step spawns nothing, so without this the JSONL would have gaps
            # exactly where clerk did the work itself.
            self._emit_raw({"kind": p.kind, "text": line})
            if self.log:
                self._write(line, to_stderr=False)
            return
        self._write(line, to_stderr=not (self.level == "quiet" and p.kind not in ("step", "result")))

    def _record(self, p):
        if not self.records:
            return
        try:
            with self.lock:
                self.records.write(json.dumps({k: v for k, v in asdict(p).items() if v is not None},
                                              separators=(",", ":")) + "\n")
        except (OSError, ValueError):
            self.records = None

    def event(self, e, label=None):
        """One thing an agent did. `label` names which agent, for a phase running
        several at once; a run walking one step at a time passes none."""
        if self.level == "raw":
            if e.get("kind") == "raw":
                self._console(e["line"], sys.stdout)
            return
        if e.get("kind") != "tool":
            return
        what = describe(e.get("name"), e.get("input"))
        self._record(Progress("activity", what, row=label))
        who = f"{label:<18} " if label else ""
        self._write(f"   \u22ef {who}{what}", to_stderr=self.level != "quiet")

    def final(self, obj, code=0):
        if self.beat_file:
            try:
                self.beat_file.unlink()
            except OSError:
                pass
        if self.log:
            self.log.write(json.dumps(obj, indent=2) + "\n")
            self.log.close()
        if self.records:
            self.records.write(json.dumps({"kind": "summary", **obj}, separators=(",", ":")) + "\n")
            self.records.close()
        if self.log_path:
            obj = {**obj, "progress": self.log_path}
        if self.level == "raw":
            self._emit_raw({"kind": "summary", **obj})
            sys.exit(code)
        try:
            emit(obj, code)
        except BrokenPipeError:
            # The summary had nowhere to go, but the round's own record already landed
            # in the ledger; exiting on its result is what the caller reads.
            sys.exit(code)


def _short(path):
    try:
        rel = os.path.relpath(str(path), os.getcwd())
    except ValueError:
        return str(path)
    return rel if not rel.startswith("../..") else str(path)


def _oneline(text, width=68):
    line = " ".join(str(text).split())
    return line if len(line) <= width else line[:width - 1] + "\u2026"


def describe(name, inp):
    """One tool call in one line. What identifies a call differs by tool — a path, a
    command, a pattern — so the first field that says which call this was, wins."""
    name = name or "?"
    if not isinstance(inp, dict):
        return name
    path = next((inp[k] for k in ("file_path", "path", "notebook_path") if inp.get(k)), None)
    if path:
        size = ""
        if "old_string" in inp or "new_string" in inp:
            size = (f"  (+{len((inp.get('new_string') or '').splitlines())}"
                    f" \u2212{len((inp.get('old_string') or '').splitlines())})")
        elif "content" in inp:
            size = f"  (+{len((inp.get('content') or '').splitlines())})"
        return f"{name:<6} {_short(path)}{size}"
    for key in ("command", "pattern", "query", "description", "prompt", "skill"):
        if inp.get(key):
            return f"{name:<6} {_oneline(inp[key])}"
    return name
