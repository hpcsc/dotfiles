#!/usr/bin/env python3
"""Scan a PR diff for durability (reversibility) and blast-radius signals.

Usage: scan_signals.py <outdir-from-pr_fetch>
Reads <outdir>/meta.json and <outdir>/diff.patch.
Writes <outdir>/signals.json and prints a markdown summary.

Leads, not verdicts. Every hit needs confirming by reading the code, and the absence
of a hit proves nothing -- this only knows the patterns listed below. Deploy-time
behaviour (terraform plans, filter policies, per-environment flag state) is invisible
to a diff scan and is listed as such in the output.
"""
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

GENERATED = [
    r"(^|/)(vendor|node_modules|dist|build)/",
    r"(^|/)(go\.sum|yarn\.lock|package-lock\.json|Gemfile\.lock|poetry\.lock|Cargo\.lock)$",
    r"\.(pb|pb\.gw)\.go$", r"_gen\.go$", r"(^|/)mock_", r"(^|/)mocks?/",
    r"\.min\.(js|css)$", r"(^|/)__snapshots__/", r"\.snap$",
    r"(^|/)generated/",
]
INFRA = [
    r"\.tf(vars)?$", r"(^|/)serverless.*\.ya?ml$", r"(^|/)\.github/",
    r"(^|/)\.buildkite/", r"(^|/)Dockerfile", r"(^|/)docker-compose",
    r"(^|/)helm/", r"(^|/)k8s/", r"(^|/)terraform/", r"(^|/)Jenkinsfile",
]
TESTS = [
    r"_test\.go$", r"\.(test|spec)\.[tj]sx?$", r"(^|/)(tests?|__tests__)/",
    r"_test\.exs$", r"(^|/)test_.*\.py$", r".*_test\.py$", r"(^|/)testdata/",
]
DOCS = [r"\.mdx?$", r"(^|/)docs?/", r"^LICENSE", r"^CHANGELOG"]
SHARED = [r"^(common|pkg|lib|internal|shared|core|libs|packages)/"]

