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
- Should be idempotent where possible
- Does NOT make business decisions — delegates to the aggregate

**Example:**
```
OrderPlaced → [PaymentReactor] → ProcessPayment
```

---

### 4. Process Manager / Saga (Event(s) → State → Command)

A stateful automation that coordinates a multi-step process across aggregates or bounded contexts. Maintains its own state to track progress.

```
Event → [Process Manager (stateful)] → Command(s)
```

**Characteristics:**
- Maintains internal state tracking which steps have completed
- Reacts to multiple event types over time
- Can handle timeouts and compensating actions
- More complex than a reactor — use only when statefulness is required

**Example:**
```
OrderPlaced → [OrderFulfillmentProcess] → (tracks state)
PaymentSucceeded → [OrderFulfillmentProcess] → ShipOrder
ShipmentFailed → [OrderFulfillmentProcess] → RefundPayment
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
- Must be idempotent (scheduler may fire multiple times)
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
│   ├─ Need to coordinate multiple steps over time? → Process Manager (#4)
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
