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

## Delivery Is a Fact About Transport, Not About Intent

A domain often has several *kinds* of outbound message that are genuinely distinct — an automated reply, a human agent's reply, a request for information. Each is triggered differently, carries different intent, and drives different downstream behavior, so each earns its own event when it is composed:

```
AutoReplyDrafted    // composed by automation
AgentReplyDrafted   // written by a human
InfoRequestDrafted  // asks the customer for something
```

The mistake is assuming that distinction carries down the lifecycle. **Ask, at each stage, whether the fact recorded at that stage actually varies by the upstream distinction.**

For delivery it does not. "Did this reach the recipient?" means the same thing, arrives the same way, and is handled the same way whether the message answered the customer or asked them a question. So the shape is asymmetric, and that is correct:

```
three drafting events (intent differs)  →  one delivery event (transport does not)
```

**The test: can whatever produces the fact even see the distinction?** Delivery is reported by the email provider, and the provider has no idea whether it just sent a bot's answer or a human's. Your intent taxonomy is invisible to it. So the three delivered types are not merely unlikely to diverge — nothing upstream is *capable* of making them differ.

Ask this rather than "will these types ever diverge?", because nobody can answer that one. Asking what would have to supply the difference, then looking to see whether it exists, is a question you can settle today.

**Channel is a different axis, and the same test shows why.** Email and SMS are reported by different providers, with different failure modes and different delivery semantics, so `EngagementEmailDelivered` / `EngagementSMSDelivered` is a real split. Change the channel and you change who reports the fact and what they are able to report. Change the intent and you change neither.

**When the test does not settle it, start with one type.** The two mistakes are not equally expensive:

- Three types you regret are permanent. In an append-only log, every projection handles all three forever, even after you add a unified fourth — and every new kind of outgoing message forces the split again.
- One type you regret is cheap. You start emitting specific types from that point on, and the history stays readable.
- Merging loses nothing. A single delivery event still has to name the message it refers to, and that id leads back to the drafted event, which carries the intent. You are declining to store intent twice, not throwing it away.

This is the mirror image of [False Equivalence](anti-patterns.md): there, genuinely different scenarios are forced into one type; here, one genuine fact is split along a boundary borrowed from an earlier stage.

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
7. ❌ Don't split delivery events per message kind — ask whether whatever reports the fact can even see the distinction; if it can't, one event
