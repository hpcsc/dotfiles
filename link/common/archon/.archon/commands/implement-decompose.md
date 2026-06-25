# implement — decompose

You are decomposing a user story into an ordered, codebase-aware task list for an
autonomous test-first implementation pipeline. The story and the target task-file
path arrive under `=== RUNTIME INPUT ===` as `STORY:` and `TASK_FILE:`.

## 1. Detect the language inventory

Check for marker files in the project root — collect **every** match, not just the first:

| Marker file | Language |
|---|---|
| `go.mod` | Go |
| `package.json` | JavaScript/TypeScript |
| `mix.exs` | Elixir |
| `Gemfile` or `*.gemspec` | Ruby |
| `pyproject.toml` / `setup.py` / `requirements.txt` | Python |
| `Cargo.toml` | Rust |
| `*.tf` | HCL |
| (none matched) | Generic / inferred from file extensions |

## 2. Decompose

Explore the affected files, patterns, and domain types, then break the story into
ordered implementation tasks. For each task, decide which **single** language it
primarily involves (from the detected inventory) and whether it delivers
independently testable behavior.

Apply the project testing guidelines to judge whether each task is a real unit of
behavior. Open each only via its Section Index (read line 1 for the `<!-- index: 1-N -->`
range, read the index, then load only the sections you need — never end-to-end):

- `~/.config/ai/guidelines/testing/caller-patterns.md` — "How to Identify the Caller" + Quick Reference.
- Language-specific, when that language is in the inventory:
  - Go → `~/.config/ai/guidelines/go/testing-patterns.md` ("Unit of Behavior").
  - JavaScript/TypeScript → `~/.config/ai/guidelines/javascript/testing-patterns.md` ("Unit of Behavior").
  - Elixir → `~/.config/ai/guidelines/elixir/testing-patterns.md` ("Unit of Behavior").

## 3. Write the task file

Write the task list to the `TASK_FILE` path. Use this structure:

```markdown
# <story title>

Languages detected: [<inventory>]

- [ ] Task 1: <short title>
- [ ] Task 2: <short title>
...

## Task 1: <short title>
- language: <one of the detected languages>
- description: <imperative description>
- behavior: <observable behavior>
- acceptance_criteria:
  - ...
- affected_files:
  - ...
- patterns_to_follow:
  - ...
- testable: <true|false>
```

Each task maps to exactly one cycle in the implementation phase. Order tasks so that
each builds only on already-completed ones.

## Output

After writing the file, print a one-line confirmation: the task-file path and the
number of tasks. Do not start implementing anything.
