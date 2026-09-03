"""The step table of an implement run: each row answers whether it is done, and if not,
why and what does it.

`clerk step` reads the rows from the top and returns the first that is not done, with the
method text for it. There is no counter: position is recomputed on every call from git
state and the ledger, so a stopped run continues with the same call and the model cannot
move past a step by saying so. Receipts and acceptances are compared by code tree, the
HEAD tree minus the breakdown files under tasks/, so a tasks/-only commit — the Theory
section, the archive — does not send a run back to the suite.
"""

import hashlib
import json
import os
import re
from pathlib import Path

from clerk_lib import clerk, die, git, gitout, worktree_for
from clerk_method import Renderer
from clerk_ledger import (age_seconds, fixup_ambiguities, gear, guidelines_read, is_ancestor,
                          learn_written, now, receipt_state, ref_exists, runner_view, session_id,
                          task_signals)

VALIDATE_QUESTIONS = [
    "What does the story ask for that this branch does not do?",
    "Where does the branch satisfy a task's acceptance criteria by measuring a proxy for what was asked rather than the thing itself?",
    "Where did a criterion the story stated as a category become a list in the breakdown? Check the list against the source that defines the set.",
    "Which test fails when a criterion is violated? Name one per criterion, and make the headline one fail.",
]


# --------------------------------------------------------------------------------
# Instructions — the method text for a step, or a built-in summary of it
# --------------------------------------------------------------------------------

# The method's step files are the instructions, and `clerk step` prints the one for the
# step it returns. Only two steps have no file: `start`, because a run that has not
# opened has nothing to render yet, and `finished`, which is a sentence. Every other
# step used to carry a built-in copy of its text as well, for a machine without the
# method — a second source, and it drifted from the first within a week.
BUILTIN = {
    "start": "No run is open here. Record the request verbatim: `clerk step --start <kebab-slug> --request \"<the request>\"`. The slug becomes the branch name.",
    "finished": "The run is complete.",
}


def method_dir():
    return Path(os.environ.get("CLERK_METHOD_DIR") or Path.home() / ".config" / "ai" / "method" / "implement")


def render_method(text, harness):
    """One step file with its markers resolved for one harness, by the same resolver
    `gen-skills.sh` renders whole bodies with. A missing fragment is marked in place
    rather than fatal: a step printed mid-run is worth more with a hole named than not
    printed at all."""
    mdir = method_dir()
    return Renderer(mdir.parent, mdir / "seams" / harness, strict=False).render_text(text).strip("\n")


# The gears pause is a moment inside the build step, and the method text for it is the
# build step's; the built-in summary says what to show and where to stop.
STEP_TEXT_ALIAS = {"pause": "build"}

# How long a printed text is taken to still be in the caller's view. Claude Code names
# its session, so a new session is told apart outright; a harness that does not gets
# the window alone.
SHOWN_FOR = 2 * 60 * 60


def instructions_for(step_id, harness):
    p = method_dir() / "steps" / f"{STEP_TEXT_ALIAS.get(step_id, step_id)}.md"
    if p.exists():
        return render_method(p.read_text(), harness)
    if step_id in BUILTIN:
        return BUILTIN[step_id]
    return (f"no method text for the {step_id} step: {p} does not exist. `done_by` names "
            f"the command that moves the run on; set CLERK_METHOD_DIR to the implement "
            f"method directory for the full text.")


def instructions_text(ctx, step_id):
    """(text, elided) — the method text in full the first time this session reaches a
    step, and a one-line pointer while the same text would only be repeated. The task
    text is ten kilobytes and the task row comes back once per task; printing it every
    time was most of what a run paid clerk for, and all of it sat in the caller's context
    already. The pointer goes only to the session that saw the text, within SHOWN_FOR;
    `--full` prints it again on demand, after a context compaction say."""
    key = STEP_TEXT_ALIAS.get(step_id, step_id)
    text = instructions_for(step_id, ctx.harness)
    if ctx.run is None or ctx.full or step_id in BUILTIN:
        return text, False
    shown = ctx.run.read("shown.json") or {}
    if (shown.get("text") == key and shown.get("session") == session_id()
            and age_seconds(shown.get("at")) < SHOWN_FOR):
        return (f"unchanged: the {key} step's text was printed by the reply that first reached this "
                f"step, and `done_by` says what to run; `clerk step --full` prints it again"), True
    if not ctx.read_only:
        ctx.run.write("shown.json", {"text": key, "at": now(), "session": session_id()})
    return text, False


