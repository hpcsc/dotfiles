# Comment Usage

Well-named identifiers and clear structure are the primary documentation. Comments are a last resort, not a habit.

## The rule

Default to writing **no comments**. Only add one when the **why** is non-obvious — a hidden constraint, a subtle invariant, a non-trivial rationale, or a workaround for a specific bug. If removing the comment would not confuse a future reader, do not write it.

## What to flag

A comment violates this guideline if any of the following is true:

| Anti-pattern | Example |
|---|---|
| **Restates the code** — the identifier already says it | `// increment counter` above `counter++`; `// returns the user` above `return user` |
| **Narrates the current task, fix, or PR** — belongs in the commit message, not the source | `// added for the email-classify flow`; `// fix for ticket APP-1234`; `// removed the old branch` |
| **References callers or ticket IDs as the only justification** | `// used by EmailReactor`; `// see PROJ-99` (without standalone reasoning) |
| **Godoc on unexported symbols where the logic isn't subtle** | `// userRepo persists users.` on an obvious type |
| **Removable without loss** — strip it, and a reader picks up the same meaning from the code | most one-line comments above well-named functions |

External links to a spec, bug, or discussion are fine as *additional* history reference, but the comment must still stand on its own without them.

## What is fine to keep

- A note explaining **why** a non-obvious branch exists ("retry once because the upstream API returns 429 on cold start").
- A pointer to a hidden invariant the type system can't express ("caller must hold mu").
- A workaround marker that says what the workaround is for ("works around go-yaml#123: empty maps marshal as null").

## How to apply during review or refactor

1. For every new or modified comment in the diff, ask: *would a reasonable reader understand the code with this comment removed?*
2. If yes — flag/remove.
3. If no — keep, but check it is self-contained (no "see ticket X" as the sole content).
