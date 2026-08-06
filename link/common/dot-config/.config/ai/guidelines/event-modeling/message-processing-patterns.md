# Message Processing Patterns

Standardized patterns for transitions between commands, events, and state in an event model.

---

## Relationship to the Four Event Modeling Patterns

Event modeling uses four design-level patterns to describe the types of slices in a model:

- **Command**: Trigger → Command → Event(s)
- **View**: Event(s) → View
- **Automation**: Event(s) → Reactor → Command → Event(s)
- **Translation**: External System → View → Command → Event(s)

Message processing patterns are **complementary, not a replacement**. They describe the implementation component behind each arrow/transition within those slices. A single "Automation" slice might use a Reactor, Policy, or Process Manager depending on the complexity. A "Translation" slice might use a Translation pattern plus a Gateway for the return path.

---

## Why Label Patterns Explicitly

After completing an event model, label each transition with its processing pattern. This:
- Ensures consistency across the design
- Maps directly to implementation components
- Makes the model auditable — every arrow has a named pattern behind it
- Helps new team members understand the architecture

---

## The Core Patterns

### 1. Aggregate (Command → Event)

A command handler that makes a business decision, enforces invariants, and records the outcome as one or more events.

```
Command → [Aggregate] → Event(s)
```

**Characteristics:**
- Owns business rules and invariants
- Single source of truth for its consistency boundary
- Rejects invalid commands (returns errors)
- Produces events only on successful decisions

**Example:**
```
PlaceOrder → [Order Aggregate] → OrderPlaced
```

---

### 2. Projection (Event → State/View)

Transforms an event stream into a read-optimized state representation. Users and systems consume projections to make informed decisions.

```
Event(s) → [Projection] → State (View / Read Model)
```

**Characteristics:**
- Purely derived from events — can be rebuilt from scratch
- Optimized for a specific read use case
- Eventually consistent with the event stream
- No side effects, no business decisions

**Example:**
```
OrderPlaced, PaymentSucceeded, OrderShipped → [OrderSummaryProjection] → OrderSummary
```

---

### 3. Reactor / Automation (Event → Command)

Listens for events and automatically issues commands in response. Bridges two slices or processes without human intervention.

```
Event → [Reactor] → Command
```

