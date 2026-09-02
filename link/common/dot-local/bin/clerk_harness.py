"""Spawning a coding harness from a program rather than from a model.

Two commands drive a model without one driving them — `clerk audit run` walks the audit's
phases, `clerk run` walks the step table — and both need the same thing: start `claude -p`
or `opencode run`, hand it a prompt, and read what comes back. That difference is the
whole of what the two harnesses cost this design, and it is deliberately small: the
invocation constants, `_argv` and `_envelope` below are the entire per-harness surface.
Everything above them — which agent to spawn, when, with what, and what to do with the
reply — is harness-agnostic.

Two things a harness does for an in-session subagent and does NOT do here, so they are
done here instead: a schema is not enforced, so a reply is parsed and validated and the
agent is asked again with the error when it does not fit; and no worktree is provided,
so one is made for any job whose claim can only be settled by mutating a checkout.
"""

import json
import os
import shutil
import subprocess
import tempfile
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed

# Claude Code resolves user-defined agents only in a full session: `--bare` skips the
# discovery that finds them and leaves the five built-ins, so every lens would fail to
# resolve. The speed it buys is not worth a panel that silently cannot run.
CLAUDE = ["claude", "-p"]
OPENCODE = ["opencode", "run"]

DEFAULT_PERMISSION_MODE = "acceptEdits"

# Claude Code takes a session id the caller chose; opencode names its own and hands it
# back, so the first turn of a conversation there cannot be told what to call it.
NAMES_OWN_SESSIONS = {"opencode"}
# Whose event stream this module knows how to reduce into tool calls and text. opencode's
# `--format json` is an event stream too, but its shape is documented rather than
# exercised here, so its lines pass through raw and its reply is read from the envelope.
REDUCIBLE = {"claude"}


def names_own_sessions(harness):
    return harness in NAMES_OWN_SESSIONS


def reducible(harness):
    return harness in REDUCIBLE

# What the machine can actually run at once. A literal count is wrong in both directions
# — too many on a laptop, far too few on a build box — so it is derived the way Claude
# Code's own workflow engine derives it, leaving two cores for everything else.
DEFAULT_WORKERS = max(1, min(16, (os.cpu_count() or 4) - 2))

MAX_ATTEMPTS = 3
# A lens reads a whole diff and may run a suite; a scope pass is seconds. The ceiling is
# a runaway guard, not a schedule.
TIMEOUT_S = int(os.environ.get("CLERK_AGENT_TIMEOUT", "1800"))


_running = set()
_running_lock = threading.Lock()
STOPPING = False


def _track(proc):
    with _running_lock:
        _running.add(proc)


def _untrack(proc):
    with _running_lock:
        _running.discard(proc)


def stop_all():
    """Ends every agent this process started and refuses to start another. A runner
    going down would otherwise leave them spending against a ledger nobody is left to
    write, and `run_job` would retry the one it just killed."""
    global STOPPING
    STOPPING = True
    with _running_lock:
        procs = list(_running)
    for p in procs:
        try:
            p.terminate()
        except OSError:
            pass


def new_session_id():
    """Claude Code takes a session id only as a UUID; opencode names its own and hands it
    back. Minted here so a caller that wants several turns in one session can decide the
    id before the first of them runs."""
    return str(uuid.uuid4())


def harness_cmd():
    """Which harness binary this machine has, or None. Not which method text a run
    renders — that is the ledger's `harness`, and `clerk step` decides it."""
    if os.environ.get("CLERK_HARNESS_CMD"):
        return os.environ["CLERK_HARNESS_CMD"]
    if shutil.which("claude"):
        return "claude"
    if shutil.which("opencode"):
        return "opencode"
    return None


