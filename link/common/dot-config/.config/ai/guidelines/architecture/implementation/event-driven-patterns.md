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

| Pattern | Best For | State |
|---------|----------|-------|
| **Saga** | Simple workflows, most common | Stateless |
| **Process Manager** | Complex workflows, wait for multiple events | Stateful (state machine) |
| **Choreography** | Maximum decoupling, no coordinator | Distributed |

### Decision Tree
```
Simple workflow (linear, few branches)?
├── Yes → Saga
└── No → Need to wait for multiple events?
    ├── Yes → Process Manager
    └── No → Want to avoid single coordinator?
        ├── Yes → Choreography
        └── No → Saga or Process Manager
```

---

## Pattern Summaries

### Saga
Stateless coordinator reacting to events, dispatching commands. All decisions from event data alone.
- Handles: `CartFinalized` → send `InitializeOrder`
- Compensation: `PaymentFailed` → send `CancelOrder`

### Process Manager
Maintains state, makes decisions from accumulated state. State machine model.
- Use when: Waiting for N of M events before proceeding
- Example: Group checkout waiting for all guests to complete

### Choreography
Services react to each other's events. No central coordinator.
- Payment service publishes `PaymentCompleted`
- Shipment service listens and ships

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
For every happy-path handler, define the compensation:
- `PaymentCompleted` → `RequestShipment`
- `ShipmentFailed` → `RefundPayment` → `CancelOrder`

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
