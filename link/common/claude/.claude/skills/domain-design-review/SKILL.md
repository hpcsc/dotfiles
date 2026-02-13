---
description: Review domain designs for architectural anti-patterns before implementation. Auto-triggers when designing new features, aggregates, or bounded contexts.
---

# Domain Design Review

Review domain designs against common architectural anti-patterns.

## Quick Reference

- Design from domain events, not UI mockups
- Each aggregate changes for ONE category of reasons
- Communicate through events, not direct service calls
- Define context-specific models, not shared generic entities
- Each context owns its data

## Checklist

Before approving any design:
- [ ] Events identified before commands
- [ ] Clear bounded context boundaries
- [ ] No cross-context direct dependencies
- [ ] Aggregates represent true consistency boundaries
- [ ] No god objects (10+ event types = smell)

## Key Anti-Patterns

- **Wireframe-Driven**: Design starts with "the screen shows..."
- **Noun-Based Modeling**: Aggregate changes for multiple unrelated reasons
- **Context Violation**: Service A directly calls Service B
- **Blurred Boundaries**: Same struct used across 5+ packages
- **Data Coupling**: Cross-context database joins

## Common Pitfalls

- Starting from UI mockups instead of domain events
- Building around nouns instead of behaviors
- Sharing database tables across contexts
- Exposing internal state to external code

## For Full Details

See: `~/.config/ai/guidelines/architecture/design/domain-modeling.md`