def _argv(harness, job, model=None, *, session=None, resume=False, stream=False):
    """The one function that knows what a harness is called and what its flags are.

    `job` may carry `agent`, `allowed_tools` and `permission_mode`; `session` continues a
    conversation, with `resume` saying whether that id already exists. Claude scopes tools
    per invocation and opencode does not — there it is configuration, written by the
    caller and pointed at through the environment — so `allowed_tools` reaches only one of
    the two branches. Everything else maps across.
    """
    if harness == "opencode":
        av = list(OPENCODE)
        av += ["--format", "json"]
        if job.get("agent"):
            av += ["--agent", job["agent"]]
        if model:
            av += ["--model", model]
        if session and resume:
            # `--session` continues a session opencode already named. There is no
            # create-with-this-id, so the first turn passes nothing and the id comes back
            # in the reply. Not `--fork`: forking would keep each task separately
            # inspectable at the cost of the shared context that is the point.
            av += ["--session", session]
        if (job.get("permission_mode") or DEFAULT_PERMISSION_MODE) != "manual":
            av += ["--auto"]
        return av
    av = list(CLAUDE)
    av += ["--output-format", "stream-json", "--verbose"] if stream else ["--output-format", "json"]
    av += ["--permission-mode", job.get("permission_mode") or DEFAULT_PERMISSION_MODE]
    if job.get("agent"):
        av += ["--agent", job["agent"]]
    if model:
        av += ["--model", model]
    if session:
        av += ["--resume", session] if resume else ["--session-id", session]
    # Variadic, so it goes last: the prompt arrives on stdin and there is no positional
    # argument after it for the list to swallow.
    if job.get("allowed_tools"):
        av += ["--allowedTools", *job["allowed_tools"]]
    return av


def _envelope(harness, raw):
    """(text, cost_usd, session_id, error) from the harness's own JSON envelope."""
    try:
        env = json.loads(raw)
    except json.JSONDecodeError:
        # opencode's `--format json` emits an event stream rather than one object; the
        # last object carrying text is the reply.
        text, sid = None, None
        for line in raw.splitlines():
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(ev, dict) and ev.get("text"):
                text = ev["text"]
            if isinstance(ev, dict) and ev.get("sessionID"):
                sid = ev["sessionID"]
        return text, 0.0, sid, (None if text else "harness output was not JSON")
    if isinstance(env, dict):
        sid = env.get("session_id") or env.get("sessionID")
        if env.get("is_error"):
            return None, float(env.get("total_cost_usd") or 0), sid, \
                str(env.get("result") or "the agent reported an error")
        return env.get("result"), float(env.get("total_cost_usd") or 0), sid, None
    return None, 0.0, None, "harness output was not a JSON object"


# --------------------------------------------------------------------------------
# Streaming — the same spawn, read as it happens
# --------------------------------------------------------------------------------

def _reduce(ev):
    """One harness event reduced to the vocabulary a caller renders: a tool call, a line
    of text, or the turn's result. Anything else is a shape a renderer has no use for."""
    if not isinstance(ev, dict):
        return None
    t = ev.get("type")
    if t == "assistant":
        out = []
        for block in ((ev.get("message") or {}).get("content") or []):
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use":
                out.append({"kind": "tool", "name": block.get("name"),
                            "input": block.get("input") or {}})
            elif block.get("type") == "text" and (block.get("text") or "").strip():
                out.append({"kind": "text", "text": block["text"].strip()})
        return out or None
    if t == "result":
        return [{"kind": "result", "is_error": bool(ev.get("is_error")),
                 "text": ev.get("result"), "cost_usd": float(ev.get("total_cost_usd") or 0),
                 "session_id": ev.get("session_id"), "subtype": ev.get("subtype")}]
    if t == "system" and ev.get("subtype") == "init":
        return [{"kind": "start", "session_id": ev.get("session_id"), "model": ev.get("model")}]
    return None


