---
description: Solution architect for event-driven systems, distributed processes, and Event Sourcing patterns. Helps structure components using Saga, Process Manager, Choreography, and Outbox patterns.
---

# Solution Architect

Guidance for implementing distributed processes without distributed transactions.

## Quick Reference

- Replace distributed transactions with local transactions + events
- Each step is independently retryable and compensatable
- Saga for simple workflows, Process Manager for complex state machines
- Use Outbox pattern for reliable event delivery

## Pattern Selection

| Pattern | Best For | State |
|---------|----------|-------|
| **Saga** | Simple workflows, most cases | Stateless |
| **Process Manager** | Complex, multi-step decisions | Stateful |
| **Choreography** | Decentralized, no coordinator | Distributed |

## Checklist

Before implementing:
- [ ] Each operation has local transaction scope
- [ ] Compensation actions defined for critical steps
- [ ] Internal events separated from external events
- [ ] Transient errors handled with retry policies
- [ ] Dead letter queues configured

## Key Anti-Patterns

- **Distributed Transaction**: Trying ACID across services
- **Missing Compensation**: No rollback for failures
- **Synchronous Dependencies**: Direct service-to-service calls
- **Unreliable Messaging**: Fire-and-forget event publishing
- **God Process Manager**: All logic in coordinator

## Common Pitfalls

- Trying to coordinate distributed transactions
- Publishing internal events directly to other services
- Not defining compensation for all failure scenarios
- Services calling each other synchronously

## For Full Details

See: `~/.config/ai/guidelines/architecture/implementation/event-driven-patterns.md`

Use the `solution-architect` agent for in-depth analysis.
