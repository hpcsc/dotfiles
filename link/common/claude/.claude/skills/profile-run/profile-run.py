#!/usr/bin/env python3
"""Measure where an agentic run's wall-clock actually went.

Reads a run's transcript directory and reports, per agent type, how long each
agent took and what it spent that time on. Durations come from file mtimes:
the .meta.json is written when an agent starts and its .jsonl keeps growing
until it returns, so their difference is that agent's wall time. The journal
carries no timestamps, which is why mtimes are the clock here.

  profile-run.py [transcript_dir] [--top N] [--type AGENT] [--list]

With no directory it profiles the most recently modified workflow run under
~/.claude/projects.
"""

import argparse
import collections
import glob
import json
import os
import re
import sys


def newest_run():
    runs = glob.glob(os.path.expanduser("~/.claude/projects/*/*/subagents/workflows/wf_*"))
    return max(runs, key=os.path.getmtime) if runs else None


def agents(d):
    """(agent_type, seconds, jsonl_path) per agent, skipping ones still running."""
    out = []
    for meta in glob.glob(os.path.join(d, "*.meta.json")):
        jsonl = meta[: -len(".meta.json")] + ".jsonl"
        if not os.path.exists(jsonl):
            continue
        try:
            t = json.load(open(meta)).get("agentType", "?")
        except (json.JSONDecodeError, OSError):
            t = "?"
        out.append((t, os.path.getmtime(jsonl) - os.path.getmtime(meta), jsonl))
    return out


def transcript_stats(path):
    """Turn count, tool mix and shell commands from one agent transcript."""
    turns, tools, cmds, size = 0, collections.Counter(), [], os.path.getsize(path)
    for line in open(path, errors="replace"):
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        msg = d.get("message")
        if not isinstance(msg, dict):
            continue
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        if msg.get("role") == "assistant":
            turns += 1
        for c in content:
            if isinstance(c, dict) and c.get("type") == "tool_use":
                tools[c.get("name", "?")] += 1
                if c.get("name") == "Bash":
                    cmds.append((c.get("input") or {}).get("command", ""))
    return turns, tools, cmds, size


# Buckets answer one question: is the stage waiting on commands, or on the model?
BUCKETS = [
    ("run tests", r"\b(pytest|jest|vitest|mix test|cargo test|go test|npm t(est)?\b|task test|make test)"),
    ("build/lint/fmt", r"\b(go (build|vet)|gofmt|tsc\b|cargo (build|clippy)|mix compile|ruff|eslint|golangci)"),
    ("read/search code", r"\b(rg|grep|sed -n|awk|cat|head|tail|wc|ls|fd|find)\b"),
    ("git", r"\bgit\b"),
]


def bucket(cmd):
    for name, pattern in BUCKETS:
        if re.search(pattern, cmd):
            return name
    return "other"


def invocation(cmd):
    """The line that actually runs something, not the shell scaffolding around it.

    A multi-line recipe often opens with `set -e` or a variable assignment, so
    truncating the whole command would name the scaffolding rather than the
    command whose cost is being asked about.
    """
    for line in cmd.splitlines():
        for name, pattern in BUCKETS[:2]:
            m = re.search(pattern, line)
            # Slice from the match, not from the start of the line: the runner is
            # often preceded by a cd, an env var, or a `set -o pipefail`.
            if m:
                return re.sub(r"\s+", " ", line[m.start():].strip())[:76]
    return None