def _run_streamed(harness, argv, ask, cwd, on_event, timeout, env=None):
    """(text, cost, session_id, error) — the turn read line by line as it runs.

    Every event is handed to `on_event` before the turn ends, which is what makes a run
    watchable; the last `result` event is still the envelope, so nothing downstream has to
    know whether the turn was streamed or waited for.
    """
    text, sid, err, cost = None, None, None, 0.0
    lines = []
    proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True, cwd=cwd, bufsize=1,
                            env=env)
    _track(proc)
    try:
        proc.stdin.write(ask)
        proc.stdin.close()
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            lines.append(line)
            if on_event:
                on_event({"kind": "raw", "line": line})
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            for e in (_reduce(ev) or []):
                if e["kind"] == "result":
                    text, cost = e["text"], e["cost_usd"]
                    sid = e.get("session_id") or sid
                    if e["is_error"]:
                        err, text = (text or "the agent reported an error"), None
                elif e["kind"] == "start":
                    sid = e.get("session_id") or sid
                if on_event:
                    on_event(e)
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        return None, cost, sid, f"the agent did not finish within {timeout}s"
    finally:
        _untrack(proc)
    if text is None and err is None:
        # No event this module recognised as the result. The lines are still the harness's
        # own reply, so they go through the envelope reader rather than being thrown away
        # — which is what lets a harness whose event shape is not reduced here still work.
        text, cost, got, err = _envelope(harness, "\n".join(lines))
        sid = got or sid
    return text, cost, sid, err


def extract_json(text):
    """The reply is free text; the payload is the JSON in it. Prefer a fenced block, then
    the outermost braces, so a model that explains itself first still parses."""
    if not text:
        return None
    s = text.strip()
    if "```" in s:
        parts = s.split("```")
        for i in range(1, len(parts), 2):
            body = parts[i]
            if body.startswith("json"):
                body = body[4:]
            body = body.strip()
            if body.startswith(("{", "[")):
                try:
                    return json.loads(body)
                except json.JSONDecodeError:
                    pass
    for opener, closer in (("{", "}"), ("[", "]")):
        i, j = s.find(opener), s.rfind(closer)
        if 0 <= i < j:
            try:
                return json.loads(s[i:j + 1])
            except json.JSONDecodeError:
                pass
    return None


def validate(obj, schema):
    """Enough of JSON Schema to catch what a model actually gets wrong here: the wrong
    top-level type, a missing required key, an array where an object belongs. Not a
    validator — a gate that turns a malformed reply into a retry with a reason."""
    if schema is None:
        return None
    t = schema.get("type")
    if t == "object" and not isinstance(obj, dict):
        return f"expected a JSON object, got {type(obj).__name__}"
    if t == "array" and not isinstance(obj, list):
        return f"expected a JSON array, got {type(obj).__name__}"
    if isinstance(obj, dict):
        missing = [k for k in (schema.get("required") or []) if k not in obj]
        if missing:
            return f"missing required key(s): {', '.join(missing)}"
        props = schema.get("properties") or {}
        for k, sub in props.items():
            if k in obj and isinstance(sub, dict) and sub.get("type") == "array" \
                    and obj[k] is not None and not isinstance(obj[k], list):
                return f"'{k}' must be an array"
    return None


SCHEMA_NOTE = (
    "\n\n---\nRETURN ONLY JSON. Your entire reply must be one JSON value matching this schema, "
    "with no prose before or after it and no code fence:\n{schema}\n"
)