**Characteristics:**
- Stateless — reacts to individual events
- May read projections to gather context before issuing the command
- Must be safe to run twice — see [Safe to Run Twice](#safe-to-run-twice)
- Does NOT make business decisions — delegates to the aggregate

**Example:**
```
OrderPlaced → [PaymentReactor] → ProcessPayment
```

---

### 4a. Saga (Event → Command, with Compensation)

A coordination pattern for long-lived processes composed of local transactions, each paired with a **compensating action** that semantically undoes its effect if a later step fails. Sagas distribute workflow knowledge — each participant knows only its own step and its own compensation.

```
Event → [Saga step] → Command
(on failure) Event → [Saga step] → Compensating Command
```

**Characteristics:**
- Originally a compensation strategy for long-lived transactions (Garcia-Molina & Salem, 1987)
- Aligns with **choreography**: no central coordinator; each participant reacts to events
- Compensations are new forward-moving events — they *add to* the history, never erase it ("compensation adds to the story; rollback pretends part of the story never happened")
- Best fit: simple, stable, largely linear workflows with well-defined compensations

**Example:**
```
OrderPlaced      → [Payment step]  → ChargePayment
PaymentSucceeded → [Shipping step] → ShipOrder
ShipmentFailed   → [Payment step]  → RefundPayment   (compensating command)
```

---

### 4b. Process Manager (Event(s) → State → Command(s))

A **stateful orchestrator** that holds the workflow plan, accumulates state from incoming events, and dispatches commands based on its current position in the plan. Process managers centralize workflow knowledge.

```
Event → [Process Manager (stateful)] → Command(s)
```

**Characteristics:**
- Maintains internal state tracking which steps have completed
- Aligns with **orchestration**: a single component directs all participants
- Reacts to multiple event types over time; handles timeouts, branching, and dynamic routing
- Chooses the next command based on accumulated state, not just the triggering event

**When to reach for a Process Manager instead of a Saga:**
- The workflow diagram has conditional branches
- Steps depend on timeouts or scheduled deadlines
- Routing changes based on data accumulated across events
- You need to wait for N of M events before proceeding

**Example:**
```
OrderPlaced       → [OrderFulfillmentPM] → (tracks state: awaiting payment)
PaymentSucceeded  → [OrderFulfillmentPM] → ShipOrder
ShipmentFailed    → [OrderFulfillmentPM] → RefundPayment
PaymentTimeout    → [OrderFulfillmentPM] → CancelOrder
```

---

### 5. Translation (External System → Event or Command)

Converts external system inputs (webhooks, API calls, file imports) into domain commands or events.

```
External Input → [Translator] → Command or Event
```

**Characteristics:**
- Anti-corruption layer between external and internal models
- Maps external terminology to domain language
- Validates and sanitizes external data
- May emit integration events for traceability

**Example:**
```
Stripe Webhook (payment_intent.succeeded) → [PaymentTranslator] → ConfirmPayment
```

---

### 6. Gateway (Command → External System)

Sends domain-originated requests to external systems. The inverse of translation.

```
Command → [Gateway] → External System Call → (optional callback Event)
```

**Characteristics:**
- Adapts domain commands to external API contracts
- Handles retries, circuit breaking, timeout
- May produce result events from callbacks/webhooks
- Domain should not depend on gateway implementation details

**Example:**
```
SendNotification → [EmailGateway] → SendGrid API → (webhook) → EmailDelivered
```

---

### 7. Policy (Event → Decision → Command)

A domain rule that evaluates conditions from events and/or projections to decide whether to issue a command. More opinionated than a reactor — encodes business logic.

```
Event → [Policy (reads State)] → Command (conditionally)
```

**Characteristics:**
- Encodes business rules ("if X then do Y")
- Reads projections to evaluate conditions
- May suppress the command if conditions aren't met
- Named after the business rule it enforces

**Example:**
```
PaymentFailed → [OverduePaymentPolicy (reads CustomerStanding)] → SuspendAccount (if 3+ failures)
```

---

### 8. Scheduler (Time → Command)

A time-triggered automation that issues commands on a schedule or after a delay.

```
Time/Cron → [Scheduler] → Command
```

**Characteristics:**
- Triggered by time, not by events
- Often reads projections to determine what needs processing
- Must be safe to run twice — the same tick can fire more than once; see [Safe to Run Twice](#safe-to-run-twice)
- Produces commands, not events directly

**Example:**
```
Daily 9am → [DormancyScheduler (reads InactiveAccounts)] → CloseForInactivity
```

---

### 9. Event Stream Processing (Event → Event)

Transforms, enriches, or filters events from one stream into events in another. Used at bounded context boundaries.

```
Internal Event → [Stream Processor] → External/Enriched Event
```

**Characteristics:**
- Bridges bounded contexts
- Enriches events with additional context for external consumers
- May filter (not all internal events are externally relevant)
- No business decisions — purely transformation

**Example:**
```
OrderPlaced (internal, detailed) → [OrderEventPublisher] → OrderReceived (external, enriched with customer name)
```

---

## Safe to Run Twice

Every pattern that turns an event or a tick into a command — Reactor (#3), Saga step (#4a), Process Manager (#4b), Policy (#7), Scheduler (#8) — runs twice eventually. Delivery is at-least-once and processes die mid-flight, so "we retry on failure" is a statement about when the second run happens, not whether. Take the first mechanism that applies:

1. **The effect is naturally idempotent** — a conditional write, a compare-and-set, or an aggregate that refuses the command a second time on its own business rules. Nothing external needed.
2. **The provider accepts an idempotency key** — pass one and let the provider deduplicate. See [external-communications.md](external-communications.md).
3. **A dedup record commits with the effect** — an inbox row written in the same transaction as the state change. Exact, not best-effort.
4. **None of the above** — a best-effort external lock, and only here. It trades duplicate-risk for loss-risk; it removes neither.

Two rules decide which one you actually have.

**A dedup marker outside the effect's transaction is a lock, not idempotence.** If the marker and the effect cannot commit or roll back together, there is a window where one exists without the other, and no ordering removes it:

- Marker first, then the process dies — the effect never happens, and every retry is skipped in silence. A handler that acks the skipped message loses it without it ever reaching a dead-letter queue. A marker with no lease is never reclaimed, so this is permanent.
- Effect first, then the process dies — the effect repeats.

Releasing the marker when the handler returns an error does not rescue option 4, because an error does not mean nothing happened. A transaction can commit and then fail to report it; the caller cannot tell that apart from a failure before the commit. Branching on "did it fail?" branches on a question the caller cannot answer.

**Key on the business fact, not the delivery.** Message ids, event positions, and queue receipts change under replay, store rebuild, or the same fact arriving from a second upstream — key on those and a deliberate replay is silently skipped while a genuinely repeated fact slips through. The reply, the payment, the order do not change. Better still, encode the rule as a domain invariant rather than a key: an invariant also settles a *different* message arriving out of order, which no dedup key can.

**In an event-sourced system, option 1 is the default.** The aggregate is derived from the same log the handler is about to append to, so "have I already done this?" is answerable from state already loaded, and expected-version concurrency supplies the atomic guard — which also covers two *simultaneous* deliveries, something a dedup key does not address at all. An internal handler that needs an external dedup store is usually an aggregate decision that leaked into infrastructure.

---

## Pattern Selection Guide

When labeling transitions in your event model, use this decision tree:

```
Who/what initiates the transition?
│
├─ Human actor (UI/API)
│   └─ Command → Aggregate (#1)
│
├─ An event occurred
│   ├─ Need to update a read model? → Projection (#2)
│   ├─ Need to trigger a single command (stateless)? → Reactor (#3)
│   ├─ Need to coordinate a linear multi-step flow with compensations? → Saga (#4a)
│   ├─ Need branching, timeouts, or state-dependent routing? → Process Manager (#4b)
│   ├─ Need to evaluate a business rule first? → Policy (#7)
│   └─ Need to publish to another context? → Stream Processing (#9)
│
├─ External system input
│   └─ Translation (#5)
│
├─ Domain needs to call external system
│   └─ Gateway (#6)
│
└─ Time/schedule
    └─ Scheduler (#8)
```

---

## Labeling Convention

In event model diagrams and documents, label each transition with its pattern:

```
[Event] ──(Reactor)──→ [Command]
[Command] ──(Aggregate)──→ [Event]
[Event] ──(Projection)──→ [View]
[Event] ──(Policy: OverduePaymentPolicy)──→ [Command]
[External] ──(Translation)──→ [Command]
```

This makes the model self-documenting — anyone reading it knows which implementation component handles each arrow.