# key, rung, title, path regex or None, added-line regex or None, removed-line regex or None, note
SIGNALS = [
    # --- D5: destroys information -------------------------------------------------
    ("destructive_sql", "D5", "destructive migration", r"(?i)migrat|\.sql$|schema",
     r"(?i)\b(DROP\s+(TABLE|COLUMN|DATABASE|SCHEMA|INDEX|CONSTRAINT)|TRUNCATE\b|DELETE\s+FROM)\b", None,
     "prior values are unrecoverable without a restore; ask when a restore was last exercised"),
    ("destructive_orm", "D5", "destructive schema call", None,
     r"\b(DropColumn|DropTable|RemoveColumn|drop_column|drop_table|dropTable|remove_column)\b", None,
     "same as a destructive migration, expressed in the ORM"),
    ("data_deletion", "D5", "stored data deletion", None,
     r"\b(DeleteObject|DeleteObjects|DeleteItem|DeleteBucket|deleteMany|\.Purge\(|\.Destroy\()", None,
     "confirm whether the deleted copy is the only one"),
    ("tf_destroy_guard", "D5", "terraform destroy guard lowered", r"\.tf$",
     r"(?i)(force_destroy\s*=\s*true|skip_final_snapshot\s*=\s*true|deletion_protection\s*=\s*false)", None,
     "makes a stateful resource destroyable by a later apply"),
    ("tf_guard_removed", "D5", "terraform protection removed", r"\.tf$", None,
     r"(?i)(prevent_destroy\s*=\s*true|deletion_protection\s*=\s*true|skip_final_snapshot\s*=\s*false)",
     "removing the guard is itself the risky half of the change"),
    ("tf_resource_removed", "D5", "terraform resource removed", r"\.tf$", None,
     r"^\s*resource\s+\"", "apply will destroy it; in-flight state and messages go with it"),
    ("tf_identity_change", "D5", "terraform identity attribute changed", r"\.tf$",
     r"^\s*(name|identifier|bucket|queue_name|topic_name|db_name|cluster_identifier|table_name)\s*=", None,
     "renaming identity on a stateful resource forces destroy-and-create; read the plan before grading"),
    ("credential_rotation", "D5", "credential or secret rotation", None,
     r"(?i)(aws_secretsmanager_secret_version|\brotate\w*\b.*(secret|credential|key|token)|new_password)", None,
     "old credential stops working for everything still holding it"),

    # --- D4: contracts and expectations -------------------------------------------
    ("api_contract", "D4", "published API contract file", r"(?i)(openapi|swagger|asyncapi|\.proto$|schema\.graphql|\.graphqls$)",
     None, None, "consumers outside this repo build against it"),
    ("http_surface", "D4", "HTTP route surface", r"(?i)serverless.*\.ya?ml$",
     r"^\s*-?\s*(http(Api)?:|path:\s*)", None, "a route once published is a URL someone links to"),
    ("route_registration", "D4", "route registration", None,
     r"\b(HandleFunc|router\.(Get|Post|Put|Patch|Delete|Handle)|mux\.Handle|app\.(get|post|put|patch|delete)\(|@(Get|Post|Put|Patch|Delete)Mapping)", None,
     "new or changed request surface"),
    ("field_removed", "D4", "serialised field removed or renamed", None, None,
     r"(json:\"|@JsonProperty|serde\(rename|dynamodbav:\"|xml:\")",
     "removing or renaming a wire field breaks consumers; additive is two-way, subtractive is not"),
    ("contract_field_removed", "D4", "field removed from a contract file",
     r"(?i)(openapi|swagger|asyncapi|\.proto$|schema\.graphql|\.graphqls$|\.avsc$|json-?schema)", None,
     r"^\s*[\"\w-]+\s*[:=]", "consumers outside this repo read this shape"),
    ("access_change", "D4", "access grant or revocation",
     r"(?i)(authorized_?keys|admin[-_]keys|\.pub$|(^|/)access[-_])", None, None,
     "revocation is re-addable, but whoever loses access is locked out until it is; check for in-flight sessions and jobs"),
    ("ssh_key", "D4", "SSH key material", None,
     r"ssh-(rsa|ed25519|dss)|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY",
     r"ssh-(rsa|ed25519|dss)", "adding or removing a key changes who can connect right now"),
    ("event_name", "D4", "event type name", None,
     r"(?i)(event_?type|event_?name)\s*[:=]|\"[A-Z][A-Za-z0-9]*(Created|Updated|Deleted|Submitted|Requested|Received|Linked|Completed|Failed|Cancelled|Sent|Recorded)\"", None,
     "a name written to an append-only log is permanent; every future consumer sees it"),
    ("queue_topic_identity", "D4", "queue/topic identity or filter", r"(?i)(\.tf$|serverless.*\.ya?ml$)",
     r"(?i)(aws_sqs_queue|aws_sns_topic|queue_?name|topic_?name|filter_?policy|subscription)", None,
     "renaming drops in-flight messages; filter changes are unverifiable until applied"),
    ("stored_key_format", "D4", "stored key or id format", None,
     r"(?i)(s3_?key|object_?key|key_?prefix|partition_?key|sort_?key|id_?format)\s*[:=]", None,
     "a key layout becomes permanent as soon as objects are written under it"),

    # --- D3: externalised effects --------------------------------------------------
    ("outbound_comms", "D3", "outbound customer comms", None,
     r"(?i)\b(sendgrid|twilio|messagebird|genesys|send_?email|send_?sms|sendMessage\(|mailer|push_?notification)\b", None,
     "delivered messages cannot be unsent; price rate x time-to-detect"),
    ("comms_content", "D3", "comms content or template", r"(?i)(templates?/|i18n|locales?/|\.tmpl$|\.hbs$|\.mjml$)",
     None, None, "wrong content reaches recipients at full send rate"),
    ("money", "D3", "money movement", None,
     r"(?i)\b(payment|refund|charge|capture|instalment|installment|settlement|payout|invoice|disburse)\b", None,
     "confirm whether this path moves money or only describes it"),
    ("external_publish", "D3", "publish or call out of the system", None,
     r"(?i)(sns\.Publish|PublishInput|PutEvents|EventBridge|webhook|http\.Post|axios\.post|fetch\(\s*[\"']https)", None,
     "the receiving system keeps what you sent"),
    ("vendor_sdk", "D3", "third-party system write", None,
     r"(?i)\b(stripe|adyen|braintree|salesforce|zendesk|frontapp|docusign|experian|equifax|xero|slack_?client)\b", None,
     "state created in someone else's system is theirs to keep"),
    ("file_export", "D3", "file delivery or export", None,
     r"(?i)\b(sftp|PutObject|upload_?(file|to)|csv\.NewWriter|export_?to)\b", None,
     "a delivered file is a delivered file"),

    # --- D2: append-only state ------------------------------------------------------
    ("event_append", "D2", "append-only write", None,
     r"(?i)(\bAppend(ToStream|Events?)?\(|EmitEvent|RecordEvent|event_?store|\boutbox\b)", None,
     "records survive the revert and replay on every rebuild; every future consumer must tolerate the shape"),
    ("queue_send", "D2", "message enqueued", None,
     r"(?i)(SendMessage(Batch)?\(|\bEnqueue\(|producer\.Send|kafka)", None,
     "at-least-once delivery: a non-idempotent handler can do the effect twice"),
    ("audit_write", "D2", "audit trail write", None,
     r"(?i)(audit_?log|immutable|append[_-]?only)", None, "written for compliance, not editable"),

    # --- D1: recoverable state ------------------------------------------------------
    ("migration_additive", "D1", "additive migration", r"(?i)(migrat|\.sql$)",
     r"(?i)\b(ADD\s+COLUMN|CREATE\s+TABLE|CREATE\s+(UNIQUE\s+)?INDEX|ALTER\s+TABLE\s+\w+\s+ADD)\b", None,
     "reversible; check whether the index build locks and whether old code runs against the new schema"),
    ("db_write", "D1", "mutable store write", None,
     r"(?i)(INSERT\s+INTO|UPDATE\s+\w+\s+SET|\.Save\(|\.Create\(|\.Upsert\(|\.Update\()", None,
     "recoverable only if the prior value is still knowable"),
    ("projection", "D1", "projection / read model", r"(?i)(projector|projection|read_?model|catch_?up)",
     None, None, "rebuildable from the source of truth; note the rebuild cost"),

    # --- blast-radius signals -------------------------------------------------------
    ("shared_code", "radius", "shared library code", r"^(common|pkg|lib|internal|shared|core|libs|packages)/",
     None, None, "fans out to every importer; count them before sizing"),
    ("infra", "radius", "infrastructure", r"(\.tf(vars)?$|serverless.*\.ya?ml$|(^|/)terraform/)",
     None, None, "effects land at apply time, not merge time"),
    ("ci", "radius", "build/deploy pipeline", r"(^\.github/|^\.buildkite/|Jenkinsfile|\.gitlab-ci)",
     None, None, "affects every change that ships after it, not just this one"),
    ("dependencies", "radius", "dependency change", r"(go\.mod$|package(-lock)?\.json$|yarn\.lock$|requirements.*\.txt$|Gemfile$|Cargo\.toml$|mix\.lock$)",
     None, None, "transitive behaviour change outside the diff"),
    ("schedule", "radius", "schedule / cron", None,
     r"(?i)(cron\(|rate\(|schedule:\s|@daily|@hourly)", None, "changes when and how often the effect happens"),
    ("shared_limits", "radius", "shared limit or capacity knob", None,
     r"(?i)(reserved_?concurrency|maximum_?concurrency|batch_?size|visibility_?timeout|memory_?size|max_?pool|rate_?limit|quota)", None,
     "the effect can land on other workloads sharing the limit"),
    ("iam", "radius", "IAM / permissions", r"(\.tf$|serverless.*\.ya?ml$)",
     r"(?i)(aws_iam|iamRoleStatements|\"Action\"|Effect:|PolicyDocument)", None,
     "grants outlive the code that needed them"),
    ("authz", "radius", "auth / authorization logic", None,
     r"(?i)\b(authoriz|authenticat|permission|\brole\b|scope|jwt|oauth|api[_-]?key)\b", None,
     "failure here is silent and wide"),
    ("pii", "radius", "personal data", None,
     r"(?i)\b(email|phone|mobile|date_of_birth|dob|ssn|tax_file|passport|first_?name|last_?name|address_line)\b", None,
     "matters most when it lands in a store, a log, or an export"),
    ("llm", "radius", "model / LLM call", None,
     r"(?i)\b(bedrock|anthropic|claude|openai|gpt-|inference_profile|prompt)\b", None,
     "non-deterministic output and per-call cost"),

    # --- mitigations ----------------------------------------------------------------
    ("feature_flag", "mitigation", "feature flag / gate", None,
     r"(?i)\b(feature_?flag|toggle|is_?enabled|rollout|allow_?list|allowlist|canary|enabled_?for)\b", None,
     "confirm the default and the per-environment state -- a flag defaulting on is not a gate"),
    ("idempotency", "mitigation", "idempotency guard", None,
     r"(?i)(idempoten|dedup|already_?(processed|exists|handled)|ON CONFLICT|ErrDuplicate)", None,
     "makes replay and redrive safe"),
    ("dry_run", "mitigation", "dry-run / shadow mode", None,
     r"(?i)(dry[_-]?run|shadow[_-]?mode|dark[_-]?launch|no[_-]?op\b)", None,
     "lets the change run without externalising effects"),
    ("alarm", "mitigation", "alarm / monitoring", None,
     r"(?i)(cloudwatch_metric_alarm|\balarm\b|\balert\b|sentry|datadog|pagerduty|slo)", None,
     "shortens time-to-detect, which shortens irreversible residue"),
    ("backup", "mitigation", "backup / snapshot", None,
     r"(?i)\b(backup|snapshot|point_?in_?time)\b", None, "a backup is a claim until a restore is exercised"),
]

