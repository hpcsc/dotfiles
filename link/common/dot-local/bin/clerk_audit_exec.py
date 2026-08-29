"""Spawning an audit agent from a program rather than from a model.

The panel decides what to run and the phase machine decides when; this is the part that
actually starts something. It shells out to whichever coding harness is installed —
`claude -p` or `opencode run` — so the orchestration loop is a Python `while` and not a
model following instructions about one.

Two things the harness does for an in-session subagent and does NOT do here, so they are
done here instead: a schema is not enforced, so a reply is parsed and validated and the
agent is asked again with the error when it does not fit; and no worktree is provided,
so one is made for any job whose claim can only be settled by mutating a checkout.
"""

import json
import os
import shutil
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor

# Claude Code resolves user-defined agents only in a full session: `--bare` skips the
# discovery that finds them and leaves the five built-ins, so every lens would fail to
# resolve. The speed it buys is not worth a panel that silently cannot run.
CLAUDE = ["claude", "-p", "--output-format", "json", "--permission-mode", "acceptEdits"]
OPENCODE = ["opencode", "run", "--format", "json"]

MAX_ATTEMPTS = 3
# A lens reads a whole diff and may run a suite; a scope pass is seconds. The ceiling is
# a runaway guard, not a schedule.
TIMEOUT_S = int(os.environ.get("CLERK_AUDIT_AGENT_TIMEOUT", "1800"))


def detect_harness():
    if os.environ.get("CLERK_AUDIT_HARNESS"):
        return os.environ["CLERK_AUDIT_HARNESS"]
    if shutil.which("claude"):
        return "claude"
    if shutil.which("opencode"):
        return "opencode"
    return None


def _argv(harness, job, model=None):
    if harness == "opencode":
        av = list(OPENCODE)
        if job.get("agent"):
            av += ["--agent", job["agent"]]
        if model:
            av += ["--model", model]
        return av
    av = list(CLAUDE)
    if job.get("agent"):
        av += ["--agent", job["agent"]]
    if model:
        av += ["--model", model]
    return av


def _envelope(harness, raw):
    """(text, cost_usd, error) from the harness's own JSON envelope."""
    try:
        env = json.loads(raw)
    except json.JSONDecodeError:
        # opencode's `--format json` emits an event stream rather than one object; the
        # last object carrying text is the reply.
        text, cost = None, 0.0
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
        return text, cost, (None if text else "harness output was not JSON")
    if isinstance(env, dict):
        if env.get("is_error"):
            return None, float(env.get("total_cost_usd") or 0), str(env.get("result") or "the agent reported an error")
        return env.get("result"), float(env.get("total_cost_usd") or 0), None
    return None, 0.0, "harness output was not a JSON object"


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


def run_job(job, schema, *, harness, cwd, model=None, log=None):
    """One agent, retried while its reply does not parse or does not fit the schema."""
    prompt = job["prompt"] + SCHEMA_NOTE.format(schema=json.dumps(schema)) if schema else job["prompt"]
    attempt, complaint, spent = 0, None, 0.0
    work = cwd
    tree = None
    if job.get("isolation") == "worktree":
        tree = _make_worktree(cwd)
        work = tree or cwd
    try:
        while attempt < MAX_ATTEMPTS:
            attempt += 1
            ask = prompt if complaint is None else (
                prompt + f"\n\nYour previous reply could not be used: {complaint}. "
                         f"Return only the JSON, matching the schema exactly.")
            try:
                proc = subprocess.run(_argv(harness, job, model), input=ask, cwd=work,
                                      capture_output=True, text=True, timeout=TIMEOUT_S)
            except subprocess.TimeoutExpired:
                return {"id": job["id"], "ok": False, "cost_usd": spent,
                        "error": f"the agent did not finish within {TIMEOUT_S}s"}
            text, cost, err = _envelope(harness, proc.stdout)
            spent += cost
            if err:
                complaint = err
                if log:
                    log(f"{job['id']}: {err} (attempt {attempt}/{MAX_ATTEMPTS})")
                continue
            data = extract_json(text) if schema else text
            if schema:
                if data is None:
                    complaint = "the reply contained no JSON"
                else:
                    complaint = validate(data, schema)
                if complaint:
                    if log:
                        log(f"{job['id']}: {complaint} (attempt {attempt}/{MAX_ATTEMPTS})")
                    continue
            return {"id": job["id"], "ok": True, "cost_usd": spent, "data": data,
                    "attempts": attempt}
        return {"id": job["id"], "ok": False, "cost_usd": spent,
                "error": f"no usable reply in {MAX_ATTEMPTS} attempts: {complaint}"}
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


def run_batch(jobs, schemas, *, harness, cwd, concurrent=True, workers=6, model=None, log=None):
    """A phase's jobs, concurrently when the phase says they are independent."""
    if not jobs:
        return []
    def one(j):
        return run_job(j, schemas.get(j.get("schema_name")), harness=harness, cwd=cwd,
                       model=model, log=log)
    if not concurrent or len(jobs) == 1:
        return [one(j) for j in jobs]
    with ThreadPoolExecutor(max_workers=min(workers, len(jobs))) as pool:
        return list(pool.map(one, jobs))