def run_job(job, schema, *, harness, cwd, model=None, log=None, env=None,
            session=None, resume=False, on_event=None, attempts=MAX_ATTEMPTS):
    """One agent, retried while its reply does not parse or does not fit the schema.

    With `on_event` the turn is streamed and every tool call reaches the caller as it
    happens; without it the whole reply arrives at the end. `session` continues a
    conversation across calls — a separate process per turn against one id, because a turn
    written into a held-open stream while the model is mid-turn is discarded silently, and
    a run that skipped a task that way would be indistinguishable from one that built it.
    """
    prompt = job["prompt"] + SCHEMA_NOTE.format(schema=json.dumps(schema)) if schema else job["prompt"]
    attempt, complaint, spent = 0, None, 0.0
    work = cwd
    tree = None
    sid = session
    if job.get("isolation") == "worktree":
        tree = _make_worktree(cwd)
        work = tree or cwd
    try:
        while attempt < attempts:
            if STOPPING:
                return {"id": job["id"], "ok": False, "cost_usd": spent, "session_id": sid,
                        "error": "the runner was stopped"}
            attempt += 1
            ask = prompt if complaint is None else (
                prompt + f"\n\nYour previous reply could not be used: {complaint}. "
                         f"Return only the JSON, matching the schema exactly.")
            argv = _argv(harness, job, model, session=sid, resume=resume, stream=bool(on_event))
            if on_event:
                text, cost, got, err = _run_streamed(harness, argv, ask, work, on_event,
                                                     TIMEOUT_S, env)
            else:
                proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL, text=True, cwd=work, env=env)
                _track(proc)
                try:
                    stdout, _ = proc.communicate(ask, timeout=TIMEOUT_S)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    return {"id": job["id"], "ok": False, "cost_usd": spent, "session_id": sid,
                            "error": f"the agent did not finish within {TIMEOUT_S}s"}
                finally:
                    _untrack(proc)
                text, cost, got, err = _envelope(harness, stdout)
            spent += cost
            # A retry continues the conversation the first attempt opened, so what it is
            # told went wrong is said to the session that got it wrong.
            if got:
                sid = got
            if sid:
                resume = True
            if err:
                complaint = err
                if log:
                    log(f"{job['id']}: {err} (attempt {attempt}/{attempts})")
                continue
            data = extract_json(text) if schema else text
            if schema:
                if data is None:
                    complaint = "the reply contained no JSON"
                else:
                    complaint = validate(data, schema)
                if complaint:
                    if log:
                        log(f"{job['id']}: {complaint} (attempt {attempt}/{attempts})")
                    continue
            return {"id": job["id"], "ok": True, "cost_usd": spent, "data": data,
                    "session_id": sid, "attempts": attempt}
        return {"id": job["id"], "ok": False, "cost_usd": spent, "session_id": sid,
                "error": f"no usable reply in {attempts} attempts: {complaint}"}
    finally:
        if tree:
            _remove_worktree(cwd, tree)


def _make_worktree(repo):
    """Every verifier that mutates gets a checkout of its own. Sharing one, agents read
    each other's experiments — measured at 22 interference reports over six runs, once
    refuting a claim on a probe file that was not the verifier's."""
    try:
        head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True,
                              text=True, check=True).stdout.strip()
        path = tempfile.mkdtemp(prefix="clerk-audit-")
        subprocess.run(["git", "worktree", "add", "--detach", path, head], cwd=repo,
                       capture_output=True, text=True, check=True)
        return path
    except (subprocess.CalledProcessError, OSError):
        return None


def _remove_worktree(repo, path):
    subprocess.run(["git", "worktree", "remove", "--force", path], cwd=repo,
                   capture_output=True, text=True)
    shutil.rmtree(path, ignore_errors=True)


def run_batch(jobs, schemas, *, harness, cwd, concurrent=True, workers=None, model=None,
              log=None, on_start=None, on_event=None, on_done=None):
    """A phase's jobs, concurrently when the phase says they are independent.

    The callbacks are what makes a long phase watchable: `on_start` when a job is handed
    to the harness, `on_event` for each thing it does, `on_done` the moment it returns.
    Each is given the job's id, because several of these run at once and a line that does
    not say which agent produced it is worse than no line.
    """
    if not jobs:
        return []
    def one(j):
        if on_start:
            on_start(j)
        r = run_job(j, schemas.get(j.get("schema_name")), harness=harness, cwd=cwd,
                    model=model, log=log,
                    on_event=(lambda e, jid=j["id"]: on_event(jid, e)) if on_event else None)
        if on_done:
            on_done(j, r)
        return r
    if not concurrent or len(jobs) == 1:
        return [one(j) for j in jobs]
    n = min(workers or DEFAULT_WORKERS, len(jobs))
    with ThreadPoolExecutor(max_workers=n) as pool:
        # as_completed, not pool.map: map yields in submission order, so a lens that
        # finished in twenty seconds stays unreported behind one still running at three
        # minutes. The list handed back keeps the caller's order all the same.
        futures = {pool.submit(one, j): j["id"] for j in jobs}
        done = {}
        for f in as_completed(futures):
            done[futures[f]] = f.result()
        return [done[j["id"]] for j in jobs]