# --------------------------------------------------------------------------------
# The step table. Each row answers: is it done, and if not, why and what does it.
# --------------------------------------------------------------------------------

def row(step_id, done, **fields):
    r = {"step": step_id, "done": done}
    r.update(fields)
    return r


def breakdown_files(ctx):
    """(tasks_file, sidecar, archived) for the bound breakdown. `clerk land` moves both
    into tasks/completed/, and a run that has landed still reads them from there."""
    bd = ctx.run.read("breakdown.json")
    if not bd:
        return None, None, False
    tf, side = Path(bd["tasks_file"]), Path(bd["sidecar"])
    if tf.exists():
        return tf, side, False
    home = Path(ctx.prepare.get("tasks_home") or ctx.cwd)
    atf = home / "tasks" / "completed" / tf.name
    if atf.exists():
        return atf, atf.with_suffix(".json"), True
    return tf, side, False


def sidecar_tasks(ctx):
    bd = ctx.run.read("breakdown.json")
    if not bd:
        return None, None
    _, side, _ = breakdown_files(ctx)
    if not side.exists():
        return bd, None
    return bd, json.loads(side.read_text()).get("tasks", [])


def row_ground(ctx):
    rec = guidelines_read(ctx.run) or ctx.run.done.get("ground")
    if rec and rec.get("caller"):
        return row("ground", True, caller=rec["caller"], source=rec.get("source", "asserted"))
    if not ctx.prepare.get("clean"):
        return row("ground", False, blocked=True, stop=True,
                   reason="the tree is dirty — never build on top of someone else's loose work; stop and ask",
                   why_not_done="tree dirty")
    return row("ground", False,
               why_not_done="no `clerk guidelines --caller <pattern>` has run for this run",
               done_by="clerk guidelines; then clerk guidelines --caller <pattern> [--dom] [--state]; then clerk step. "
                       "(A repo with no guidelines directory: clerk step --done ground --caller <pattern>)")


def run_branch(ctx):
    """Where the run's branch stands, resolved once per call: whether it still exists,
    whether the default branch already contains it, and which worktree holds it. The
    isolate and land rows and `landed_elsewhere` each derived a part of this on their own."""
    if ctx.branch_state is None:
        slug = ctx.run.slug
        ctx.branch_state = {"exists": ref_exists(slug, ctx.cwd),
                            "merged": bool(ctx.default) and is_ancestor(slug, ctx.default, ctx.cwd),
                            "worktree": worktree_for(slug, ctx.prepare.get("worktrees"))}
    return ctx.branch_state


def landed_elsewhere(ctx):
    """True when the run has left its branch for a reason the table accepts: the branch
    was merged or deleted, or its worktree holds the archive record."""
    if not ctx.run.read("breakdown.json"):
        return False
    b = run_branch(ctx)
    if not b["exists"] or b["merged"]:
        return True
    if b["worktree"]:
        gd = gitout("rev-parse", "--absolute-git-dir", cwd=b["worktree"])
        return bool(gd) and (Path(gd) / "clerk" / "archived.json").exists()
    return False


def row_isolate(ctx):
    slug = ctx.run.slug
    if ctx.branch == slug:
        in_place = bool(ctx.flags.get("in_place"))
        mode = "worktree" if ctx.in_worktree else "in-place"
        fallback = (not ctx.in_worktree) and (not in_place)
        return row("isolate", True, mode=mode, fallback=fallback, path=ctx.build_tree)
    if landed_elsewhere(ctx):
        return row("isolate", True, mode="landed", note="the run has left its branch; it landed")
    b = run_branch(ctx)
    if b["exists"]:
        wt = b["worktree"]
        if wt:
            return row("isolate", False, action="enter", path=wt,
                       why_not_done=f"the run's worktree is {wt} and this call is not in it",
                       done_by=f"enter {wt} (EnterWorktree with that path on Claude Code; cd elsewhere), then clerk step")
        return row("isolate", False, action="switch",
                   why_not_done=f"branch {slug} exists with no worktree; this run builds in place",
                   done_by=f"clerk branch {slug} — it returns the step that follows as next")
    if ctx.flags.get("in_place"):
        return row("isolate", False, action="branch",
                   why_not_done="in_place is on and the run has no branch yet",
                   done_by=f"clerk branch {slug} — it returns the step that follows as next")
    return row("isolate", False, action="worktree",
               why_not_done="the run has no worktree yet",
               done_by=f"clerk worktree {slug}; enter the path it reports; then clerk step")


