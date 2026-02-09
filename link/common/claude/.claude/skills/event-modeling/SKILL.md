---
description: Design event-driven systems using Event Modeling methodology. Auto-triggers when designing new features, aggregates, or discussing system workflows.
---

# Event Modeling

You are an event modeling expert who helps design event-driven systems. When working with event modeling, **read and apply patterns from the following guidelines**:

## Core Guidelines

1. **Anti-Patterns** (`~/.config/ai/guidelines/event-modeling/anti-patterns.md`)
   - Common mistakes in event-driven architecture
   - Visual anti-patterns (left chair, right chair, bed, bookshelf)
   - Detection signals and fixes
   - Business stakeholder test

2. **Diagram Templates** (`~/.config/ai/guidelines/event-modeling/diagram-templates.md`)
   - Draw.io XML templates and styles
   - Element styles (events, commands, views, triggers)
   - Connection styles and layout guidelines
   - Complete examples

3. **External Communications** (`~/.config/ai/guidelines/event-modeling/external-communications.md`)
   - Modeling emails, SMS, letters, API calls
   - Reactor-based communication patterns
   - Domain boundaries and idempotency tradeoffs
   - Avoiding "Initiated" and premature "Sent" events

4. **One or Many Events** (`~/.config/ai/guidelines/event-modeling/one-or-many-events.md`)
   - When to emit single vs multiple events
   - The reusability trap
   - Warning signs of over-splitting
   - Internal vs external events

## Quick Reference

### Four Building Blocks

1. **Event (Orange)** - The Facts
   - Named in past tense: `OrderPlaced`, `PaymentSucceeded`
   - Immutable business facts

2. **Command (Blue)** - The Intentions
   - Named imperatively: `PlaceOrder`, `ProcessPayment`
   - Contains parameters needed for change

3. **View (Green)** - The Read Models
   - Optimized projections built from events
   - Named for purpose: `CustomerDashboard`

4. **Trigger (White)** - The Initiators
   - UI screens, API endpoints, automated processes

### Four Patterns

- **Command**: Trigger → Command → Event(s)
- **View**: Event(s) → View
- **Automation**: Event(s) → Reactor → Command → Event(s)
- **Translation**: External System → View → Command → Event(s)

## Analysis Process

1. **Identify Events First** - What business facts need recording?
2. **Work Backwards to Commands** - What actions cause these events?
3. **Identify Triggers** - What UI/API/automation initiates commands?
4. **Design Views** - What information do users need?
5. **Identify Automations** - What should happen automatically?

## Output Format

Structure your event model as:
- Actors
- Events (The Facts) - table format
- Commands (The Intentions) - table format
- Views (Read Models) - table format
- Slices (Implementation Units)
- Automations - table format
- External Integrations - table format

**Always generate a Draw.io diagram** - Save to `docs/event-model-[feature-name].drawio`

## Quick Anti-Pattern Check

Before finalizing:
- [ ] Events are business facts, not technical operations
- [ ] No "...Updated" or "...Changed" generic events
- [ ] No "...Initiated" events (commands in disguise)
- [ ] Single event per business decision (not splitting for reuse)
- [ ] Events don't connect directly to events (use reactors)

## When to Trigger This Skill

Suggest event modeling when conversation involves:
- Designing new feature or capability
- Adding aggregates or bounded contexts
- Discussing workflows or business processes
- Planning external system integrations
- Refactoring existing event flows

**Trigger phrase**: "Would you like me to help model the events for this feature?"

## For Full Details

See: `~/.config/ai/guidelines/event-modeling/` for comprehensive documentation on:
- Anti-Patterns: Common mistakes and visual patterns to avoid
- Diagram Templates: Draw.io templates with complete styling
- External Communications: Modeling outbound emails, SMS, API calls
- One or Many Events: When to split or combine events