RUNG_ORDER = ["D0", "D1", "D2", "D3", "D4", "D5"]
COMMENT_PREFIXES = ("//", "#", "*", "/*", "<!--", "--")


def matches(path, pats):
    return any(re.search(p, path) for p in pats)


def bucket(path):
    if matches(path, GENERATED):
        return "generated"
    if matches(path, INFRA):
        return "infra"
    if matches(path, TESTS):
        return "test"
    if matches(path, DOCS):
        return "docs"
    return "core"


def parse_diff(text):
    files, cur, new_ln = [], None, 0
    for line in text.splitlines():
        if line.startswith("diff --git "):
            if cur:
                files.append(cur)
            m = re.match(r"diff --git a/(.*?) b/(.*)$", line)
            cur = {"path": m.group(2) if m else "?", "old_path": m.group(1) if m else "?",
                   "status": "modified", "added": [], "removed": []}
            new_ln = 0
        elif cur is None:
            continue
        elif line.startswith("new file mode"):
            cur["status"] = "added"
        elif line.startswith("deleted file mode"):
            cur["status"] = "deleted"
        elif line.startswith("rename from"):
            cur["status"] = "renamed"
        elif line.startswith("@@"):
            m = re.search(r"\+(\d+)", line)
            new_ln = int(m.group(1)) if m else 0
        elif line.startswith("+") and not line.startswith("+++"):
            cur["added"].append((new_ln, line[1:]))
            new_ln += 1
        elif line.startswith("-") and not line.startswith("---"):
            cur["removed"].append((new_ln, line[1:]))
        elif line.startswith(" "):
            new_ln += 1
    if cur:
        files.append(cur)
    return merge_by_path(files)


