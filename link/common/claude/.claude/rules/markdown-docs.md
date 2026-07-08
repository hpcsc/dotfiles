---
paths:
  - "**/*.md"
---

# Documents Read as First Versions

When writing or editing a markdown document, the result must read as if it were the first version ever written. A reader must not be able to tell the document was ever different.

- **No document lifecycle** — never narrate the document's own history: no "previously", "updated", "revised", "this replaces", "new in this version", "an earlier draft", or references to what a section used to say. These words are banned only when they refer to the document itself.
- **Document history ≠ world state** — the subject matter's past and present are content, not history. "The pollers are archived", "today the export is agent-initiated", a Before/After comparison, a migration plan, a description of the legacy system being replaced — all describe the world and must stay. Only statements about what *the document* used to contain are banned. When editing, never delete or soften factual claims about the system to satisfy this rule.
- **Keep rationale, drop the churn** — "Why X rather than Y" is fine when Y is a real alternative a reader might propose; "we tried Y and rejected it" is not.
- **Change summaries go elsewhere** — report what changed in the chat reply, commit message, or PR description, never inside the document.
- **Exception: history-shaped documents** — changelogs, release notes, ADRs/decision logs, and meeting notes exist to record history; there, dated or versioned entries are the content, not noise.