def main():
    p = argparse.ArgumentParser(
        description="Profile a finished agentic run: where its wall-clock went, per stage.",
        epilog="With no directory, profiles the most recently modified workflow run.",
    )
    p.add_argument("transcript_dir", nargs="?", help="a wf_* run directory (default: newest)")
    p.add_argument("--top", type=int, default=2, metavar="N", help="drill into the N slowest agents (default: 2, 0 for none)")
    p.add_argument("--type", metavar="AGENT", help="drill into this agent type only, e.g. go-implementer")
    p.add_argument("--list", action="store_true", help="list available runs and exit")
    opts = p.parse_args()

    if opts.list:
        for r in sorted(glob.glob(os.path.expanduser("~/.claude/projects/*/*/subagents/workflows/wf_*")), key=os.path.getmtime):
            print(f"{os.path.basename(r)}  {len(glob.glob(os.path.join(r, '*.meta.json'))):>3} agents  {r}")
        return

    d = opts.transcript_dir or newest_run()
    if not d or not os.path.isdir(d):
        sys.exit("no transcript directory found — pass one explicitly, or --list to see them")

    rows = agents(d)
    if not rows:
        sys.exit(f"no finished agents in {d}")

    by = collections.defaultdict(list)
    for t, secs, path in rows:
        by[t].append((secs, path))

    agent_minutes = sum(s for t, s, _ in rows) / 60
    wall = (max(os.path.getmtime(p) for _, _, p in rows) - min(os.path.getmtime(m) for m in glob.glob(os.path.join(d, "*.meta.json")))) / 60
    ranked = sorted(by.items(), key=lambda kv: -sum(s for s, _ in kv[1]))
    widest = max(sum(s for s, _ in v) for _, v in ranked)

    print("WHERE THE TIME WENT")
    print(f"  {len(rows)} agents · {agent_minutes:.0f} agent-minutes over {wall:.0f} minutes wall-clock\n")
    for t, v in ranked:
        ds = sorted(s for s, _ in v)
        total = sum(ds) / 60
        bar = "█" * max(1, round(sum(ds) / widest * 24))
        print(f"  {t:26} {bar:<24} {total:>6.1f}m {total/agent_minutes*100:>3.0f}%   "
              f"{len(ds)} run{'s' if len(ds) > 1 else ''} · median {ds[len(ds)//2]/60:.1f}m · slowest {ds[-1]/60:.1f}m")

    # Agent-minutes far above wall-clock means real overlap; near it means the stages
    # ran one after another, so only the slowest single agent is worth optimising.
    overlap = agent_minutes / wall if wall else 0
    shape = ("essentially serial — the slowest single agent sets the pace" if overlap < 1.5
             else f"{overlap:.1f}x overlap — stages genuinely run in parallel")
    print(f"\n  Concurrency: {shape}")

    target, top = opts.type, opts.top
    pool = [r for r in rows if r[0] == target] if target else rows
    for t, secs, path in sorted(pool, key=lambda r: -r[1])[:top]:
        turns, tools, cmds, size = transcript_stats(path)
        per_turn = secs / turns if turns else 0
        print(f"\n\nSLOWEST {t if target else 'STEP: ' + t} — {secs/60:.1f} minutes")
        print(f"  {turns} model turns at ~{per_turn:.0f}s each · transcript grew to {size/1024:.0f}KB")
        print(f"  {sum(tools.values())} tool calls: " + ", ".join(f"{k} {v}" for k, v in tools.most_common(5)))
        if not cmds:
            continue
        b = collections.Counter(bucket(c) for c in cmds)
        print(f"\n  What its {len(cmds)} shell calls did:")
        for k, v in b.most_common():
            print(f"    {k:20} {v:>4}  {v*100//len(cmds):>3}%  {'▏' * max(1, v*20//len(cmds))}")

        # Name the operations concretely: the human can time these to settle whether
        # the stage is waiting on commands or on the model.
        heavy = collections.Counter(
            filter(None, (invocation(c) for c in cmds if bucket(c) in ("run tests", "build/lint/fmt")))
        )
        if heavy:
            print("\n  Operations worth timing by hand (is the stage compute-bound?):")
            for cmd, n in heavy.most_common(4):
                print(f"    {n:>3}x  {cmd}")
        print(f"\n  READ THIS AS: {turns} turns × ~{per_turn:.0f}s is {turns*per_turn/60:.0f}m of the {secs/60:.1f}m.")
        print("    If the commands above run in seconds, the stage is round-trip-bound —")
        print("    fewer, wider tool calls will help; faster commands will not.")


if __name__ == "__main__":
    main()
