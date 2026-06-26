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

- **Default to none**: code, identifiers, types, and tests are the primary documentation. Do not restate what the code already says.
- **Justify or delete**: add a comment only when you can name the specific wrong conclusion a reader would draw without it (a hidden constraint, a subtle invariant, a non-trivial rationale, or a workaround). If you cannot state that wrong conclusion in one sentence, do not write the comment.
- **"Why" is not a license**: if the rationale is recoverable from the code, types, test names, or commit message, put it there, not in a comment.
- **Self-contained**: a comment must be understandable on its own, without chasing external context (story IDs, ticket numbers, caller names, prior conversations).
- **External links are optional context only**: a link to a spec, bug, or discussion may be included as *additional* history reference, but the comment must still stand on its own without it.
