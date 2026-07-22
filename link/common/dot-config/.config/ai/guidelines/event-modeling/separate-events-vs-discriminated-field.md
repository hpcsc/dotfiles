# Separate Events vs Discriminated Field

When a business fact comes in variants, you face a recurring choice: model each variant as its own **event type**, or model it as one event type carrying a **discriminator field**.

```
PaymentFailedInsufficientFunds        vs.   PaymentFailed { reason: "insufficient_funds" | "card_expired" | ... }
PaymentFailedCardExpired
```

This is not the same question as ["one event or many per command"](one-or-many-events.md) (how many events a single operation records) or ["multiple producers"](multiple-producers.md) (how many handlers emit one type). It applies even with a single producer and a single event per operation: *does this variation deserve its own type?*

## The core axis: behavior vs data

- **Different behavior → separate event.** The variants are different facts that lead to different reactions, carry different invariants, or mean different things to the business.
- **Different data point → discriminated field.** The variants are the *same fact* observed along a dimension. Consumers record or display the dimension; they don't branch their workflow on it.

## The decisive question

**Do consumers react differently?**

- If a consumer does `switch variant { A → workflowA; B → workflowB }` and those workflows are genuinely different → **separate events**. (Switch statements on an event field are the strongest split signal — see [multiple-producers.md](multiple-producers.md), Test 1.)
- If every consumer processes the occurrence identically and only persists/shows the variant → **discriminated field**.

Everything below is a refinement of this one question.

## Signals for separate events

1. **Different downstream behavior.** `PaymentSucceeded` and `PaymentFailed` are not one `PaymentProcessed { outcome }` — they trigger different processes. The outcome *is* the event.
2. **Divergent payloads.** If variant A needs fields meaningless to variant B, a single event becomes a bag of mutually-exclusive nullable fields. The "fields that only apply when `type == X`" shape is the model telling you to split (see anti-pattern ["I'll Just Add One More Field"](anti-patterns.md)).
3. **Different invariants.** If the variants are produced under different validation rules, they are different facts (see [multiple-producers.md](multiple-producers.md), Test 2).
4. **Independent evolution.** If one variant will grow fields, get versioned, or be deprecated on its own timeline, keep it separate.
5. **Precise subscription.** Consumers subscribe at the event-type level. If most consumers care about only one variant, separate types let them subscribe exactly instead of subscribe-then-filter.
6. **Stakeholders need the variant to understand impact.** "We had 50 account closures today" is meaningless without the variant; "50 order cancellations" is not (see [multiple-producers.md](multiple-producers.md), Test 4).

## Signals for a discriminated field

1. **Same fact, same reaction.** `PaymentReceived { method: card | bank | cash }` — money arrived; everyone handles "money arrived" the same way and `method` is an attribute.
2. **Uniform payload.** All variants carry the same shape; the discriminator just labels it.
3. **Only analytics cares.** If the difference matters to reporting but not to any workflow, a field is enough.
4. **Open or growing variant set.** If new categories appear regularly (channels, reasons, sources), a field scales; a new event type per category does not. A type-per-variant model is only viable for a *small, closed, stable* set.

## Two traps at the extremes

**Splitting too far — property/state sourcing.** Don't mint a new event type per field value when the reaction is identical. That's the discriminated-field case, and over-splitting produces near-duplicate events all handled by copy-pasted logic. A little healthy copy/paste beats artificial event proliferation.

**Lumping too far — false equivalence.** Don't force different business scenarios into one type with a discriminator just because they have similar effects. If handlers must load extra state and switch to react correctly, the discriminator is hiding a real type boundary (see ["False Equivalence"](anti-patterns.md)).

## The answer can differ by lifecycle stage

Ask the question separately at each stage of an entity's life. A distinction that earns separate types at one stage does not automatically carry to the next.

Several kinds of outbound message may differ enough in intent to deserve their own events when composed, yet share one delivery event, because "did it arrive" does not vary by intent. The resulting asymmetry — many events at one stage, one at the next — is a correct model, not an inconsistency to tidy up.

Where consumers plainly branch, the behavioral question already answers it. Where it is less clear, ask about the producer instead: **can whatever records the fact at this stage even see the distinction?** If a provider callback reports delivery and knows nothing about the message's intent, no consumer can ever branch on what was never recorded — the distinction belongs to an earlier stage. That question you can settle by looking; "will these ever diverge?" you cannot. See [external-communications.md](external-communications.md) for the worked example, and for why one type is the cheaper default when the answer stays unclear.

## Don't discriminate on downstream or derived data

A discriminator must be a fact true **at the moment the event occurred**. Never categorize an upstream event by reaching into a downstream aggregate's state or id (e.g. tagging a detection event with the `caseId` it later produces). That couples the event to a future it cannot yet know and breaks replay. If the only way to set the discriminator is to look downstream, you're modeling the wrong fact.

## Decision checklist

| Ask | Separate events | Discriminated field |
|-----|-----------------|---------------------|
| Do consumers branch their workflow on it? | Yes | No |
| Do variants carry different payload fields? | Yes (mutually exclusive) | No (uniform) |
| Do variants have different invariants? | Yes | No |
| Is the variant set open / growing? | No (small, closed) | Yes |
| Who cares about the difference? | Many consumers | Only analytics |
| Will variants evolve independently? | Yes | No |
| Can the discriminator be known at occurrence time? | n/a | Must be yes |

**Rule of thumb:** start from the behavioral lens — a small, fixed set of outcomes driving *different downstream behavior* → separate events; the same occurrence varying along a dimension (especially an open-ended one) → one event with a discriminated field.

## Related

- [one-or-many-events.md](one-or-many-events.md) — how many events one command should emit
- [multiple-producers.md](multiple-producers.md) — when multiple handlers may emit the same event type; the coupling tests
- [anti-patterns.md](anti-patterns.md) — "I'll Just Add One More Field", "False Equivalence", "State Obsession"
