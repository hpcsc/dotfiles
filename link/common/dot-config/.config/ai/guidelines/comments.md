# Comment Usage

Well-named identifiers, clear structure, and tests are the primary documentation. Comments are a last resort, not a habit. Default to writing **none**.

## The rule

Write a comment **only** when you can name the specific wrong conclusion a competent reader would draw from the code alone — and the comment exists to prevent exactly that. If you cannot state that wrong conclusion in one plain sentence, delete the comment.

"Explaining the why" is **not** a license. Most "why" is already recoverable from the code, the identifiers, the types, the test names, or the commit message — put it there, not in a comment. A why-comment earns its place only when the rationale is invisible at the point of use **and** a reader would otherwise make a wrong change (delete a guard, reorder a call, loosen a bound).

The burden of proof is on keeping a comment, never on removing one. When unsure, remove it.

## What to flag

A comment violates this guideline if any of the following is true:

| Anti-pattern | Example |
|---|---|
| **Restates the code** — the identifier already says it | `// increment counter` above `counter++`; `// returns the user` above `return user` |
| **Narrates the current task, fix, or PR** — belongs in the commit message, not the source | `// added for the email-classify flow`; `// fix for ticket APP-1234`; `// removed the old branch` |
| **Names code by its plan position, not its role** — plan / PR / design-doc artifacts a reader of the merged code cannot see | `// reactor 1 decides, reactor 2 drafts`; `// the decide leg`; `// the on switch`; `// per design note f`; `// PR 5 wiring` |
| **Explains a why the code, types, tests, or commit already make clear** | `// validate before saving` above an obvious validation call |
| **References callers or ticket IDs as the only justification** | `// used by EmailReactor`; `// see PROJ-99` (without standalone reasoning) |
| **Godoc on unexported symbols where the logic isn't subtle** | `// userRepo persists users.` on an obvious type |
| **Removable without loss** — strip it, and a reader picks up the same meaning from the code | most one-line comments above well-named functions |

External links to a spec, bug, or discussion are fine as *additional* history reference, but the comment must still stand on its own without them.

## What survives the test

Each of these names a concrete wrong conclusion a reader would otherwise reach:

- `// retry once: the upstream API returns 429 on cold start` — without it, a reader deletes the retry.
- `// caller must hold mu` — without it, a reader calls this without the lock.
- `// works around go-yaml#123: empty maps marshal as null` — without it, a reader "simplifies" the workaround and reintroduces the bug.

If a proposed comment does not read like one of these — a named, specific misunderstanding it heads off — it does not survive.

## How to apply during review or refactor

For every new or modified comment in the diff:

1. State, in one sentence, the wrong conclusion a competent reader would draw if the comment were gone.
2. If you cannot — flag/remove it.
3. If you can, confirm that wrong conclusion is not already prevented by the code, types, test names, or commit message — and that the comment is self-contained (no "see ticket X" as its sole content). Otherwise flag/remove.
