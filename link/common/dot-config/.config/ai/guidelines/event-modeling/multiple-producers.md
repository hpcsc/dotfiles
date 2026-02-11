# Multiple Producers for Same Event

When should multiple command handlers emit the same event type?

## The Key Question

**Do they represent the same business outcome or just similar technical effects?**

---

## ✅ Same Event: Cohesion (Good)

Multiple handlers emitting the same event is **cohesion** when they produce the same business outcome.

### Example: Order Cancellation

```go
type Order struct { ... }

// All three produce the same business outcome: "order is cancelled"
func (o *Order) CancelByCustomer(reason string) (*OrderCancelled, error) {
    if o.Status == "shipped" {
        return nil, errors.New("cannot cancel shipped order")
    }
    return &OrderCancelled{
        OrderID: o.ID,
        CancelledBy: "customer",
        Reason: reason,
    }, nil
}

func (o *Order) CancelDueToPaymentFailure(attempts int) (*OrderCancelled, error) {
    return &OrderCancelled{
        OrderID: o.ID,
        CancelledBy: "system",
        Reason: fmt.Sprintf("payment_failed_%d_attempts", attempts),
    }, nil
}

func (o *Order) CancelByAdmin(adminID, reason string) (*OrderCancelled, error) {
    return &OrderCancelled{
        OrderID: o.ID,
        CancelledBy: "admin",
        AdminID: adminID,
        Reason: reason,
    }, nil
}
```

**Why this is cohesion:**
- Same business outcome: order is cancelled
- Same invariants: status becomes "cancelled", inventory released
- Uniform downstream: most consumers treat all cancellations identically
- Payload differentiation: `CancelledBy` field allows specialized handling when needed
- Single source of truth: Order aggregate owns "cancellation"

---

## ❌ Same Event: False Equivalence (Bad)

Multiple handlers emitting the same event creates **coupling** when they represent different business scenarios forced into one shape.

### Example: Account Closure

```go
// ❌ BAD: Different business scenarios using same event

func (a *Account) CloseByCustomer() (*AccountClosed, error) {
    if a.Balance > 0 {
        return nil, errors.New("cannot close with positive balance")
    }
    return &AccountClosed{AccountID: a.ID}, nil
}

func (a *Account) CloseForFraud(reason string) (*AccountClosed, error) {
    // Different invariants: can close with balance
    return &AccountClosed{AccountID: a.ID}, nil
}

func (a *Account) CloseForInactivity(days int) (*AccountClosed, error) {
    return &AccountClosed{AccountID: a.ID}, nil
}
```

**Why this creates coupling:**

1. **Different business semantics**:
   - Customer closure: voluntary, final
   - Fraud closure: involuntary, legal hold on funds
   - Dormancy: automatic, reversible

2. **Different invariants**:
   - Customer closure requires zero balance
   - Fraud closure ignores balance
   - Dormancy closure allows small balances

3. **Forces downstream coupling**:
```go
// ❌ Handler forced to query and switch on hidden state
func (h *Handler) OnAccountClosed(evt AccountClosed) {
    account := h.loadAccount(evt.AccountID) // forced query

    if account.HasFraudFlag {
        h.triggerLegalReview()
    } else if account.InactiveDays > 365 {
        h.scheduleWinBack()
    } else {
        h.sendFarewellEmail()
    }
}
```

### Fix: Use Specific Events

```go
// ✅ GOOD: Different events for different business facts

func (a *Account) CloseByCustomer() (*AccountClosedByCustomer, error) {
    return &AccountClosedByCustomer{
        AccountID: a.ID,
        FinalBalance: 0,
        CustomerConfirmed: true,
    }, nil
}

func (a *Account) CloseForFraud(reason, investigatorID string) (*AccountClosedForFraud, error) {
    return &AccountClosedForFraud{
        AccountID: a.ID,
        Reason: reason,
        InvestigatorID: investigatorID,
        BalanceFrozen: a.Balance,
    }, nil
}

func (a *Account) CloseForInactivity(days int) (*AccountClosedForInactivity, error) {
    return &AccountClosedForInactivity{
        AccountID: a.ID,
        InactiveDays: days,
        ReopenEligible: true,
    }, nil
}
```

