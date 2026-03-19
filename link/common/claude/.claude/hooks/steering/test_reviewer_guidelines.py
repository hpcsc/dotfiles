"""Tests for reviewer guideline steering hook."""

from steering.reviewer_guidelines import (
    REVIEWER_GUIDELINES,
    build_steering_message,
    handle,
)


class TestHandle:
    def test_non_reviewer_agent_passes_through(self):
        assert handle({"agent_type": "go-implementer"}) == {}

    def test_empty_input_passes_through(self):
        assert handle({}) == {}

    def test_reviewer_without_guidelines_passes_through(self):
        assert handle({"agent_type": "security-reviewer"}) == {}
        assert handle({"agent_type": "performance-reviewer"}) == {}
        assert handle({"agent_type": "concurrency-reviewer"}) == {}
        assert handle({"agent_type": "go-mutation-reviewer"}) == {}

    def test_go_semantic_reviewer_injects_two_guidelines(self):
        result = handle({"agent_type": "go-semantic-reviewer"})
        ctx = result["additionalContext"]
        assert "caller-patterns.md" in ctx
        assert "go/testing-patterns.md" in ctx

    def test_go_guidelines_reviewer_injects_three_guidelines(self):
        result = handle({"agent_type": "go-guidelines-reviewer"})
        ctx = result["additionalContext"]
        assert "naming-patterns.md" in ctx
        assert "architecture-principles.md" in ctx
        assert "development-workflow.md" in ctx

    def test_go_concurrency_reviewer_injects_one_guideline(self):
        result = handle({"agent_type": "go-concurrency-reviewer"})
        ctx = result["additionalContext"]
        assert "concurrency-patterns.md" in ctx

    def test_semantic_reviewer_injects_language_agnostic_guidelines(self):
        result = handle({"agent_type": "semantic-reviewer"})
        ctx = result["additionalContext"]
        assert "testing/caller-patterns.md" in ctx
        assert "testing/patterns.md" in ctx

    def test_message_includes_agent_type(self):
        result = handle({"agent_type": "go-test-reviewer"})
        assert "@go-test-reviewer" in result["additionalContext"]

    def test_message_includes_must_read_instruction(self):
        result = handle({"agent_type": "go-test-reviewer"})
        assert "MUST read" in result["additionalContext"]


class TestBuildSteeringMessage:
    def test_contains_all_guideline_paths(self):
        msg = build_steering_message("test-reviewer", ["a.md", "b.md"])
        assert "a.md" in msg
        assert "b.md" in msg

    def test_contains_agent_name(self):
        msg = build_steering_message("go-semantic-reviewer", ["a.md"])
        assert "@go-semantic-reviewer" in msg


class TestGuidelineMapCompleteness:
    """Verify every mapped reviewer has at least one guideline."""

    def test_all_entries_have_guidelines(self):
        for agent, guidelines in REVIEWER_GUIDELINES.items():
            assert len(guidelines) > 0, f"{agent} has empty guideline list"
            for g in guidelines:
                assert g.endswith(".md"), f"{agent}: {g} is not a .md file"