def lint_sidecar(side_path, cwd):
    rc, data, err = clerk("lint", "--rule", "certainty-unevidenced", "--json", str(side_path), cwd=cwd)
    if rc not in (0, 1):
        die(f"clerk lint failed: {err}")
    return data or []


def file_hash(path):
    return hashlib.sha1(Path(path).read_bytes()).hexdigest()


def row_decompose(ctx):
    bd = ctx.run.read("breakdown.json")
    resume = ctx.prepare.get("resume")
    if not bd:
        return row("decompose", False,
                   why_not_done="no breakdown is bound to this run",
                   resume=resume, breakdowns=ctx.prepare.get("breakdowns"),
                   done_by="clerk step --done decompose --tasks-file <tasks/<story>.md> [--approved]")
    tf, side, archived = breakdown_files(ctx)
    if archived:
        return row("decompose", True, tasks_file=str(tf), sidecar=str(side), archived=True)
    if not side.exists():
        return row("decompose", False, tasks_file=bd["tasks_file"],
                   why_not_done=f"no sidecar at {side} — run `clerk sidecar` to recover one, then bind again",
                   done_by=f"clerk sidecar; clerk step --done decompose --tasks-file {bd['tasks_file']}")
    if file_hash(side) != bd.get("lint_hash"):
        findings = lint_sidecar(side, ctx.cwd)
        if findings:
            return row("decompose", False, tasks_file=bd["tasks_file"], findings=findings,
                       why_not_done="the sidecar changed and `lint certainty-unevidenced` now reports findings",
                       done_by="correct the assessments, then clerk step --done decompose --tasks-file again")
    if ctx.flags.get("review_breakdown") and not bd.get("approved"):
        return row("decompose", False, stop=True, tasks_file=bd["tasks_file"],
                   why_not_done="review_breakdown is on and the breakdown is not approved",
                   done_by=f"show the breakdown and wait for approval; then clerk step --done decompose --tasks-file {bd['tasks_file']} --approved")
    return row("decompose", True, tasks_file=bd["tasks_file"], sidecar=bd["sidecar"])


def row_build(ctx):
    tf, side, _ = breakdown_files(ctx)
    if tf is None or not side.exists():
        return row("build", False, why_not_done="no sidecar to read tasks from")
    # `clerk status` owns which task is ready — the dependency rule is applied, not repeated.
    rc, st, err = clerk("status", "--tasks-file", str(tf), cwd=ctx.cwd)
    if st is None:
        die(f"clerk status failed: {err}")
    nx = st.get("next") or {}
    total, remaining = nx.get("total", 0), nx.get("remaining", 0)
    progress = {"done": total - remaining, "total": total, "remaining": remaining, "blocked": nx.get("blocked", 0)}
    if nx.get("done"):
        return row("build", True, progress=progress)
    cur = nx.get("task")
    if cur is None:
        return row("build", False, blocked=True, stop=True, progress=progress,
                   reason="open tasks remain but none is unblocked — the dependency graph has a cycle or names a task that is not there",
                   why_not_done="no ready task")
    n = cur["n"]
    gears = bool(ctx.flags.get("gears"))
    certainty = cur.get("certainty")
    blast = cur.get("blast_radius")
    signals, order = task_signals(ctx.run)
    g = gear(signals, order)
    reasons = [r for r, hit in (("certainty low", certainty == "low"), ("blast radius high", blast == "high"),
                                ("the run downshifted", g == "low")) if hit]
    pauses = gears and bool(reasons)
    shown = str(n) in (ctx.run.done.get("pause") or {})
    fields = dict(n=n, task=cur, certainty=certainty, blast_radius=blast,
                  unassessed=(certainty is None and blast is None), gear=g,
                  last_task_signals=(signals.get(order[-1]) if order else None),
                  tree_dirty=not ctx.prepare.get("clean"), progress=progress,
                  commit_skill=ctx.prepare.get("commit_skill"))
    if pauses and not shown:
        return row("pause", False, stop=True,
                   why_not_done=f"task {n} pauses after its tests ({', '.join(reasons)}) and they were not shown",
                   done_by=f"write the tests, run them red, show the assertions, stop; then clerk step --done pause {n}",
                   **fields)
    return row("build", False, pause_after_tests=pauses,
               why_not_done=f"task {n} is open",
               done_by=f"clerk finish {n} [--retried] -- <files> (it lints the staged set and returns the step after the commit as after_commit); commit with the {fields['commit_skill']} skill; then act on after_commit",
               **fields)


