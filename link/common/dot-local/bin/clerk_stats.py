"""Where a run's time and tokens went, read from what already exists: the ledger clerk
wrote as the run went, and the transcripts the harness wrote beside it.

The ledger alone gives every step's wall clock, each task's, each audit round's and each
audit agent's, with the dollars the harness reported for the agents. Tokens live only in
the transcripts, which are found from the session id `clerk step --start` stamps into
the run — or, for a run from before that stamp, from `shown.json`, `--session`, or a
picker over the transcripts that overlap the run.
"""

import glob
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

STEPS = ["ground", "decompose", "build", "suite", "audit", "match-request", "explain",
         "verify-run", "land", "learn"]


def parse_at(s):
    try:
        return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        pass
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None


def iso(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if dt else None


def read_jsonl(path):
    try:
        with open(path, errors="replace") as fh:
            for line in fh:
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    continue
    except OSError:
        return


def unwrap_report(obj):
    """The report inside whatever was saved. `clerk audit run` ends with a reply that
    carries the report under `report`, and a run that saves the whole reply and passes
    the file on has handed over a valid JSON document with no findings at its top level.
    Returns None when neither shape is present."""
    if not isinstance(obj, dict):
        return None
    if isinstance(obj.get("findings"), list):
        return obj
    inner = obj.get("report")
    if isinstance(inner, dict) and isinstance(inner.get("findings"), list):
        return inner
    return None


def finding_rows(rep):
    return [{"id": f.get("id"), "severity": f.get("severity"), "nature": f.get("nature"),
             "file": f.get("file"), "line": f.get("line")}
            for f in (rep.get("findings") or []) if isinstance(f, dict)]


def recover_round(r):
    """Counts for a round recorded without them, read back from the report file it named."""
    path = r.get("report")
    if r.get("findings") is not None or not path:
        return r
    try:
        rep = unwrap_report(json.loads(Path(path).read_text()))
    except (OSError, json.JSONDecodeError):
        return r
    if not rep:
        return r
    gaps = rep.get("coverage_gaps")
    return {**r, "findings": len(rep["findings"]),
            "coverage_gaps": len(gaps) if isinstance(gaps, list) else None,
            "findings_list": finding_rows(rep), "recovered_from_report": True}


# --------------------------------------------------------------------------------
# Windows: each step's span, from the stamps the run left behind
# --------------------------------------------------------------------------------

def windows(run):
    """One entry per step of the table, in order, with the span the ledger can vouch
    for. A step whose stamp is missing gets no span rather than a guessed one, and the
    step after it starts where the last known stamp left off."""
    meta = run.meta
    t0 = parse_at(meta.get("started_at"))
    tend = parse_at(meta.get("finished_at"))
    ev = [e for e in read_jsonl(run.dir / "events.jsonl") if isinstance(e, dict)]
    for e in ev:
        e["_at"] = parse_at(e.get("at"))

    def first(cmd, after=None):
        for e in ev:
            if e.get("cmd") == cmd and e.get("exit") == 0 and e["_at"] and (after is None or e["_at"] >= after):
                return e["_at"]
        return None

    finishes = {}
    for e in ev:
        if e.get("cmd") == "finish" and e.get("exit") == 0 and e.get("argv") and e["_at"]:
            finishes[str(e["argv"][0])] = e["_at"]
    breakdown = run.read("breakdown.json") or {}
    done = run.read("done.json") or {}
    aud = run.read("audit.json") or {}
    match = run.read("match-request.json") or {}
    land = run.read("land.json") or {}

    build_end = max(finishes.values()) if finishes else None
    suite_end = first("receipt", after=build_end) if build_end else None
    accepted = (aud.get("accepted") or {}).get("at")
    rounds = aud.get("rounds") or []
    audit_end = parse_at(accepted) if accepted else None
    match_end = parse_at(match.get("at"))
    explain_end = first("verify", after=match_end) if match_end else None
    verify_stamps = [parse_at((done.get(k) or {}).get("at")) for k in ("verify-residue", "verify-run")]
    verify_stamps = [v for v in verify_stamps if v]
    ends = {
        "ground": first("guidelines") or parse_at(breakdown.get("at")),
        "decompose": parse_at(breakdown.get("at")),
        "build": build_end,
        "suite": suite_end,
        "audit": audit_end,
        "match-request": match_end,
        "explain": explain_end,
        "verify-run": max(verify_stamps) if verify_stamps else None,
        "land": parse_at(land.get("at")),
        "learn": tend,
    }

    # A stamp rewritten after the run — an acceptance re-asserted, a step re-done —
    # would otherwise swallow every step after it. No step outlives the next known
    # stamp, or the run's own finish.
    ceiling = tend
    for step in reversed(STEPS):
        end = ends.get(step)
        if end and ceiling and end > ceiling:
            ends[step] = ceiling
        ceiling = min(ends[step], ceiling) if ends.get(step) and ceiling else (ends.get(step) or ceiling)

    out, cur = [], t0
    for step in STEPS:
        end = ends.get(step)
        if cur is None or end is None or end < cur:
            out.append({"step": step, "start": iso(cur), "end": None, "seconds": None})
            continue
        out.append({"step": step, "start": iso(cur), "end": iso(end),
                    "seconds": int((end - cur).total_seconds())})
        cur = end

    tasks, prev = [], ends["decompose"] or ends["ground"] or t0
    for n, at in sorted(finishes.items(), key=lambda kv: kv[1]):
        tasks.append({"task": n, "end": iso(at),
                      "seconds": int((at - prev).total_seconds()) if prev and at >= prev else None})
        prev = at

    audit_rounds, prev = [], suite_end
    for r in rounds:
        r = recover_round(r)
        at = parse_at(r.get("at"))
        agents = r.get("agents") or []
        audit_rounds.append({
            "n": r.get("n"), "at": r.get("at"),
            "seconds": int((at - prev).total_seconds()) if prev and at and at >= prev else None,
            "findings": r.get("findings"), "coverage_gaps": r.get("coverage_gaps"),
            "agents": len(agents),
            "agent_seconds": sum(a.get("seconds") or 0 for a in agents) or None,
            "cost_usd": round(sum(a.get("cost_usd") or 0 for a in agents), 4) if agents else None,
            "incidents": len(r.get("incidents") or []),
            "recovered_from_report": bool(r.get("recovered_from_report")),
            "agent_rows": agents})
        prev = at or prev

    total = int((tend - t0).total_seconds()) if t0 and tend else None
    return {"started_at": meta.get("started_at"), "finished_at": meta.get("finished_at"),
            "total_seconds": total, "steps": out, "tasks": tasks, "audit_rounds": audit_rounds,
            "incidents": aud.get("incidents") or []}


# --------------------------------------------------------------------------------
# Transcripts: tokens, found from a session id
# --------------------------------------------------------------------------------

def transcripts_dir():
    return Path(os.environ.get("CLERK_TRANSCRIPTS_DIR") or (Path.home() / ".claude" / "projects"))


def project_dir(cwd):
    """The directory the harness keeps a working directory's transcripts in: the path
    with every character outside [A-Za-z0-9] turned into a dash."""
    return transcripts_dir() / re.sub(r"[^A-Za-z0-9]", "-", str(cwd))


def find_transcript(session, cwd=None):
    if not session:
        return None
    if cwd:
        p = project_dir(cwd) / f"{session}.jsonl"
        if p.exists():
            return p
    hits = glob.glob(str(transcripts_dir() / "*" / f"{session}.jsonl"))
    return Path(hits[0]) if hits else None


def usage_of(path):
    """Each assistant turn once. The harness writes a turn's message once per streamed
    block, every copy carrying the same id and the same input usage, so summing lines
    would count a turn's input as many times as it had blocks."""
    turns, first_ts, last_ts, model = {}, None, None, None
    for d in read_jsonl(path):
        ts = d.get("timestamp")
        if ts:
            first_ts = first_ts or ts
            last_ts = ts
        if d.get("type") != "assistant":
            continue
        m = d.get("message") or {}
        u = m.get("usage") or {}
        mid = m.get("id") or d.get("uuid")
        model = m.get("model") or model
        t = turns.get(mid)
        if t is None:
            turns[mid] = {"ts": ts, "input": u.get("input_tokens") or 0,
                          "cache_read": u.get("cache_read_input_tokens") or 0,
                          "cache_creation": u.get("cache_creation_input_tokens") or 0,
                          "output": u.get("output_tokens") or 0}
        else:
            t["output"] = max(t["output"], u.get("output_tokens") or 0)
    return list(turns.values()), first_ts, last_ts, model


def _zero():
    return {"turns": 0, "input": 0, "cache_read": 0, "cache_creation": 0, "output": 0}


def _add(into, t):
    into["turns"] += 1
    for k in ("input", "cache_read", "cache_creation", "output"):
        into[k] += t[k]


def bucket(turns, steps):
    """Turns summed into the step whose span holds their timestamp; the rest, before the
    run opened or after it finished, under `outside`."""
    spans = [(s["step"], parse_at(s["start"]), parse_at(s["end"])) for s in steps if s["end"]]
    by = {s["step"]: _zero() for s in steps}
    outside, total = _zero(), _zero()
    for t in turns:
        at = parse_at(t["ts"])
        _add(total, t)
        for name, a, b in spans:
            if at and a <= at < b:
                _add(by[name], t)
                break
        else:
            _add(outside, t)
    return by, outside, total


def subagents(session, cwd, t0=None, tend=None):
    """The in-session agents a run spawned — commit writers, the verifier — each with its
    type, span and tokens. A session outlives its run, so each says whether it began
    inside the run's span."""
    root = project_dir(cwd) / session / "subagents" if cwd else None
    if not root or not root.is_dir():
        hits = glob.glob(str(transcripts_dir() / "*" / session / "subagents"))
        root = Path(hits[0]) if hits else None
    if not root:
        return []
    rows = []
    for meta in sorted(root.glob("*.meta.json")):
        jsonl = meta.with_name(meta.name[: -len(".meta.json")] + ".jsonl")
        if not jsonl.exists():
            continue
        try:
            md = json.loads(meta.read_text())
        except (OSError, json.JSONDecodeError):
            md = {}
        turns, first_ts, last_ts, model = usage_of(jsonl)
        tot = _zero()
        for t in turns:
            _add(tot, t)
        a, b = parse_at(first_ts), parse_at(last_ts)
        rows.append({"type": md.get("agentType") or "?", "description": md.get("description"),
                     "model": model, "started_at": first_ts, "ended_at": last_ts,
                     "seconds": int((b - a).total_seconds()) if a and b else None, "tokens": tot,
                     "in_run": bool(a and (t0 is None or a >= t0) and (tend is None or a <= tend))})
    rows.sort(key=lambda r: r["started_at"] or "")
    return rows


def candidates(run, cwds, limit=12):
    """Transcripts that could be the run's own session: those in the transcript folders
    of the directories the run was launched from, built in, or is being asked about
    from, whose span overlaps the run's."""
    t0 = parse_at(run.meta.get("started_at"))
    tend = parse_at(run.meta.get("finished_at")) or datetime.now(timezone.utc)
    roots = []
    for cwd in cwds:
        d = project_dir(cwd) if cwd else None
        if d and d.is_dir() and d not in roots:
            roots.append(d)
    if not t0 or not roots:
        return []
    rows = []
    for p in [p for root in roots for p in root.glob("*.jsonl")]:
        first_ts, prompt = None, None
        for d in read_jsonl(p):
            first_ts = first_ts or d.get("timestamp")
            if d.get("type") == "user" and prompt is None:
                c = (d.get("message") or {}).get("content")
                if isinstance(c, str):
                    prompt = c
                elif isinstance(c, list):
                    texts = [x.get("text") for x in c if isinstance(x, dict) and x.get("type") == "text"]
                    prompt = texts[0] if texts else None
            if first_ts and prompt is not None:
                break
        a = parse_at(first_ts)
        b = datetime.fromtimestamp(p.stat().st_mtime, tz=timezone.utc)
        if not a or b < t0 or a > tend:
            continue
        rows.append({"session": p.stem, "started_at": first_ts, "ended_at": iso(b),
                     "bytes": p.stat().st_size,
                     "prompt": re.sub(r"\s+", " ", (prompt or "").strip())[:90]})
    rows.sort(key=lambda r: r["started_at"] or "")
    return rows[:limit]


# --------------------------------------------------------------------------------
# The whole picture
# --------------------------------------------------------------------------------

def collect(run, cwd, session=None):
    w = windows(run)
    out = {"run": run.slug, "request": run.meta.get("request"), "harness": run.meta.get("harness"),
           "cwd": cwd, **w}
    sid = session or run.meta.get("session_id") or (run.read("shown.json") or {}).get("session")
    out["session"] = sid
    path = find_transcript(sid, cwd)
    out["transcript"] = str(path) if path else None
    if path:
        turns, first_ts, last_ts, model = usage_of(path)
        by, outside, total = bucket(turns, w["steps"])
        for s in out["steps"]:
            s["tokens"] = by[s["step"]]
        out["tokens"] = {"total": total, "outside_run": outside, "model": model,
                         "context_at_end": (turns[-1]["input"] + turns[-1]["cache_read"]
                                            + turns[-1]["cache_creation"]) if turns else None}
        out["subagents"] = subagents(sid, cwd, parse_at(w["started_at"]), parse_at(w["finished_at"]))
    else:
        out["tokens"] = None
        out["subagents"] = []
        out["note"] = ("no transcript: the run records no session id and none was given with --session"
                       if not sid else f"no transcript found for session {sid}")
    for r in out["audit_rounds"]:
        tok = _zero()
        found = 0
        for a in r["agent_rows"]:
            p = find_transcript(a.get("session_id"), cwd)
            if not p:
                continue
            found += 1
            for t in usage_of(p)[0]:
                _add(tok, t)
        r["tokens"] = tok if found else None
        r["agents_with_transcripts"] = found
    return out


# --------------------------------------------------------------------------------
# Choosing, for a person at a terminal
# --------------------------------------------------------------------------------

def interactive():
    v = os.environ.get("CLERK_INTERACTIVE")
    if v in ("0", "1"):
        return v == "1"
    return sys.stdin.isatty() and sys.stdout.isatty()


def fzf(lines, header, preview=None):
    """One line of `lines`, chosen in fzf, or None: fzf missing, or the choice cancelled."""
    if not lines or not shutil.which("fzf"):
        return None
    argv = ["fzf", "--no-multi", "--layout=reverse", "--header", header]
    if preview:
        argv += ["--preview", preview, "--preview-window", "right,60%,wrap"]
    try:
        r = subprocess.run(argv, input="\n".join(lines) + "\n", capture_output=True, text=True)
    except OSError:
        return None
    if r.returncode != 0:
        return None
    return r.stdout.strip().splitlines()[0] if r.stdout.strip() else None


def local(at):
    dt = parse_at(at)
    return dt.astimezone().strftime("%m-%d %H:%M") if dt else "?"


def pick_run(summaries):
    """`summaries` as run_summary() shapes them, newest first. Returns a slug or None."""
    lines = []
    for s in summaries:
        t = s.get("tasks") or {}
        prog = f"{t.get('done', 0)}/{t.get('total', 0)}" if t else "-"
        state = "done" if s.get("finished") else "open"
        req = re.sub(r"\s+", " ", (s.get("request") or "").strip())[:70]
        lines.append(f"{s['slug']:<50} {local(s.get('started_at')):<11} {state:<5} {prog:<6} {req}")
    choice = fzf(lines, "a run — Enter for its statistics, Esc to leave",
                 preview="clerk stats --run {1} --text")
    return choice.split()[0] if choice else None


def pick_session(rows):
    lines = [f"{r['session']:<38} {local(r.get('started_at')):<11} {r['bytes'] // 1024:>6}K  {r['prompt']}"
             for r in rows]
    choice = fzf(lines, "the transcript that was this run's session")
    return choice.split()[0] if choice else None


# --------------------------------------------------------------------------------
# Text
# --------------------------------------------------------------------------------

def span(seconds):
    if seconds is None:
        return "-"
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds / 60:.1f}m"
    return f"{seconds // 3600}h{(seconds % 3600) // 60:02d}m"


