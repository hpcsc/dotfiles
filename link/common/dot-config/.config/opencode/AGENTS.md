# Tooling Guidelines

## Code Structure Analysis
- Use `ast-grep -p '<pattern>' --lang=<language>` for syntax-aware matching
- Avoid text-only tools (`rg`, `grep`) unless explicitly requested

## File Operations
- Finding files: `fd`
- Finding text/strings: `rg`
- Selecting from results: pipe to `fzf`
- JSON manipulation: `jq`
- YAML/XML manipulation: `yq`

# Go Test Organization

- **One umbrella test per type**: a single `Test{TypeName}` function wraps all scenarios for that type.
- **Group by operation with `t.Run`**: inside the umbrella, group scenarios by the operation under test (e.g. `t.Run("create", ...)`, `t.Run("list", ...)`, `t.Run("rename", ...)`, `t.Run("delete", ...)`). Do not name groups after method signatures.
- **Scenario subtests describe behaviour**: nested `t.Run` names read as full sentences about the observed outcome (e.g. `"rejects duplicate name case-insensitively"`, `"unknown ID returns not-found error"`), not implementation details.
- **Assertions use `testify/require`**: import `github.com/stretchr/testify/require` and assert with `require.NoError`, `require.Equal`, `require.Contains`, `require.True(errors.Is(...))`, etc. Do not hand-roll `if err != nil { t.Fatalf(...) }` chains.
- **Each subtest is independent**: construct fresh fixtures (service, repo, etc.) inside every leaf subtest — no shared mutable state between scenarios.

# Comment Usage

- **No obvious comments**: do not restate what the code already says. Well-named identifiers and clear structure are the primary documentation.
- **Only when necessary**: add a comment only to explain something that is not obvious from the code itself — a hidden constraint, a subtle invariant, a non-trivial rationale, or a workaround.
- **Self-contained**: a comment should be understandable on its own, without requiring the reader to chase external context (story IDs, ticket numbers, caller names, prior conversations).
- **External links are optional context only**: a link to a spec, bug, or discussion may be included as *additional* history reference, but the comment must still stand on its own without it.