def row_suite(ctx):
    fresh, rec, why = receipt_state(ctx)
    if fresh:
        return row("suite", True, receipt={"sha": rec["sha"], "command": rec["command"], "at": rec.get("at")})
    cmd = ctx.prepare.get("test_command")
    return row("suite", False, why_not_done=why, test_command=cmd, build_tree=ctx.build_tree,
               done_by=f"run `{cmd}` in {ctx.build_tree}; clerk receipt --command \"{cmd}\" --passed --output-file <file>")


def row_audit(ctx):
    aud = ctx.run.read("audit.json", {})
    rounds = aud.get("rounds", [])
    accepted = aud.get("accepted")
    fields = dict(request=ctx.run.meta.get("request"), base=ctx.prepare.get("base"),
                  test_commands=ctx.prepare.get("test_commands"),
                  rounds_planned=aud.get("rounds_planned"), rounds_done=len(rounds),
                  last_round_fresh=bool(rounds) and rounds[-1].get("code_tree") == ctx.head_ct)
    if accepted and accepted.get("code_tree") == ctx.head_ct:
        return row("audit", True, rounds_done=len(rounds), accepted_at=accepted.get("at"))
    live = aud.get("live")
    runner = runner_view(live)
    if runner:
        fields["runner"] = runner
    if runner and runner["alive"]:
        why = f"round {live['round']} is running: pid {runner['pid']}, in {runner['phase']}"
    elif runner and not runner.get("finished_at"):
        why = (f"round {live['round']} is in flight but its runner (pid {runner['pid']}) is gone — "
               f"it entered {runner['phase']} at {runner['started_at']}, {len(runner['landed'])} agent(s) "
               f"kept, {len(runner['in_flight'])} to run again; `clerk audit run` resumes it")
    elif not rounds:
        why = "no audit round is recorded for this run"
    elif not accepted:
        why = f"{len(rounds)} round(s) recorded, findings not yet accepted"
    else:
        why = "the acceptance describes an earlier code tree — the code changed since"
    return row("audit", False, why_not_done=why,
               done_by="clerk audit plan --rounds <n>; audit-implement; clerk audit round --report <json>; fix + clerk fixup + suite + clerk receipt; ...; clerk audit accept",
               **fields)


def row_match_request(ctx):
    rec = ctx.run.read("match-request.json")
    base = ctx.prepare.get("base")
    log = gitout("log", "--oneline", f"{base}..HEAD", cwd=ctx.cwd) if base else gitout("log", "--oneline", "-20", cwd=ctx.cwd)
    fields = dict(request=ctx.run.meta.get("request"), log=(log or "").splitlines(), questions=VALIDATE_QUESTIONS)
    if rec and rec.get("code_tree") == ctx.head_ct:
        if rec.get("mismatches") and not rec.get("resolved"):
            return row("match-request", False, blocked=True, stop=True,
                       reason="mismatches were recorded; put them to the user and stop. After the decision: clerk step --done match-request --resolved",
                       mismatches=rec["mismatches"], why_not_done="unresolved mismatches", **fields)
        return row("match-request", True, mismatches=rec.get("mismatches", []))
    why = "the request was not re-read against this code tree" if not rec else "validated at an earlier code tree — the code changed since"
    return row("match-request", False, why_not_done=why,
               done_by="clerk step --done match-request [--mismatch \"<quoted words>\"]...", **fields)


def row_explain(ctx):
    tf, _, archived = breakdown_files(ctx)
    if tf is None:
        return row("explain", False, why_not_done="no breakdown is bound to this run")
    text = tf.read_text() if tf.exists() else ""
    if not re.search(r"^## Theory\b", text, re.M):
        return row("explain", False, tasks_file=str(tf),
                   why_not_done=f"no `## Theory` section in {tf}",
                   done_by="write the section; commit it when the breakdown is tracked; then clerk step")
    if ctx.prepare.get("tasks_tracked") and not archived:
        dirty = git("status", "--porcelain", "--", str(tf), cwd=ctx.cwd).stdout.strip()
        if dirty:
            return row("explain", False, tasks_file=str(tf),
                       why_not_done="the Theory is written but not committed",
                       done_by="commit the breakdown as its own commit; then clerk step")
    return row("explain", True, tasks_file=str(tf))


