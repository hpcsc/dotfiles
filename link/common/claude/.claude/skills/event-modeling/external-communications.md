# Modeling External Outbound Communication

How to model emails, SMS, letters, and API calls to third parties.

## The Key Question

**Do we need to make decisions based on this interaction later?**

Model external interactions as domain events **only when they carry business value**:
- Compliance requires knowing what was sent
- Business logic depends on communication status
- Stakeholders need visibility into outcomes

If communications are purely notifications with no downstream logic, you may not need events.

## The Business Stakeholder Test

Before creating an event, ask: **"Would I use this term when describing the process to a non-technical business leader?"**

- ✅ `PaymentConfirmationEmailDelivered` — Business understands this
- ❌ `EmailMessageInitiated` — Technical process detail

## Anti-Patterns to Avoid

### ❌ "...Initiated" Events

**Never use events like `EmailInitiated` or `SMSInitiated`.**

Problems:
- Commands in disguise — exist to trigger downstream processes, not record facts
- Lack business significance — stakeholders care about results, not initiation
- Misrepresent system state — nothing has actually happened yet

```
# BAD: Command masquerading as event
CustomerFollowUp → EmailMessageInitiated → [reactor sends email]
```

### ❌ Premature "...Sent" Events

Don't emit `EmailSent` immediately after calling the provider but before confirmation.

Problems:
- External providers are uncontrollable — email might fail
- You're claiming success before confirmation
- Creates dishonest system state

## Recommended Pattern

**Trigger external interactions through meaningful domain events, not technical process events.**

### Reactor-Based External Communication

```
Domain Event → Reactor → External Provider → (Optional) Result Event
```

**Flow**:
1. Business-meaningful domain event occurs (`PaymentSucceeded`, `CustomerEngaged`)
2. Reactor listens for this event
3. Reactor calls external provider (SendGrid, Twilio, etc.)
4. (Optional) On provider callback, emit result event (`EmailDelivered`)

**Example - Payment Confirmation**:
```
PaymentSucceeded
    ↓ (reactor)
    → Call SendGrid
    ↓ (webhook callback)
PaymentConfirmationEmailDelivered
```

**Example - Customer Follow-up**:
```
CustomerEngaged (contains channel selection, compliance checks)
    ↓ (reactor)
    → Call SendGrid/Twilio
    ↓ (webhook callback)
EngagementEmailDelivered / EngagementSMSDelivered
```

## Domain Boundaries

Distinguish between **your domain** and **external provider concerns**:

| We Own | Provider Owns |
|--------|---------------|
| Customer engagement | Email delivery mechanics |
| Communication compliance | SMS routing |
| Channel selection | Delivery status tracking |
| Business outcomes | Retry logic |

**Model your domain, not theirs.** Instead of `EmailMessage` aggregate, consider `CustomerEngagement` aggregate.

## The Idempotency Tradeoff

There's an unsolvable problem: if a reactor crashes after calling the external provider but before persisting the result event, you may get duplicate communications.

**Accepted tradeoff**: The probability is small enough to accept occasional duplicates rather than over-engineering with complex outbox patterns.

If duplicates are truly unacceptable, use the outbox pattern—but recognize this may require `...Initiated` style events as triggers.

## Checklist

When modeling external outbound communication:

1. ✅ Does the business need to make decisions based on this communication?
2. ✅ Use business-meaningful trigger events, not technical process events
3. ❌ Avoid `...Initiated` events — they're commands in disguise
4. ❌ Avoid premature `...Sent` events before provider confirmation
5. ✅ Model your domain (engagement, notification) not the provider's (email, SMS)
6. ✅ Accept the tradeoff: Occasional duplicates vs complex outbox patterns
