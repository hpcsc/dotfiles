"""Steering hook: enforce guideline reading for reviewer agents.

SubagentStart hook. When a reviewer subagent starts, injects additionalContext
listing the exact guideline files the reviewer MUST read before analyzing any diff.

Guideline map is the single source of truth — add new reviewers here.
"""

from __future__ import annotations

import json
import os
import sys

GUIDELINES_HOME = os.path.expanduser("~/.config/ai/guidelines")

# Map reviewer agent types to their required guideline files (relative to GUIDELINES_HOME).
# Reviewers not listed here pass through silently.
REVIEWER_GUIDELINES: dict[str, list[str]] = {
    "go-semantic-reviewer": [
        "testing/caller-patterns.md",
        "go/testing-patterns.md",
    ],
    "go-concurrency-reviewer": [
        "go/concurrency-patterns.md",
    ],
    "go-performance-reviewer": [
        "go/performance-patterns.md",
    ],
    "go-guidelines-reviewer": [
        "go/naming-patterns.md",
        "go/architecture-principles.md",
        "go/development-workflow.md",
    ],
    "go-test-reviewer": [
        "testing/caller-patterns.md",
        "go/testing-patterns.md",
    ],
    "semantic-reviewer": [
        "testing/caller-patterns.md",
        "testing/patterns.md",
    ],
    "test-reviewer": [
        "testing/caller-patterns.md",
        "testing/patterns.md",
    ],
}


def build_steering_message(agent_type: str, guidelines: list[str]) -> str:
    file_list = "\n".join(f"  - {os.path.join(GUIDELINES_HOME, g)}" for g in guidelines)
    return (
        "STEERING RULE — Required Reading Before Review\n"
        "\n"
        f"You are @{agent_type}. Before analyzing any diff or code, "
        "you MUST read these guideline files first:\n"
        "\n"
        f"{file_list}\n"
        "\n"
        "Read each file using the Read tool (or cat via Bash). "
        "Do NOT skip this step. Do NOT start reviewing until you have read ALL "
        "listed files. Your review quality depends on applying these guidelines "
        "— reviewers that skip them produce shallow, generic findings.\n"
        "\n"
        "After reading, proceed with your normal review process."
    )


def handle(hook_input: dict) -> dict:
    """Process SubagentStart hook input, return JSON-serializable response."""
    agent_type = hook_input.get("agent_type", "")

    if not agent_type.endswith("-reviewer"):
        return {}

    guidelines = REVIEWER_GUIDELINES.get(agent_type)
    if not guidelines:
        return {}

    message = build_steering_message(agent_type, guidelines)
    return {"additionalContext": message}


def main() -> None:
    try:
        raw = sys.stdin.read()
        hook_input = json.loads(raw) if raw.strip() else {}
        result = handle(hook_input)
        if result:
            print(json.dumps(result))
    except Exception:
        pass  # Fail-open: never block agent startup
    sys.exit(0)


if __name__ == "__main__":
    main()