def row_verify_run(ctx):
    # A pass is recorded at its code tree, so the tasks/-only commits that follow — the
    # Theory, the archive — do not send the run back through git grep, and a run that has
    # landed is not re-verified against a receipt `clerk verify` still compares by SHA.
    passed = ctx.run.done.get("verify-run")
    if passed and passed.get("code_tree") == ctx.head_ct:
        return row("verify-run", True, cached=True)
    tf, _, archived = breakdown_files(ctx)
    args = ["verify", "--all-closed"]
    if tf is not None and not archived:
        args += ["--tasks-file", str(tf)]
    rc, data, err = clerk(*args, cwd=ctx.cwd)
    if data is None:
        die(f"clerk verify failed: {err}")
    clean = bool(data.get("clean"))
    not_checked = data.get("not_checked", [])
    if not ctx.read_only:
        # Which check fired, every time the step asks. The event log records that `clerk
        # verify` ran and what it exited, and answering "is this step worth its blocks"
        # needs the rules — twelve runs of ledgers could say it blocked 53 times out of 60
        # and not say what any of them was.
        findings = data.get("findings") or []
        ctx.run.append("verify-log.jsonl", {
            "at": now(), "code_tree": ctx.head_ct, "clean": clean,
            "blocks": sorted({f.get("check") for f in findings if f.get("severity") == "block"}),
            "warns": sorted({f.get("check") for f in findings if f.get("severity") != "block"}),
            "not_checked": len(not_checked), "hints": len(data.get("hints") or [])})
    residue = ctx.run.done.get("verify-residue")
    residue_ok = bool(residue) and residue.get("code_tree") == ctx.head_ct
    if clean and (not not_checked or residue_ok):
        if not ctx.read_only:
            ctx.run.mark("verify-run", {"at": now(), "code_tree": ctx.head_ct, "not_checked": not_checked})
        return row("verify-run", True, findings=data.get("findings", []), not_checked=not_checked)
    if not clean:
        why = "clerk verify reports a block"
        done_by = "fix the block; then clerk step"
    else:
        why = "clerk verify left checks in not_checked that need judgment"
        done_by = ("spawn run-verifier, passing it the `not_checked` list verbatim so it works "
                   "those gaps rather than the whole branch; then clerk step --done verify-residue")
    return row("verify-run", False, why_not_done=why,
               verify=data, done_by=done_by)


def row_land(ctx):
    slug = ctx.run.slug
    stamp = ctx.run.read("land.json")
    if stamp and stamp.get("landed"):
        return row("land", True, archived=True, integrated=True, source="land.json")
    if ctx.branch == slug:
        archived = bool(stamp) or (Path(ctx.git_dir) / "clerk" / "archived.json").exists()
        if not archived:
            return row("land", False, action="archive", why_not_done="the breakdown is not archived",
                       integrate=ctx.flags.get("integrate"),
                       done_by="clerk land [--integrate|--no-integrate] — it returns the step that follows as next")
        integrate = stamp.get("integrate") if stamp else ctx.flags.get("integrate")
        if integrate and ctx.in_worktree:
            return row("land", False, action="leave",
                       why_not_done="archived; integration is on and cannot finish from inside the worktree",
                       done_by=f"leave the worktree keeping the branch (ExitWorktree keep on Claude Code), run the command `clerk land` printed in {ctx.repo_root}, then clerk step there")
        return row("land", True, archived=True, integrated=False)
    b = run_branch(ctx)
    if not b["exists"]:
        return row("land", True, archived=True, integrated=True)
    wt = b["worktree"]
    if b["merged"]:
        if wt:
            return row("land", False, action="cleanup", why_not_done=f"merged; the worktree at {wt} remains",
                       done_by=f"git worktree remove {wt} && git branch -d {slug}; then clerk step")
        return row("land", False, action="cleanup", why_not_done=f"merged; branch {slug} remains",
                   done_by=f"git branch -d {slug}; then clerk step")
    cmd = f"git -C {ctx.repo_root} merge --ff-only {slug}"
    if wt:
        cmd += f" && git -C {ctx.repo_root} worktree remove {wt}"
    cmd += f" && git -C {ctx.repo_root} branch -d {slug}"
    return row("land", False, action="merge", why_not_done=f"archived on {slug}, not yet on {ctx.default}",
               done_by=f"{cmd}; then clerk step")