def tokens(n):
    if n is None:
        return "-"
    if n < 1000:
        return str(n)
    if n < 1_000_000:
        return f"{n / 1000:.0f}K"
    return f"{n / 1_000_000:.1f}M"


def render(st):
    total = st.get("total_seconds")
    lines = [f"run {st['run']}   {local(st.get('started_at'))} → "
             f"{local(st['finished_at']) if st.get('finished_at') else 'open'}   {span(total)}"]
    if st.get("session"):
        lines.append(f"session {st['session']}   transcript {'found' if st.get('transcript') else 'not found'}")
    else:
        lines.append("session not recorded — tokens unavailable (pass --session <id>)")
    has_tok = bool(st.get("tokens"))
    head = f"{'step':<16}{'wall':>8}{'share':>7}"
    if has_tok:
        head += f"{'turns':>7}{'fresh in':>10}{'cached in':>11}{'out':>8}"
    lines += ["", head]
    tasks = {t["task"]: t for t in st.get("tasks") or []}
    for s in st["steps"]:
        sec = s.get("seconds")
        share = f"{100 * sec / total:.0f}%" if sec is not None and total else "-"
        row = f"{s['step']:<16}{span(sec):>8}{share:>7}"
        if has_tok:
            t = s.get("tokens") or _zero()
            row += (f"{t['turns']:>7}{tokens(t['input'] + t['cache_creation']):>10}"
                    f"{tokens(t['cache_read']):>11}{tokens(t['output']):>8}")
        lines.append(row)
        if s["step"] == "build":
            for n, t in sorted(tasks.items(), key=lambda kv: kv[1]["end"] or ""):
                lines.append(f"  task {n:<10}{span(t['seconds']):>8}")
        if s["step"] == "audit":
            for r in st.get("audit_rounds") or []:
                cost = f"${r['cost_usd']:.2f}" if r.get("cost_usd") is not None else "$-"
                agents = (f"agents {r['agents']} · {span(r['agent_seconds'])} · {cost}"
                          if r.get("agents") else "no agent record")
                tok = f" · {tokens(sum(r['tokens'][k] for k in ('input', 'cache_read', 'cache_creation')))} in" \
                    if r.get("tokens") else ""
                lines.append(f"  round {r['n']:<9}{span(r['seconds']):>8}       "
                             f"findings {r.get('findings')}  {agents}{tok}  incidents {r['incidents']}")
    if has_tok:
        t = st["tokens"]["total"]
        lines.append(f"{'total':<16}{'':>8}{'':>7}{t['turns']:>7}{tokens(t['input'] + t['cache_creation']):>10}"
                     f"{tokens(t['cache_read']):>11}{tokens(t['output']):>8}")
        o = st["tokens"]["outside_run"]
        if o["turns"]:
            lines.append(f"  ({o['turns']} turns outside the run's span, {tokens(o['output'])} out)")
        if st["tokens"].get("context_at_end"):
            lines.append(f"  context at the last turn: {tokens(st['tokens']['context_at_end'])}")
    subs = [a for a in st.get("subagents") or [] if a.get("in_run", True)]
    later = len(st.get("subagents") or []) - len(subs)
    if subs or later:
        lines += ["", "subagents" + (f"  (+{later} after the run, not counted)" if later else "")]
        by_type = {}
        for a in subs:
            g = by_type.setdefault(a["type"], {"n": 0, "seconds": 0, "out": 0, "in": 0})
            g["n"] += 1
            g["seconds"] += a.get("seconds") or 0
            g["out"] += a["tokens"]["output"]
            g["in"] += a["tokens"]["input"] + a["tokens"]["cache_creation"] + a["tokens"]["cache_read"]
        for typ, g in by_type.items():
            lines.append(f"  {typ:<24}×{g['n']:<3} {span(g['seconds']):>8}   in {tokens(g['in'])}  out {tokens(g['out'])}")
    inc = st.get("incidents") or []
    if inc:
        lines += ["", "incidents"]
        for i in inc:
            extra = " ".join(f"{k} {v}" for k, v in i.items()
                             if k not in ("at", "kind", "round", "phase") and not isinstance(v, (list, dict)))
            kept = f"kept {len(i['kept'])} lost {len(i['lost'])}" if "kept" in i else ""
            lines.append(f"  {local(i.get('at'))}  round {i.get('round')}  {i.get('kind'):<14} {i.get('phase') or '':<10} {extra} {kept}".rstrip())
    if st.get("note"):
        lines += ["", st["note"]]
    return "\n".join(lines)
