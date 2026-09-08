# Comment Usage

Well-named identifiers, clear structure, and tests are the primary documentation. Comments are a last resort, not a habit. Default to writing **none**.

## The rule

Two things must both be true. If either fails, there is no comment.

**1. You can name the edit.** Not a misunderstanding — an edit: the concrete change a competent reader would make, and what breaks when they make it. "A reader might not realise X" does not count. Anyone can imagine a reader not realising anything, which is why that test passes almost everything ever written. "A reader deletes this retry and the cold-start 429s come back" is an edit.

**2. The code cannot be made to say it.** Ask what would carry the reason instead — a rename, a tighter type, a smaller function, a test named after it. If any of them would, do that and write no comment; the reader is already in the code and does not have to be sent anywhere. A comment is only what is left when nothing in the code *can* hold the fact: it belongs to a system you do not control (an upstream's behaviour, a dependency's bug, the platform), or it is a contract the language has no way to state (a lock discipline, an ordering across calls, an invariant spanning files).

This is not about where the fact sits. `// caller must hold mu` is about code in this repo, and survives — no signature can say it. `// the priority order is chain before address` is also about code in this repo, and fails — the slice below says it already.

Most rationale fails this test. Why a call is ordered this way is nearly always sayable in code; why only one retry is allowed nearly never is. The first is a refactor. Only the second is a comment.

One such fact and one edit take one sentence to state. A paragraph means you have several facts, and the code can say the rest of them.

The burden of proof is on keeping a comment, never on removing one. When unsure, remove it.

## What survives it

- `// retry once: the upstream API returns 429 on cold start`
  *Edit:* a reader deletes the retry. *Unsayable:* the upstream's behaviour is not ours to encode.
- `// caller must hold mu`
  *Edit:* a reader calls this without the lock. *Unsayable:* no Go signature carries it.
- `// works around go-yaml#123: empty maps marshal as null`
  *Edit:* a reader "simplifies" it back. *Unsayable:* the bug is in a dependency.

## What fails it

Each of these passes the weaker "a reader might misunderstand" test, which is why they get written:

- `// customerID is the customer this conversation is placed on, which only an identification names.` — no edit to name, and the events already say who writes the field.
- `// messageOrder keeps the arrival order the map cannot.` — there is an edit here (someone drops it back to a map), but the code can say it: name the field `arrivalOrder` and the comment is gone.
- `// Priority order: message-id chain before sender address.` — the priority order is the order of the slice three lines below.
- `// InboundMessageStrategies identifies the sender of a message delivered into a conversation.` — the declaration, again, in a full sentence.

## Never, even when both hold

The fact may be real and still belong somewhere else:

| Anti-pattern | Example |
|---|---|
| **Narrates the current task, fix, or PR** — the commit message carries it, and ages with it | `// added for the email-classify flow`; `// fix for ticket APP-1234` |
| **Names code by its plan position, not its role** — plan artifacts a reader of the merged code cannot see | `// reactor 1 decides, reactor 2 drafts`; `// the decide leg`; `// per design note f`; `// PR 5 wiring` |
| **Leans on a ticket, document, or caller** — it rots when they move, and the reader cannot open them from here | `// see PROJ-99`; `// used by EmailReactor`; `// keep in sync with the proposal` |
| **A package or file doc comment** — remove it even where the language tolerates one | `// Package inboundreply drafts replies…` |

An external link is fine as *additional* history, but the comment must stand on its own without following it.

## How to write the one that survives

A comment is technical writing, so write it in Simplified Technical English (`writing/asd-ste100.md`). Those rules are what keep a comment short — no line count can, because a line count only truncates a sentence that was built wrong.

- **One sentence, active voice, twenty words.** `// the upstream returns 429 on cold start` — not `// it has been observed that cold starts can result in 429s being returned by the upstream`.
- **Plain words.** Use *use*, not *utilize*; *check*, not *verify*; *stop*, not *suppress*; *before*, not *prior to*; *to*, not *in order to*.
- **Simple present, and no `-ing` forms.** `// the reactor opens the case, then sends the request` — not `// after opening the case, the reactor has sent the request`.
- **`must` and `can` only.** `// callers must hold mu` — never *should*, *may*, or *might*, which leave a reader guessing whether the rule is a rule.
- **No metaphors.** `// the schedule sends the message at the deadline` — not `// the deadline fires and the case is welded to one outcome`.
- **One word for one thing.** If the code calls it a `hold`, the comment calls it a hold — never a snooze, a block, or a pause.

Most over-long comments are one fact wrapped in these habits. `// judgeExpectations records what the judge made of the reply. An attempt that never drafted has no reply to rule on, so its expectations stay unrecorded rather than counted as missed.` is three sentences and a passive; the fact in it is `// an attempt with no reply has no expectations to record`.

Identifiers, event names, field names and paths are technical names. Spell them exactly as the code does.

## How to apply while writing

The cheapest comment to remove is the one never written, so run the test before typing, not over the diff afterwards.

Reach for a comment and stop. Name the edit first, out loud. If no edit comes, there is nothing to write — move on. If one comes, ask what could carry the reason instead: a rename, a tighter type, a smaller function, a test named after it. If any of them could, do that and write no comment. Only what survives both gets typed, in the form above.

Write the file with no comments and add one back only where a reader would trip. Do not write it commented and thin it out later — the second pass keeps whatever reads plausibly, and everything above reads plausibly.

## How to apply during review or refactor

For every new or modified comment in the diff:

1. Name the edit it prevents, and what breaks. If you cannot — remove it.
2. Name what could carry the reason instead — a rename, a tighter type, a smaller function, a test name, the commit message. If anything could, remove the comment and do that.
3. Confirm it stands alone, with no ticket or document as its only content. Otherwise remove it.
4. Read what is left against *How to write the one that survives*: one active sentence, plain words, no `-ing`, no metaphor.

Then read the file whole. If the comments are the first thing you notice, the test was applied loosely — go back to step 1 for each of them.
