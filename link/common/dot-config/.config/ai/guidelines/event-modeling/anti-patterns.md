# Event Modeling Anti-Patterns

Common mistakes that undermine event-driven architecture.

---

## Event Anti-Patterns

### 1. State Obsession

**What it is**: Focusing on the *result* of state changes rather than the *business facts* that caused them.

**Bad**:
```
BalanceUpdated { Amount: 50 }
BalanceUpdated { Amount: -50 }
BalanceUpdated { Amount: 100 }
```

**Good**:
```
CashDeposited { Amount: 50 }
DebitCardPaymentMade { Amount: 50, MerchantId: "..." }
WireTransferReceived { Amount: 100, SenderAccount: "..." }
```

**Detection**: Event name contains "Updated", "Changed", or "Modified" and could apply to multiple scenarios.

**Fix**: Ask "What specific business fact happened?" and name the event after that.

---

### 2. Property Sourcing

**What it is**: Creating events that mirror database column updates.

**Bad**:
```
UserNameChanged { UserId, NewName }
UserEmailChanged { UserId, NewEmail }
UserAddressChanged { UserId, NewAddress }
```

**Good**:
```
CustomerProfileCorrected { UserId, Name, Email, Address, Reason }
CustomerRelocated { UserId, NewAddress, EffectiveDate }
```

**Detection**: Event names follow `[Entity][Field]Changed` pattern.

**Fix**: Ask "What business operation caused these fields to change?" Group related changes.

---

### 3. "I'll Just Add One More Field"

**What it is**: Continuously expanding event payloads with optional fields.

**Bad** (evolved over time):
```
ShoppingCartConfirmed {
    CartId, ClientId, ProductItems, TotalPrice,
    // v2: loyalty
    LoyaltyProgramId?, PointsEarned?,
    // v3: promotions
    PromotionId?, DiscountAmount?,
    // v4: subscriptions
    IsSubscriptionOrder?, SubscriptionId?,
    // v5: gifts
    IsGiftOrder?, GiftMessage?, RecipientId?
}
```

**Good**:
```
StandardCartConfirmed { CartId, ClientId, ... }
SubscriptionCartConfirmed { CartId, SubscriptionId, ... }
GiftOrderConfirmed { CartId, RecipientId, GiftMessage, ... }
LoyaltyRewardEarned { CartId, LoyaltyProgramId, PointsEarned }
```

**Detection**: Events with many nullable fields or mutually exclusive field combinations.

**Fix**: Create distinct event types for distinct business scenarios.

---

### 4. Clickbait Event

**What it is**: Events with vague names that require additional lookups to understand.

**Bad**:
```
AccountInformationUpdated { AccountId }
ShipmentStatusChanged { ShipmentId }
OrderModified { OrderId }
```

**Good**:
```
ShipmentDispatched { ShipmentId, DispatchedAt, CarrierId }
ShipmentDelivered { ShipmentId, DeliveredAt, RecipientName }
ShipmentLost { ShipmentId, ReportedAt, LastKnownLocation }
```

**Detection**: Payload only contains an ID; event name ends in "Updated/Changed/Modified".

**Fix**: Name events after the specific business fact with relevant data included.

---

### 5. "...Initiated" Events

**What it is**: Events that exist only to trigger downstream processes.

**Bad**:
```
CustomerFollowUp → EmailMessageInitiated → [reactor sends email]
```

The "Initiated" event exists only to trigger the reactor—it records intention, not fact.

**Good**:
```
CustomerEngaged → [reactor sends email] → EmailDelivered (optional callback)
```

**Why it's wrong**: These are commands in disguise. They lack business significance.

**Fix**: Use meaningful domain events as triggers. Don't create events just to start processes.

---

### 6. False Equivalence

**What it is**: Using the same event for different business scenarios that have different semantics, invariants, or downstream requirements.

**Bad**:
```
AccountClosed { AccountID }

// Used for three different scenarios:
// - Customer voluntary closure (requires zero balance)
// - Fraud closure (freezes funds, legal hold)
// - Dormancy closure (reversible, can reopen)
```

