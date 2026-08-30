"""Showing a program-driven run as it happens.

`clerk run` walks a story and `clerk audit run` walks a round, and both spend most of
their wall clock inside a headless agent. Without this they are a wait with a number at
the end, which is the one thing a session gives for free and a program does not.

The event vocabulary is `clerk_harness._reduce`'s — a tool call, a line of text, the
turn's result — so this file and that function have to agree, and they live one import
apart for that reason.
"""

import json
import os
import sys
import threading
from pathlib import Path

from clerk_lib import emit


class Out:
    """default — a line per tool call, the step, its result and its cost
       quiet   — steps and results only, for a cron entry with a log to write
       raw     — the harness's own JSONL on stdout, summary last, for piping onward

    Per-tool lines need the event stream reduced, which is done for Claude Code's shapes
    only. Under a harness whose events are not reduced, `raw` still carries every line and
    the other two levels fall back to steps and results — fewer lines, not wrong ones."""

    def __init__(self, level, log_path=None):
        self.level = level
        self.lock = threading.Lock()
        self.log_path = str(log_path) if log_path else None
        self.log = None
        if log_path:
            # Full detail whatever the terminal is set to: a cron entry wants a quiet
            # console and a complete file, and the file is the only way to watch a
            # twenty-minute round that was launched into the background.
            try:
                Path(log_path).parent.mkdir(parents=True, exist_ok=True)
                self.log = open(log_path, "w", buffering=1)
            except OSError:
                self.log, self.log_path = None, None

    def _write(self, text, to_stderr):
        with self.lock:
            if to_stderr:
                print(text, file=sys.stderr, flush=True)
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
            print(f"progress: {self.log_path}", file=sys.stderr, flush=True)

    def _emit_raw(self, obj):
        print(json.dumps(obj, separators=(",", ":")), flush=True)

    def step(self, text):
        self._say(text, "step")

    def result(self, text):
        self._say(text, "result")

    def note(self, text):
        self._say(text, "note")

    def reply(self, text):
        self._say(text, "reply")

    def _say(self, text, kind):
        if self.level == "raw":
            # A mechanical step spawns nothing, so without this the JSONL would have gaps
            # exactly where clerk did the work itself.
            self._emit_raw({"kind": kind, "text": text})
            if self.log:
                self._write(text, to_stderr=False)
            return
        self._write(text, to_stderr=not (self.level == "quiet" and kind not in ("step", "result")))

    def event(self, e, label=None):
        """One thing an agent did. `label` names which agent, for a phase running
        several at once; a run walking one step at a time passes none."""
        if self.level == "raw":
            if e.get("kind") == "raw":
                print(e["line"], flush=True)
            return
        if e.get("kind") != "tool":
            return
        who = f"{label:<18} " if label else ""
        self._write(f"   \u22ef {who}{describe(e.get('name'), e.get('input'))}",
                    to_stderr=self.level != "quiet")

    def final(self, obj, code=0):
        if self.log:
            self.log.write(json.dumps(obj, indent=2) + "\n")
            self.log.close()
        if self.log_path:
            obj = {**obj, "progress": self.log_path}
        if self.level == "raw":
            self._emit_raw({"kind": "summary", **obj})
            sys.exit(code)
        emit(obj, code)


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
