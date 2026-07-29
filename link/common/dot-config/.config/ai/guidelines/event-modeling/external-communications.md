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

**The test has two halves: do consumers act differently on it, and can whatever produces the fact even see the distinction?**

*Consumers first, because that half is decisive.* All three delivery outcomes land in the same place and do the same job — mark a row on the timeline so an agent can see the message arrived. Nothing reading them branches on which kind of message it was.

*The producer question then sharpens an unclear answer.* Delivery is reported by the email provider, and the provider has no idea whether it just sent a bot's answer or a human's. Your intent taxonomy is invisible to it, so the three delivered types are not merely unlikely to diverge — nothing upstream is *capable* of making them differ.

Ask both rather than "will these types ever diverge?", because nobody can answer that one. Asking what would have to supply the difference, then looking to see whether it exists, is a question you can settle today.

**The producer half is a tiebreaker, not a substitute.** A blind producer does not mean no consumer needs the distinction — a consumer can resolve it from the send's identity and branch anyway. Split when *either* half says split; merge only when both say merge.

**Channel is a different axis, and the same test shows why.** Email and SMS are reported by different providers, with different failure modes and different delivery semantics, so `EngagementEmailDelivered` / `EngagementSMSDelivered` is a real split. Change the channel and you change who reports the fact and what they are able to report. Change the intent and you change neither.

**Same provider, different consequence, still a split.** Marketing and transactional email go out through one provider, over one webhook, with the same failure modes, so the producer half says merge. The consumer half does not. Marketing delivery feeds campaign reporting, open-rate baselines, list hygiene and sender reputation; transactional delivery answers "did this person get their reset link", where a failure means re-send or escalate, now. Merge them and campaign metrics quietly start counting password resets, while every consumer that only ever wanted one population filters for it forever. This is the case a producer-only test gets wrong, and the easier one to miss precisely because checking who reports the fact turns up nothing.

**"One delivery event" means one per owner, not one globally.** Where two aggregates both send — a campaign engine and a support conversation — each records its own delivery fact, even when the field lists come out identical. Two aggregates emitting one shared type is the boundary smell in [multiple-producers.md](multiple-producers.md) ("Different Aggregates, Same Context"), and a shared delivery stream also gives up two things ownership buys: ordering against the send it belongs to, and the owner's ability to reject a delivery for a send it never made. Deduplicate what genuinely repeats — parsing the provider payload, translating its vocabulary into your outcomes, the idempotency key — and let each owner keep its own fact.

**When the test does not settle it, start with one type.** The two mistakes are not equally expensive:

- Three types you regret are permanent. In an append-only log, every projection handles all three forever, even after you add a unified fourth — and every new kind of outgoing message forces the split again.
- One type you regret is cheap. You start emitting specific types from that point on, and the history stays readable.
- Merging loses nothing **provided the delivery event is keyed per send**. Its id then leads back to exactly one drafted event, which carries the intent, so you are declining to store intent twice rather than throwing it away. Key it to the thread or to the inbound message being answered instead, and several sends share that id: one outcome points at three drafted events, nothing says which of them arrived, and the timeline cannot mark the right row. This is the easy mistake, because the shared id is usually the one already at hand when the fact is recorded, and nothing looks wrong until something downstream needs to tell two sends apart.

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
7. ❌ Don't split delivery events per message kind — ask both whether consumers act differently and whether whatever reports the fact can even see the distinction; merge only when both answers are no
8. ✅ Key a merged delivery event per send, so it still resolves to exactly one drafted event
9. ✅ Keep one delivery event per owning aggregate — "one event" is not license to share one type across two owners
