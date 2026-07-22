# Event Modeling Guidelines

Guidance for discovering, designing, and diagramming event-driven models — capabilities and processes, events and their boundaries, the patterns behind each transition, and the diagram conventions to draw it all.

## Contents

### Discovering the model

- [capabilities-vs-processes.md](capabilities-vs-processes.md) — distinguish a business *capability* (the WHAT, stable) from a *process* (the HOW, a trigger→steps→outcome timeline); model processes, organize by capabilities.
- [message-processing-patterns.md](message-processing-patterns.md) — the catalogue of components behind each arrow (Aggregate, Projection, Reactor, Saga, Process Manager, Translation, Gateway, Policy, Scheduler, Stream Processing), with a selection guide and labeling convention.

### Designing events

- [one-or-many-events.md](one-or-many-events.md) — should one operation record one event or several? Prefer single; split only for distinct business facts, not code reuse.
- [separate-events-vs-discriminated-field.md](separate-events-vs-discriminated-field.md) — should a variant be its own event type or a field on one event? Decide on the behavior-vs-data axis, and re-ask it at each lifecycle stage.
- [multiple-producers.md](multiple-producers.md) — when may multiple handlers emit the *same* event type? Cohesion (same outcome) vs false equivalence (different scenarios forced into one shape), with coupling tests.
- [external-communications.md](external-communications.md) — modeling outbound email/SMS/letters/API calls: trigger on meaningful domain events, record delivery facts on confirmation, keep delivery one event across message kinds, model your domain not the provider's.

### Avoiding mistakes

- [anti-patterns.md](anti-patterns.md) — the catalogue of event and diagram smells (State Obsession, Property Sourcing, "One More Field", Clickbait, "...Initiated", False Equivalence, the chair/bed/bookshelf diagram shapes), each with a detection signal and fix.

### Diagramming

- [diagram-templates.md](diagram-templates.md) — draw.io templates, element/connection styles, colors, and layout rules for Event Modeling diagrams.

## Which guide do I need?

| I'm trying to… | Start here |
|----------------|-----------|
| Tell whether something is a process worth modeling | [capabilities-vs-processes.md](capabilities-vs-processes.md) |
| Decide how many events one command emits | [one-or-many-events.md](one-or-many-events.md) |
| Decide between a new event type and a discriminator field | [separate-events-vs-discriminated-field.md](separate-events-vs-discriminated-field.md) |
| Decide whether two handlers may share an event type | [multiple-producers.md](multiple-producers.md) |
| Model an email / SMS / external call | [external-communications.md](external-communications.md) |
| Decide how many delivery events several message kinds need | [external-communications.md](external-communications.md) |
| Label what implements each arrow in the model | [message-processing-patterns.md](message-processing-patterns.md) |
| Sanity-check a model for smells | [anti-patterns.md](anti-patterns.md) |
| Draw the diagram | [diagram-templates.md](diagram-templates.md) |