def merge_by_path(files):
    """A per-commit patch lists the same file once per commit; fold those together."""
    merged = {}
    for f in files:
        prev = merged.get(f["path"])
        if prev is None:
            merged[f["path"]] = f
            continue
        prev["added"].extend(f["added"])
        prev["removed"].extend(f["removed"])
        if prev["status"] == "modified":
            prev["status"] = f["status"]
    return list(merged.values())


def is_comment(text):
    return text.strip().startswith(COMMENT_PREFIXES)


def redact(text):
    """Keys, tokens and hashes end up in memos and PR comments; don't carry them there."""
    return re.sub(r"[A-Za-z0-9+/=_-]{28,}", "<...>", text)


def scan(files):
    hits = defaultdict(list)
    for f in files:
        path, b = f["path"], bucket(f["path"])
        if b == "generated":
            continue
        for key, rung, title, path_re, add_re, rm_re, note in SIGNALS:
            if b in ("test", "docs") and rung != "radius":
                continue  # tests and docs produce no production effect
            if path_re and not re.search(path_re, path):
                continue
            found = []
            if add_re is None and rm_re is None and path_re:
                found.append((0, "(path match)"))
            if add_re:
                for ln, text in f["added"]:
                    if not is_comment(text) and re.search(add_re, text):
                        found.append((ln, redact(text.strip())[:120]))
            if rm_re:
                for ln, text in f["removed"]:
                    if not is_comment(text) and re.search(rm_re, text):
                        found.append((ln, "- " + redact(text.strip())[:118]))
            for ln, sample in found[:3]:
                hits[(key, rung, title, note)].append(
                    {"file": path, "line": ln, "sample": sample, "bucket": b})
        if f["status"] == "deleted" and b == "core":
            hits[("source_deleted", "D4", "source file deleted", "callers outside the diff may still expect it")].append(
                {"file": path, "line": 0, "sample": "(file deleted)", "bucket": b})
    return hits


