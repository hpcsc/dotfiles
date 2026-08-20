# Blast-radius lenses

Six lenses. Run all of them; a lens with nothing to say gets one line saying so.
Size the radius as **exposed population × exposure window**, never as a t-shirt
label alone — "all customers" on a synchronous request path and "all customers" on
a nightly job are different orders of magnitude of exposure.

---

## 1. Code fan-out — what else runs this code

The diff shows what changed. The radius is what *depends* on it.

- For every changed exported symbol, find the callers, not the file. Prefer a
  symbol-aware tool (`gopls references`, LSP, `ast-grep`) over text search: text
  matches prefixes, comments and strings, and will both over- and under-count.
- Changes under shared paths (`common/`, `pkg/`, `lib/`, `internal/shared/`) fan out
  to every consumer in the repo. Count the importers and name the surprising ones —
  the surprising importer is the whole point of this lens.
- Changed behaviour of an existing function is wider than a new function nobody
  calls yet. A new unused symbol has a radius of zero and should be said to.
- Note when a change is behind an interface with multiple implementations, or in a
  base template/layout that renders everywhere.

State: *N direct callers, M transitively, across K deployables* — or "leaf, one
caller" when that is the answer.

## 2. Deploy surface — what ships, where, when

- Which deployables carry this change: services, lambdas, workers, frontends, jobs.
- Which environments and regions, and in what order. A change deploying to every
  region at once has no natural canary; one region first is a control you may already
  have for free.
- What runs *at deploy time*: migrations, `terraform apply`, cron registration,
  one-shot backfills, cache or config invalidation.
- Does anything outside the repo need to move with it — a client, another team's
  service, a vendor configuration, a manual step in a runbook?
- Is the deploy itself risky independent of the code — long lock, resource
  replacement, capacity change, a stack near a hard platform limit?

## 3. Traffic and population — who actually meets it

- **What fraction of traffic traverses the changed path?** Gated or ungated, and by
  what: feature flag, client allowlist, country, mailbox, percentage rollout, an
  `if` on a field that is rarely set. An ungated path on a live route is 100% — that
  is derived from code, and worth saying explicitly rather than implying.
- **Which population:** end customers, clients, internal agents, only engineers.
  Radius grows sharply with distance from the team, because reach and remedy cost
  scale together.
- **Volume, with a basis.** Measured is best (`--measure`: the repo's own datalake,
  log or queue tooling). Derived from code is fine when labelled. Estimated must say
  estimated. Never invent a number and never present an estimate as a measurement.
- **Rate matters more than total** for anything on D3 of the ladder: how many
  irreversible effects per minute while it is wrong.
- Is the exposure continuous (every request) or episodic (a nightly batch, a monthly
  statement run)? Episodic exposure can be huge but has a natural pause between
  windows — a real and often overlooked control.

## 4. Failure mode and loudness — how it breaks

- **Fail-closed** — it throws, retries, dead-letters, 500s. Loud, bounded, usually
  recoverable. The work queues up rather than going out wrong.
- **Fail-open** — it proceeds with wrong data, wrong recipient, wrong amount, wrong
  decision, or silently skips work. Quiet, unbounded, and the residue accrues the
  whole time.
- **Partial failure** — some records processed, some not, no record of which. Ask
  what resuming does, since resuming is what will happen.
- The quadrant to escalate on is **silent + irreversible**: a fail-open path whose
  effects sit at D2 or above. That combination is worth stopping a merge for even
  when likelihood is low.
- Ask what happens under *load* and under *retry*: at-least-once delivery plus a
  non-idempotent effect means the incident multiplies its own damage.

## 5. Detection — how fast anyone finds out

- What already exists that would catch this: alarms, DLQs, error-rate monitors,
  dashboards, scheduled reconciliation, a daily report, a customer complaining.
- **Estimate a time-to-detect** and say where it comes from. Minutes for an alarmed
  fail-closed path; hours for a daily report; never, for a silent wrong value nobody
  reconciles.
- Multiply it out: `effect rate × time-to-detect` is the residue you would be living
  with. Put the arithmetic in the memo — it converts an abstract worry into a number
  people can argue with, which is exactly what you want.
- **A change with no detection path is the headline finding**, above every other
  observation in the memo. Adding one alarm is usually the cheapest merge condition
  available and often lowers the effective risk more than any code change in review.

## 6. Coupling and partial-deploy states

- Is the change atomic, or does it need an ordered sequence across repos, services
  or teams? Name the order.
- Is the **intermediate state valid**? During a rolling deploy both versions run at
  once; during a multi-PR sequence the intermediate state is production for real
  minutes or days. If it is not valid, that is a finding regardless of how correct
  each end state is.
- Does a rollback of *this* PR alone leave the system consistent, or does it require
  reverting the others too? A revert that requires coordination is not a revert.
- Are there in-flight messages, open sessions, scheduled jobs or long-running
  workflows that started under the old code and will finish under the new one — or
  the reverse, after a rollback?
- Does the change alter a shared limit — concurrency, batch size, visibility timeout,
  connection pool, rate limit — where the effect lands on *other* workloads that
  share it? That is radius outside the diff entirely, and nobody else will look for it.
