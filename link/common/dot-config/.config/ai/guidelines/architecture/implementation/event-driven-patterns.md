# Event-Driven Architecture Patterns

## Core Principle

**Replace distributed transactions with local transactions coordinated through events.**

Break operations into small local transactions that communicate through events. Each step is independently retryable and compensatable.

---

## Implementation Checklist

### 1. Transaction Boundaries
- [ ] Each operation has clear local transaction scope
- [ ] No cross-service ACID transactions
- [ ] Compensation actions defined for all critical steps

### 2. Event Design
- [ ] Internal events separated from external events
- [ ] Events contain enough context for next steps
- [ ] Event naming follows ubiquitous language

### 3. Error Handling
- [ ] Transient errors handled with retry policies
- [ ] Permanent errors trigger compensation
- [ ] Dead letter queues configured

### 4. Infrastructure
- [ ] Durable message bus for reliable delivery
- [ ] Outbox pattern for atomic operations
- [ ] Monitoring for distributed flows

---

## Pattern Selection

| Pattern | Coordination Style | Best For | State |
|---------|-------------------|----------|-------|
| **Saga** | Choreography (distributed) | Linear workflows with clear per-step compensations | Per-step local state; no central coordinator |
| **Process Manager** | Orchestration (centralized) | Branching, timeouts, state-dependent routing | Stateful (state machine) |

Saga and Process Manager are the two coordination patterns; **Choreography** and **Orchestration** are the styles they embody (not a third alternative).

### Decision Tree
```
Does the workflow have conditional branches, timeouts,
or routing that depends on accumulated state?
├── Yes → Process Manager (orchestration)
└── No  → Linear flow with clear compensations?
         ├── Yes → Saga (choreography)
         └── No  → Reactor (single stateless event→command hop)
```

Heuristic: if the whiteboard diagram shows branches or "wait until X or timeout Y", you need a Process Manager. If it's a straight line with well-defined undos, a Saga fits.

---

## Pattern Summaries

### Saga
A set of local transactions coordinated through events, each paired with a **compensating action** that semantically undoes it if a later step fails. Workflow knowledge is distributed — each participant knows only its own step and its own compensation.
- Happy path: `PaymentCompleted` → `RequestShipment`
- Compensation: `ShipmentFailed` → `RefundPayment`

**Compensation ≠ rollback.** Compensations are new forward-moving events that add to the history. Never emit events that pretend prior facts didn't happen.

### Process Manager
A stateful orchestrator that holds the workflow plan, accumulates state from incoming events, and dispatches commands based on its current position. Centralizes workflow knowledge.
- Use when: branching, timeouts, or waiting for N of M events before proceeding
- Example: Group checkout waiting for all guests to complete, with a deadline

### Choreography vs Orchestration (coordination styles)
- **Choreography** — services react to each other's events; no central coordinator. Sagas are the canonical implementation.
- **Orchestration** — a central component directs participants via commands. Process Managers are the canonical implementation.

### Event Enrichment
Transform internal events to external events. Add context, hide internals.
- Internal: `CartConfirmed` (minimal)
- External: `ShoppingCartFinalized` (enriched with items, totals)

### Outbox Pattern
Store events + state in same transaction. Publish separately.
- Guarantees: No lost events, atomic state + event

---

## Anti-Pattern Detection

| Anti-Pattern | Signal | Fix |
|--------------|--------|-----|
| **Distributed Transaction** | `tx.Commit()` spanning services | Use Saga |
| **Leaking Internal Events** | Publishing events with `InternalStatus`, `ValidationRules` | Event Enrichment |
| **Missing Compensation** | No handlers for `*Failed` events | Define compensation for every happy-path step |
| **Synchronous Dependencies** | `s.paymentClient.ProcessPayment()` direct calls | Event-driven communication |
| **God Process Manager** | PM has DB connections, email clients, business logic | Keep lightweight, delegate to services |
| **Unreliable Messaging** | `go func() { eventBus.Publish(evt) }()` fire-and-forget | Outbox pattern |

---

## Key Implementation Notes

### Saga Compensation Flow
For every happy-path handler, define the compensation as a new forward event (not an erasure):
- `PaymentCompleted` → `RequestShipment`
- `ShipmentFailed` → `RefundPayment` → `CancelOrder`

Compensations preserve history. `PaymentRefunded` records a real business fact; a hypothetical `PaymentUndone` that tries to nullify `PaymentCompleted` does not.

### Outbox Critical Path
```
1. Begin transaction
2. Save business state
3. Save outbox entries
4. Commit (atomic)
5. Background: poll outbox, publish, mark published
```

### Event Enrichment Boundary
- Internal events: Minimal, within bounded context
- External events: Enriched, cross-context consumption

---

## Guidance Format

```markdown
## Event-Driven Architecture Guidance

### Scenario Summary
[Brief description of the distributed process]

### Recommended Pattern
[Which pattern and why]

### Key Components
[Major components and responsibilities]

### Error Handling Strategy
[Failures and compensation]
```