def breakdown_signals(ctx):
    """What this run observed about the breakdown, for the reflection: the tasks it
    called routine that were not, the ones it called hard that were, and the fixups that
    found a task boundary drawn across one file."""
    _, tasks = sidecar_tasks(ctx)
    signals, order = task_signals(ctx.run)
    by_n = {t["n"]: t for t in (tasks or [])}
    hard = lambda n: bool(signals.get(n, {}).get("retried") or signals.get(n, {}).get("lint_findings"))
    return {
        "signals": {str(n): signals[n] for n in sorted(signals)},
        "high_certainty_but_hard": [n for n in order if by_n.get(n, {}).get("certainty") == "high" and hard(n)],
        "low_certainty_but_clean": [n for n in order if by_n.get(n, {}).get("certainty") == "low" and not hard(n)],
        "fixup_ambiguous": fixup_ambiguities(ctx.run),
    }


def row_learn(ctx):
    rec = learn_written(ctx.run) or ctx.run.done.get("learn")
    if rec:
        return row("learn", True, none=bool(rec.get("none")), source=rec.get("source", "asserted"))
    return row("learn", False, why_not_done="no learning was written for this run",
               learnings_path=ctx.prepare.get("learnings_path"), breakdown_signals=breakdown_signals(ctx),
               done_by=f"clerk learn --list; clerk learn --type ... --title ... --learning ... --apply-when ... --feature {ctx.run.slug}; "
                       f"or, for a run with nothing that generalises: clerk step --done learn --none")


ROWS = [("ground", row_ground), ("isolate", row_isolate), ("decompose", row_decompose), ("build", row_build),
        ("suite", row_suite), ("audit", row_audit), ("match-request", row_match_request), ("explain", row_explain),
        ("verify-run", row_verify_run), ("land", row_land), ("learn", row_learn)]


def active_rows(ctx):
    """A run that has left its branch by landing is past everything the branch held: only
    the integration and the learnings remain, and both are read from the main checkout."""
    if ctx.branch != ctx.run.slug and landed_elsewhere(ctx):
        return [(n, f) for n, f in ROWS if n in ("land", "learn")]
    return ROWS


def evaluate(ctx):
    """The first row that is not done, or the finished marker."""
    for _, fn in active_rows(ctx):
        r = fn(ctx)
        if not r["done"]:
            return r
    return row("finished", True)


def next_step(ctx):
    """The step that follows, as `clerk step` would print it. Returned by every command
    that closes a step — --start, each --done, audit accept — so the caller acts on it
    instead of asking for it in a second call. The one write is the run's own
    `finished`, stamped the first time the table is walked to its end."""
    r = evaluate(ctx)
    if r["step"] == "finished" and not ctx.run.finished and not ctx.read_only:
        meta = ctx.run.meta
        meta["finished"] = True
        meta["finished_at"] = now()
        ctx.run.write("run.json", meta)
    if r["step"] == "finished":
        r["stats"] = run_stats_text(ctx)
    return present(ctx, r)


def run_stats_text(ctx):
    """The run's time and token table, for the closing message. A failure here is
    reported in place of the table, never as a failed `clerk step`."""
    try:
        import clerk_stats
        return clerk_stats.render(clerk_stats.collect(ctx.run, ctx.run.meta.get("launch_cwd") or ctx.cwd))
    except Exception as e:  # noqa: BLE001
        return f"(statistics unavailable: {e})"


# What the caller reads from `facts`: the repo as prepare resolved it, minus what clerk
# keeps for itself — the receipt, the run, the worktrees, the breakdown list, the code
# tree (its own field). Every row already carries the fact it turns on, so the rest is
# orientation; the rest was also a third of every reply, repeated on every call.
FACTS_KEYS = ("repo_root", "build_tree", "in_worktree", "branch", "default_branch", "base", "clean",
              "languages", "test_commands", "test_command", "go_tool_prefix",
              "learnings_path", "learnings_path_source", "commit_skill",
              "tasks_file", "tasks_home", "tasks_tracked", "flags", "flag_sources", "resume")


def facts_for(ctx):
    return {k: ctx.prepare.get(k) for k in FACTS_KEYS if k in ctx.prepare}


def present(ctx, r):
    out = {"run": ctx.run.slug, "step": r["step"]}
    for k, v in r.items():
        if k in ("step", "done"):
            continue
        out[k] = v
    out.setdefault("stop", False)
    out.setdefault("blocked", False)
    out["code_tree"] = ctx.head_ct
    out["harness"] = ctx.harness
    out["instructions"], out["instructions_elided"] = instructions_text(ctx, r["step"])
    out["facts"] = facts_for(ctx)
    return out
