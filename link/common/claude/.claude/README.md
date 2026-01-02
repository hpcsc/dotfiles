# Claude Code Skills

Custom skills that auto-trigger based on conversation context.

## Available Skills

### Event Modeling

**Location**: `~/.claude/skills/event-modeling/`

**Auto-triggers when**:
- Designing new features or capabilities
- Discussing workflows or business processes
- Adding new aggregates or bounded contexts
- Planning external system integrations

**Example prompts that trigger this skill**:

```
"I need to add a payment reminder feature"

"How should we model the order fulfillment process?"

"We need to integrate with Stripe for subscriptions"

"Let's design the customer onboarding workflow"

"What events should we emit when a user cancels their subscription?"
```

**What it does**:
- Identifies events, commands, views, and automations
- Generates Draw.io diagrams
- Checks for anti-patterns
- Structures output as implementation slices

---

### Domain Design Review

**Location**: `~/.claude/skills/domain-design-review/`

**Auto-triggers when**:
- Designing new features or aggregates
- Adding cross-service functionality
- Discussing bounded context boundaries
- Planning significant refactoring

**Example prompts that trigger this skill**:

```
"Let's add a risk assessment to the payment flow"

"I want to add customer communication tracking to the Account aggregate"

"We need PaymentService to check the customer's risk score"

"Should we add a loyalty points field to the Customer entity?"

"How do we share customer data between billing and communications?"
```

**What it does**:
- Reviews designs against 8 architectural anti-patterns
- Identifies coupling risks and god objects
- Validates bounded context boundaries
- Suggests fixes with code examples

---

## How Skills Work

Skills auto-trigger based on semantic matching. When Claude detects a relevant conversation, it will ask:

> "Would you like me to help model the events for this feature?"

or

> "Would you like me to run a design review against common architectural anti-patterns?"

You can accept or decline. Skills run in the main conversation with full context.

## Manual Invocation

If a skill doesn't auto-trigger, you can explicitly request it:

```
"Use the event modeling skill to design this feature"

"Run a domain design review on this proposal"

"Check this design for architectural anti-patterns"
```

## Skill vs Command vs Agent

| Type | Discovery | Context | Best For |
|------|-----------|---------|----------|
| **Skill** | Auto | Main conversation | Complex workflows Claude should suggest |
| **Command** | Manual `/name` | Main conversation | Quick explicit prompts |
| **Agent** | Explicit | Isolated | Multi-step autonomous work |

Skills are ideal when you want Claude to proactively offer help based on what you're discussing.
