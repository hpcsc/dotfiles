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

from clerk_lib import emit


class Out:
    """default — a line per tool call, the step, its result and its cost
       quiet   — steps and results only, for a cron entry with a log to write
       raw     — the harness's own JSONL on stdout, summary last, for piping onward

    Per-tool lines need the event stream reduced, which is done for Claude Code's shapes
    only. Under a harness whose events are not reduced, `raw` still carries every line and
    the other two levels fall back to steps and results — fewer lines, not wrong ones."""

    def __init__(self, level):
        self.level = level

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
            return
        if self.level == "quiet" and kind not in ("step", "result"):
            return
        print(text, file=sys.stderr, flush=True)

    def event(self, e, label=None):
        """One thing an agent did. `label` names which agent, for a phase running
        several at once; a run walking one step at a time passes none."""
        if self.level == "raw":
            if e.get("kind") == "raw":
                print(e["line"], flush=True)
            return
        if self.level == "quiet" or e.get("kind") != "tool":
            return
        who = f"{label:<18} " if label else ""
        print(f"   \u22ef {who}{describe(e.get('name'), e.get('input'))}",
              file=sys.stderr, flush=True)

    def final(self, obj, code=0):
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
