"""Steering hook: validate git commit messages.

PostToolUse hook on Bash. After a successful `git commit`, inspects the commit
message for rule violations and injects additionalContext with fix instructions.

Rules are defined as a list of check functions — add new rules by appending.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys

# Past-tense verbs mapped to their imperative form.
PAST_TO_IMPERATIVE: dict[str, str] = {
    "Added": "Add",
    "Fixed": "Fix",
    "Updated": "Update",
    "Changed": "Change",
    "Removed": "Remove",
    "Deleted": "Delete",
    "Moved": "Move",
    "Renamed": "Rename",
    "Refactored": "Refactor",
    "Merged": "Merge",
    "Implemented": "Implement",
    "Created": "Create",
    "Resolved": "Resolve",
    "Improved": "Improve",
    "Optimized": "Optimize",
}

AI_PATTERNS = re.compile(
    r"claude|anthropic|ai.generated|ai.assisted|generated.by.ai|llm",
    re.IGNORECASE,
)

CO_AUTHORED_PATTERN = re.compile(r"co-authored-by", re.IGNORECASE)


def check_subject_length(subject: str, _body: str) -> str | None:
    if len(subject) > 50:
        return f'Subject line is {len(subject)} chars (max 50): "{subject}"'
    return None


def check_ai_mention(_subject: str, body: str) -> str | None:
    match = AI_PATTERNS.search(body)
    if match:
        line = next(l for l in body.splitlines() if AI_PATTERNS.search(l))
        return f'AI/Claude mention found: "{line.strip()}"'
    return None


def check_co_authored_by(_subject: str, body: str) -> str | None:
    if CO_AUTHORED_PATTERN.search(body):
        return "Co-Authored-By signature found (forbidden)"
    return None


def check_imperative_mood(subject: str, _body: str) -> str | None:
    first_word = subject.split()[0] if subject.split() else ""
    imperative = PAST_TO_IMPERATIVE.get(first_word)
    if imperative:
        return (
            f'Subject uses past tense "{first_word}" '
            f'— use imperative mood (e.g., "{imperative}")'
        )
    return None


def check_trailing_period(subject: str, _body: str) -> str | None:
    if subject.endswith("."):
        return "Subject line ends with a period (remove it)"
    return None


def check_capitalization(subject: str, _body: str) -> str | None:
    if subject and subject[0].islower():
        return "Subject line starts with lowercase (capitalize it)"
    return None


# Ordered list of all checks. Each takes (subject, full_body) and returns a
# violation string or None.
CHECKS = [
    check_subject_length,
    check_ai_mention,
    check_co_authored_by,
    check_imperative_mood,
    check_trailing_period,
    check_capitalization,
]


def get_last_commit_message(cwd: str | None) -> str | None:
    """Read the most recent commit message from the git repo at cwd."""
    try:
        cmd = ["git", "log", "-1", "--format=%B"]
        if cwd:
            cmd = ["git", "-C", cwd, "log", "-1", "--format=%B"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except Exception:
        pass
    return None


def validate_commit_message(commit_msg: str) -> list[str]:
    """Run all checks against a commit message. Returns list of violation strings."""
    subject = commit_msg.splitlines()[0] if commit_msg else ""
    violations = []
    for check in CHECKS:
        violation = check(subject, commit_msg)
        if violation:
            violations.append(violation)
    return violations


def build_steering_message(subject: str, violations: list[str]) -> str:
    bullet_list = "\n".join(f"- {v}" for v in violations)
    return (
        "COMMIT MESSAGE VIOLATION — Fix Required\n"
        "\n"
        "The commit was created but the message violates commit guidelines:\n"
        f"{bullet_list}\n"
        "\n"
        f'Current subject: "{subject}"\n'
        "\n"
        "Action required: Run `git commit --amend` to fix the commit message. "
        "Follow these rules:\n"
        "- Subject line: max 50 chars, imperative mood, capitalized, no period\n"
        "- Never mention AI, Claude, or add Co-Authored-By\n"
        "- Write as a human developer would"
    )


def handle(hook_input: dict) -> dict:
    """Process PostToolUse hook input, return JSON-serializable response."""
    if hook_input.get("tool_name") != "Bash":
        return {}

    command = hook_input.get("tool_input", {}).get("command", "")
    if "git commit" not in command:
        return {}

    response = hook_input.get("tool_response", {})
    if str(response.get("exit_code", "1")) != "0":
        return {}

    cwd = hook_input.get("cwd")
    commit_msg = get_last_commit_message(cwd)
    if not commit_msg:
        return {}

    violations = validate_commit_message(commit_msg)
    if not violations:
        return {}

    subject = commit_msg.splitlines()[0]
    message = build_steering_message(subject, violations)
    return {"additionalContext": message}


def main() -> None:
    try:
        raw = sys.stdin.read()
        hook_input = json.loads(raw) if raw.strip() else {}
        result = handle(hook_input)
        print(json.dumps(result))
    except Exception:
        print("{}")  # Fail-open
    sys.exit(0)


if __name__ == "__main__":
    main()