def deployables(paths):
    out = set()
    for p in paths:
        parts = p.split("/")
        if not parts:
            continue
        head = parts[0]
        if head in ("services", "apps", "cmd", "lambdas", "packages", "plugins") and len(parts) > 1:
            out.add("/".join(parts[:2]))
        elif "." in head:
            out.add("(root)")
        else:
            out.add(head)
    return sorted(out)


def test_line(by_bucket):
    core, tests = by_bucket.get("core", 0), by_bucket.get("test", 0)
    if core and not tests:
        return f"Tests: **none touched** alongside {core} core file(s) — check whether the risky path is covered"
    return f"Tests: {tests} test file(s) touched alongside {core} core file(s)"


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: scan_signals.py <outdir-from-pr_fetch>")
    out = Path(sys.argv[1])
    patch = out / "diff.patch"
    if not patch.is_file():
        sys.exit(f"no diff at {patch} -- run pr_fetch.sh first and pass the outdir it printed")
    diff_text = patch.read_text(errors="replace")
    files = parse_diff(diff_text)
    hits = scan(files)

    by_bucket = defaultdict(int)
    for f in files:
        by_bucket[bucket(f["path"])] += 1
    paths = [f["path"] for f in files]
    shared = [p for p in paths if matches(p, SHARED)]

    durability = {k: v for k, v in hits.items() if k[1] in RUNG_ORDER}
    radius = {k: v for k, v in hits.items() if k[1] == "radius"}
    mitigations = {k: v for k, v in hits.items() if k[1] == "mitigation"}
    max_rung = max((k[1] for k in durability), key=RUNG_ORDER.index, default="D0")

    payload = {
        "files": len(files),
        "buckets": dict(by_bucket),
        "deployables": deployables(paths),
        "shared_files": shared,
        "max_rung": max_rung,
        "signals": [
            {"key": k[0], "rung": k[1], "title": k[2], "note": k[3],
             "count": len(v), "files": sorted({h["file"] for h in v}), "examples": v[:3]}
            for k, v in sorted(hits.items(), key=lambda kv: (
                RUNG_ORDER.index(kv[0][1]) if kv[0][1] in RUNG_ORDER else -1), reverse=True)
        ],
    }
    (out / "signals.json").write_text(json.dumps(payload, indent=2))

    def table(group, header):
        if not group:
            return [f"\n### {header}\n\n_none matched_"]
        rows = [f"\n### {header}\n", "| rung | signal | files | example |", "|---|---|---:|---|"]
        for k, v in sorted(group.items(), key=lambda kv: (
                RUNG_ORDER.index(kv[0][1]) if kv[0][1] in RUNG_ORDER else 0), reverse=True):
            ex = v[0]
            loc = f"{ex['file']}:{ex['line']}" if ex["line"] else ex["file"]
            sample = "" if ex["sample"] == "(path match)" else ex["sample"]
            rows.append(f"| {k[1]} | {k[2]} | {len({h['file'] for h in v})} | `{loc}` {sample} |")
        return rows

    lines = [
        f"## Review surface",
        "",
        f"{len(files)} files changed — " + ", ".join(f"{n} {b}" for b, n in sorted(by_bucket.items())),
        f"Deployables touched: {', '.join(payload['deployables']) or '(none)'}",
        f"Shared code: {len(shared)} file(s)" + (f" — {', '.join(shared[:5])}" if shared else ""),
        f"Highest durability signal: **{max_rung}**",
        test_line(by_bucket),
    ]
    lines += table(durability, "Durability signals (reversibility leads)")
    lines += table(radius, "Blast-radius signals")
    lines += table(mitigations, "Mitigations visible in the diff")
    lines += [
        "",
        "### Not detectable from a diff",
        "",
        "terraform plan outcomes (replace vs update) · SNS/SQS filter policy effects · per-environment",
        "feature-flag state · migration/deploy ordering · whether a backup restore has been exercised ·",
        "actual traffic volume. Verify these by hand and mark them unproven until deployed.",
        "",
        "_Leads, not verdicts: confirm every hit by reading the code, and treat a clean scan as silence,_",
        "_not as evidence that nothing irreversible is happening._",
    ]
    print("\n".join(lines))
    print(f"\nwrote {out / 'signals.json'}")


if __name__ == "__main__":
    main()
