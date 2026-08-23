# Tooling Guidelines

## Code Structure Analysis
- **Go — use gopls, not text search**, for symbol questions: where a symbol is used, what calls it, its type, renames. gopls is opt-in per repo, so try the deferred tools first — `mcp__gopls__*` and `LSP` in one `ToolSearch` call. References: `mcp__gopls__go_symbol_references` (name-addressed, no line/char needed). Definition, type, docs: `LSP goToDefinition`, `LSP hover`.
- If those tools are absent the repo has not opted in — large monorepos are excluded on purpose, since a long-lived gopls per session exhausts the macOS file table. Use the gopls CLI instead: it needs no server and exits straight away, so it costs nothing to leave unregistered. `gopls references <file>:<line>:<col>`, `gopls definition`, `gopls call_hierarchy`. Still prefer this over `rg`.
- Other languages: `ast-grep -p '<pattern>' --lang=<language>` for syntax-aware matching
- Avoid text-only tools (`rg`, `grep`) unless explicitly requested
- `rg` and `ast-grep` match text and syntax, not **identity** — both match prefixes of the name you asked about, and hits inside comments and strings. Only gopls resolves the actual symbol.
- If gopls returns suspiciously few results, or "no package metadata for file", in a repo whose tests are build-tagged, check that GOFLAGS carries the tags. It fails silently — confidently short answers, no error.

## File Operations
- Finding files: `fd`
- Finding text/strings: `rg`
- Selecting from results: pipe to `fzf`
- JSON manipulation: `jq`
- YAML/XML manipulation: `yq`
- Copying/restoring: never bare `cp`/`mv` onto a path that already exists — prezto's `safe-ops` aliases `cp`, `mv`, `rm` and `ln` to `-i`, and the overwrite prompt has no reader in a non-interactive shell, so the call hangs until the tool timeout kills it and the operation silently never happens. To put back a file you mutated, use `git checkout -- <file>` — it needs no backup copy at all. When a real copy or move is needed, use `/bin/cp -f` / `/bin/mv -f`.

# Go Test Organization

- **One umbrella test per type**: a single `Test{TypeName}` function wraps all scenarios for that type.
- **Group by operation with `t.Run`**: inside the umbrella, group scenarios by the operation under test (e.g. `t.Run("create", ...)`, `t.Run("list", ...)`, `t.Run("rename", ...)`, `t.Run("delete", ...)`). Do not name groups after method signatures.
- **Scenario subtests describe behaviour**: nested `t.Run` names read as full sentences about the observed outcome (e.g. `"rejects duplicate name case-insensitively"`, `"unknown ID returns not-found error"`), not implementation details.
- **Assertions use `testify/require`**: import `github.com/stretchr/testify/require` and assert with `require.NoError`, `require.Equal`, `require.Contains`, `require.True(errors.Is(...))`, etc. Do not hand-roll `if err != nil { t.Fatalf(...) }` chains.
- **Each subtest is independent**: construct fresh fixtures (service, repo, etc.) inside every leaf subtest — no shared mutable state between scenarios.

# Comment Usage

- When writing or editing code, follow `~/.config/ai/guidelines/comments.md`: default to no comments; add one only when you can name the specific wrong conclusion a reader would draw without it. Read that guideline (it's short) before adding any non-trivial comment.


# Document Creation

- When asked to create a document (proposal, notes, report, analysis write-up, diagram source) and no destination is given, create it under `./.scratches/` in the current repo. Group related files in a purpose subfolder (skills use `./.scratches/<skill-name>/<slug>/`).
- Write elsewhere only when the user names a location, or the document is clearly part of the repo's committed documentation (README, `docs/` pages).