---

## The Coupling Tests

### Test 1: Do Downstream Systems Need to Differentiate?

```go
// ❌ Switch statements = coupling smell
func (r *Reactor) OnOrderCancelled(evt OrderCancelled) {
    switch evt.CancelledBy {
    case "customer": r.sendCustomerEmail()
    case "admin": r.sendAdminNotice()
    case "system": r.sendPaymentFailure()
    }
}
```

If multiple handlers switch on event fields, split into specific event types.

### Test 2: Do Events Have Different Invariants?

```go
// Different validation rules suggest different events
func (o *Order) CancelByCustomer() error {
    if o.Status == "shipped" { return error }  // has restriction
}

func (o *Order) CancelByAdmin() error {
    // no status check - admin can override
}
```

If invariants differ significantly, use separate events.

### Test 3: Can Events Be Processed Identically?

```go
// ✅ If ALL consumers treat them the same, single event OK
func (p *Projector) OnOrderCancelled(evt OrderCancelled) {
    p.updateStatus("cancelled")
    p.releaseInventory()
    // Don't care WHO or WHY
}
```

If most consumers treat events identically, single event is cohesion.

### Test 4: Business Stakeholder Language

Would a business person naturally group these?

- ✅ "We had 50 order cancellations today" → Single event works
- ❌ "We had 50 account closures today" → Needs context

If stakeholders need the type to understand impact, use different events.

---

## Scope Matters

### ✅ Same Aggregate: Usually Fine

```go
// Same aggregate, different paths to same outcome
type Order struct { ... }

func (o *Order) CancelByCustomer() (*OrderCancelled, error)
func (o *Order) CancelByAdmin() (*OrderCancelled, error)
```

Single source of truth for "order cancellation."

### ⚠️ Different Aggregates, Same Context: Code Smell

```go
// Different aggregates emitting same event
type Payment struct { ... }
func (p *Payment) Process() (*PaymentSucceeded, error)

type Subscription struct { ... }
func (s *Subscription) ProcessRenewal() (*PaymentSucceeded, error)
```

**Smell**: Likely wrong boundaries. Either consolidate or use specific events.

### ❌ Different Bounded Contexts: Anti-Pattern

```go
// Different services with same event name
// Identity Service
type CustomerUpdated struct { Email string }

// Billing Service
type CustomerUpdated struct { PaymentMethodID string }
```

**Wrong**: Use namespaced or specific events.

---

## Decision Framework

```
Multiple handlers emitting same event?
    │
    ├─ Same business outcome?
    │   ├─ YES → Same event OK (cohesion)
    │   └─ NO → Use different events
    │
    ├─ Same invariants?
    │   ├─ YES → Same event probably OK
    │   └─ NO → Consider separate events
    │
    ├─ Downstream treats them identically?
    │   ├─ YES → Same event OK
    │   └─ NO → Split into specific events
    │
    └─ Business stakeholders group them?
        ├─ YES → Same event
        └─ NO → Different events
```

---

## Payload Differentiation vs Event Type Differentiation

### Use Payload Fields

When:
- Same business outcome
- Most consumers treat identically
- Only analytics care about the difference

Example: `OrderCancelled { CancelledBy: "customer" | "admin" }`

### Use Different Event Types

When:
- Different business semantics
- Different invariants
- Many consumers differentiate
- Switch statements in handlers

Example: `OrderCancelledByCustomer`, `OrderCancelledByAdmin`

---

## Key Principles

1. **Same event = Single business fact = Single aggregate ownership**
2. **Cohesion ≠ Coupling**: Same event is cohesion when same outcome, coupling when false equivalence
3. **Don't force different scenarios into same shape** just because they have similar effects
4. **Switch statements on event fields** = strong signal to split the event

---

## Summary

| Scenario | Recommendation |
|----------|---------------|
| Multiple commands, same aggregate, same outcome | ✅ Same event (cohesion) |
| Multiple aggregates, same context | ⚠️ Code smell |
| Different bounded contexts | ❌ Use namespaced events |
| Handlers with switch statements | ❌ Split into specific events |

**Key Insight**: Coupling comes from false equivalence, not from reuse.
