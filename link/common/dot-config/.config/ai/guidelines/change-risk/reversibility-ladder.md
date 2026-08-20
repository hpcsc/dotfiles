# The durability ladder

Grade every effect on this ladder. The rung is set by **what survives a revert**,
not by how big the diff is or how hard the code was to write.

The PR's verdict is the **worst rung any single effect reaches**. Note how many
effects sit there — "one D5, everything else D0" is a precise and useful statement,
and it points straight at what to split out.

---

## D0 — In-process behaviour

Pure computation. No persistence, no messages, no outbound calls, no contract change.
Refactors, internal renames, log wording, added validation on a path that already
rejected the input another way.

- **Revert restores:** everything.
- **Time to undo:** one deploy.
- **Verdict:** two-way door.

## D1 — Recoverable state

State written where the prior value is still knowable and rewritable: a mutable row,
a cache, a derived projection rebuildable from its source of truth, a config value.

- **Revert restores:** the code. State is repairable by rewrite or rebuild.
- **Time to undo:** deploy + a rebuild or corrective write.
- **Ask:** is the *prior* value still recoverable, or did we overwrite it in place
  with no history? An in-place overwrite of the only copy is not D1, it is D5.
- Additive migrations (`ADD COLUMN`, `CREATE TABLE`, a new index) are D1: dropping
  them back out is mechanical. Note that a long `CREATE INDEX` may lock, which is a
  blast-radius problem, not a reversibility one.

## D2 — Append-only state

Written into something that does not support unwriting: an event store, an audit
log, an outbox, a queue whose messages have been consumed, an analytics stream, an
immutable object store.

- **Revert restores:** nothing already written. It only stops new writes.
- **This is a ratchet.** Every future replay, rebuild and backfill will see those
  records forever, so **every future consumer must tolerate the shape you just
  introduced** — that is the real cost, and it is permanent.
- **Time to undo:** the code, one deploy. The records, never — only superseding
  events, tombstones or an ignore-rule in the consumers.
- **Ask:** does the system replay history (event sourcing, projection rebuild,
  reprocessing)? If yes, a badly shaped record is a permanent tax on every consumer.
  Is the name right? Event and field names written once are effectively contracts.
- Delivery semantics belong here: at-least-once delivery plus a non-idempotent
  handler means the effect can happen more than once — and a retry storm during the
  incident is exactly when it will.

## D3 — Externalised effects

It left the building. Email or SMS delivered, push sent, webhook posted, payment
captured or refunded, file dropped on a client's SFTP, record created in a vendor's
system, message posted to a customer-visible thread.

- **Revert restores:** nothing. There is no unsend.
- **Only compensation exists:** correction message, apology, refund, manual repair —
  each with its own cost, and often its own approval chain.
- **Time to undo:** not applicable. Price it as *rate × detection latency* instead:
  how many go out per minute, and how long before someone notices.
- **Ask:** who is the recipient — internal staff, a client, or an end customer? The
  further out, the higher the true cost of the same bug. Is there a rate limit, a
  quota, a batch size, or does one bad deploy drain the whole queue at full speed?
- **A cheap-to-revert PR with a D3 effect is a one-way door.** This is the most
  commonly under-graded rung; do not let a small diff talk you out of it.

## D4 — Contracts and expectations

Something other people now build against: a published API response shape, an event
schema another team consumes, a queue message format, a URL, an ID or key format,
a field name in a client-facing export or a dashboard, a behaviour customers have
started to rely on.

- **Revert restores:** your code, and breaks their integration.
- **Time to undo:** as long as coordination takes — notice periods, other teams'
  release cycles, sometimes client contracts. Weeks, not deploys.
- **Ask:** who consumes it *today*, and who will by the time we would want it back?
  Is it additive (new optional field — usually D1/D2) or does it remove, rename,
  narrow, or change the meaning of something (D4)? Expand-contract makes most of
  these two-way: add the new alongside the old, migrate consumers, delete later.
- **The door closes with time.** Merge day: two-way, nobody depends on it. After the
  first consumer integrates: one-way. Always state the horizon.

## D5 — Destroyed information

The prior state no longer exists anywhere you can reach.

`DROP TABLE` / `DROP COLUMN` / `TRUNCATE` / `DELETE FROM`, an in-place overwrite of
the only copy, an object or bucket deletion, a Terraform change that forces
replacement of a stateful resource, deleting a queue holding in-flight messages,
rotating or revoking a credential still in use, a destructive one-shot backfill.

- **Revert restores:** nothing. Undo requires a backup, and the backup is a claim
  until someone has restored from it.
- **Time to undo:** hours to days, if it is possible at all.
- **Ask, before merging:** does a backup exist, when was a restore last *exercised*,
  what is the RPO, and is the destructive step separable from the rest of the PR?
  Nearly always it is — and splitting it is the single highest-value merge condition
  this skill can produce.
- Terraform deserves specific care: a changed `name`/`identifier` on a stateful
  resource is a destroy-and-create, and the plan says so. If nobody has read a plan,
  the rung is unproven, not low.

---

# Revert-hostile patterns

Independent of rung, these turn "just revert it" into an incident of its own. Call
them out by name when present.

- **Migration and code in one deploy** — the revert puts old code on a new schema.
  Ask whether the previous release runs against the migrated database. If not, the
  revert path does not exist and the only way out is forward.
- **Expand-contract violated** — old and new shapes are not simultaneously valid, so
  neither deploy order is safe and rollback breaks whatever already moved.
- **Producer/consumer ordering** — the consumer must ship before the producer (or
  vice versa). Name the required order and say whether the intermediate state is
  valid, because that intermediate state *will* exist for real minutes.
- **Non-idempotent handler on at-least-once delivery** — a redrive or retry does the
  effect again; the more urgent the incident, the more retries.
- **Dual writes without a source of truth** — reverting one side leaves the two
  permanently disagreeing, with no rule for which wins.
- **One-shot job already run** — backfills, repair scripts, imports. Reverting the
  code does not un-run it; ask what a *second* run does, since that is what happens
  after a revert-and-reapply.
- **Deleted feature flag** — removing the flag along with the old path removes the
  cheap undo. Landing the flag removal in the same PR as the behaviour change is
  the classic way a two-way door quietly becomes one-way.
- **State written by the new code that the old code cannot read** — forward-only
  data with backward-incompatible readers.

---

# Time-to-undo reference

| Undo mechanism | Realistic TTU | Preconditions |
|---|---|---|
| Feature flag / config flip | seconds–minutes | flag exists, defaults safe, flip needs no deploy |
| Revert + deploy | one pipeline run | no schema/contract coupling; the previous release still runs |
| Revert + data repair | hours–days | repair is written, tested, and reviewable |
| Restore from backup | hours–days, uncertain | backup exists and a restore has been exercised |
| Coordinate with consumers | weeks | you know who they are and can reach them |
| Compensate externally | not undo | the effect stands; you pay for it |

Report the **cheapest mechanism that actually applies to this PR**, and say what
would have to be true for the cheaper one above it to apply. That gap is usually the
merge condition worth asking for.