**Good**:
```
AccountClosedByCustomer { AccountID, FinalBalance: 0, CustomerConfirmed: true }
AccountClosedForFraud { AccountID, BalanceFrozen, InvestigatorID, Reason }
AccountClosedForInactivity { AccountID, InactiveDays, ReopenEligible: true }
```

**Detection**:
- Multiple handlers in same aggregate emit same event but have different invariants
- Downstream handlers switch on event payload fields
- Business scenarios have different semantics but share event name

**Fix**: See `multiple-producers.md` for full guidance on when same event is cohesion vs coupling.

---

## Visual Anti-Patterns (Diagram Shapes)

### 7. The Left Chair 🪑

**Visual**: One command → multiple cascading events (3-7+)

```
                    ┌─→ CustomerCreated
                    ├─→ CustomerActivated
RegisterCustomer ───┼─→ CustomerAddressCreated
                    ├─→ CustomerEmailVerified
                    └─→ WelcomeEmailSent
```

**Problem**: Cramming excessive logic into a single command.

**Fix**: Break into discrete decisions. Each command = one decision → one event → one state change.

---

### 8. The Right Chair 🪑

**Visual**: Multiple events all feeding into a single "god" read model

```
CustomerCreated      ─┐
OrderPlaced          ─┤
PaymentReceived      ─┼─→ MasterDashboardView
ShipmentDispatched   ─┤
ReviewSubmitted      ─┘
```

**Problem**: One view consuming everything, creating excessive coupling.

**Fix**: Create focused read models for specific use cases.

---

### 9. The Bed 🛏️

**Visual**: One UI component sequentially firing multiple commands

```
┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐
│  UI    │──→│ Cmd 1  │──→│ Cmd 2  │──→│ Cmd 3  │──→ ...
└────────┘
```

**Problem**: UI orchestrating workflows instead of letting events flow naturally.

**Fix**: Use process managers or sagas for complex workflows, not UI-driven orchestration.

---

### 10. The Bookshelf 📚

**Visual**: One slice contains massive logic; all others are anemic

```
Slice 1: ████████████████████████████████  (massive)
Slice 2: ██
Slice 3: ███
Slice 4: █
```

**Problem**: God-object pattern at slice level.

**Fix**: Distribute business rules across slices proportionally.

---

## External Communication Anti-Patterns

### 11. Premature "...Sent" Events

**Bad**: Emitting `EmailSent` immediately after calling the provider but before confirmation.

**Problem**: You're claiming success before it's confirmed. External providers are uncontrollable.

**Good Pattern**:
```
Domain Event → Reactor → External Provider → (webhook) → EmailDelivered
```

Only record delivery facts when you have confirmation.

---

## Anti-Pattern Detection Checklist

| Pattern | Detection Signal | Question to Ask |
|---------|------------------|-----------------|
| State Obsession | "Updated/Changed" for multiple scenarios | "What specific business fact happened?" |
| Property Sourcing | `[Entity][Field]Changed` naming | "What business operation caused this?" |
| One More Field | Many nullable fields | "Are these really the same event?" |
| Clickbait Event | Payload only contains ID | "Can consumers act without querying?" |
| Initiated Events | Events that just trigger processes | "Is this a fact or an intention?" |
| False Equivalence | Multiple handlers, different invariants | "Do these have same business outcome?" |
| Left Chair | Command → 3+ events | "Is this one decision or multiple?" |
| Right Chair | Many events → one view | "Does this view need all this data?" |
| The Bed | UI fires sequential commands | "Should backend orchestrate this?" |
| Bookshelf | One giant slice, others tiny | "What boundaries are violated?" |

---

## The Business Stakeholder Test

For every event, ask: **"Would a business stakeholder understand this event name and know exactly what happened?"**

- ✅ `PaymentSucceeded` — Clear business fact
- ✅ `SubscriptionRenewed` — Specific scenario
- ✅ `CustomerAddressVerified` — Meaningful outcome
- ❌ `AccountUpdated` — Which account? Updated how?
- ❌ `StatusChanged` — What status? Changed to what?
- ❌ `DataModified` — Meaningless
