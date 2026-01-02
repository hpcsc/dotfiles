# Good Patterns for This Platform

Platform-specific examples of well-designed domain boundaries and event-driven architecture.

---

## Event-Based Cross-Context Communication

**Pattern**: Subscribe to events, maintain local projections, avoid sync calls.

```go
// collect/modules/payment/projections/customer_risk.go
// Payment context maintains its own view of customer risk
type CustomerRiskProjection struct {
    CustomerID string
    RiskLevel  string
    AssessedAt time.Time
}

func (p *Projector) OnRiskAssessed(evt RiskAssessed) {
    p.store.Upsert(CustomerRiskProjection{
        CustomerID: evt.CustomerID,
        RiskLevel:  evt.Level,
        AssessedAt: evt.AssessedAt,
    })
}

// Payment handler uses local projection - no cross-context call
func (h *Handler) ProcessPayment(cmd Command) {
    risk := h.riskProjection.Get(cmd.CustomerID)
    // Decision made from local data
}
```

**Why it's good**:
- Payment context works even if Risk service is down
- No hidden runtime dependencies
- Clear data ownership

---

## Context-Specific Models

**Pattern**: Define separate models for each bounded context, even for the same "concept".

```go
// collect/modules/communications/domain/contactable_customer.go
type ContactableCustomer struct {
    CustomerID vo.CustomerID
    Email      vo.Email
    Phone      vo.Phone
    Channel    vo.Channel
}

// collect/modules/compliance/domain/regulated_customer.go
type RegulatedCustomer struct {
    CustomerID vo.CustomerID
    SSN        vo.SSN  // PII only in compliance context
    KYCStatus  vo.KYCStatus
}

// collect/modules/billing/domain/billable_customer.go
type BillableCustomer struct {
    CustomerID     vo.CustomerID
    PaymentMethods []PaymentMethod
    BillingAddress Address
}
```

**Why it's good**:
- PII doesn't leak to contexts that don't need it
- Each context evolves independently
- Clear ownership of each field

---

## Single-Responsibility Aggregates

**Pattern**: Each aggregate changes for exactly one category of business reasons.

```go
// Good: Separate aggregates for separate concerns

// collect/aggregates/account.go - handles account lifecycle
type Account struct {
    ID         vo.AccountID
    CustomerID vo.CustomerID
    Status     vo.AccountStatus
    OpenedAt   time.Time
    ClosedAt   *time.Time
}
// Events: AccountOpened, AccountClosed, AccountSuspended

// collect/aggregates/payment_plan.go - handles payment arrangements
type PaymentPlan struct {
    ID        vo.PaymentPlanID
    AccountID vo.AccountID
    Schedule  []ScheduledPayment
    Status    vo.PlanStatus
}
// Events: PaymentPlanCreated, PaymentScheduled, PaymentCompleted

// collect/aggregates/communication.go - handles customer contact
type CustomerCommunication struct {
    CustomerID vo.CustomerID
    Channel    vo.Channel
    Consent    vo.ConsentStatus
    History    []CommunicationRecord
}
// Events: CommunicationSent, ConsentGranted, ConsentRevoked
```

**Why it's good**:
- Changes to payment logic don't touch account lifecycle
- Communication rules evolve independently
- Clear boundaries for testing

---

## Event Naming: Business Facts, Not Technical Operations

**Pattern**: Name events after what the business cares about.

```go
// Good: Business-meaningful events
type PaymentSucceeded struct {
    PaymentID  vo.PaymentID
    AccountID  vo.AccountID
    Amount     vo.Money
    Method     vo.PaymentMethod
    ProcessedAt time.Time
}

type CustomerEngaged struct {
    CustomerID vo.CustomerID
    Channel    vo.Channel
    Outcome    vo.EngagementOutcome
    EngagedAt  time.Time
}

type AccountDelinquent struct {
    AccountID    vo.AccountID
    DaysPastDue  int
    AmountOwed   vo.Money
    MarkedAt     time.Time
}
```

```go
// Bad: Technical/generic events
type RecordUpdated struct { ... }      // What record? Updated how?
type StatusChanged struct { ... }      // What status? To what?
type DataModified struct { ... }       // Meaningless
```

**Test**: Would a business stakeholder understand this event name?

---

## Reactor Single Responsibility

**Pattern**: One reactor, one side effect.

```go
// Good: Separate reactors for separate effects

// collect/handler/send_payment_confirmation.go
type SendPaymentConfirmationReactor struct{}

func (r *SendPaymentConfirmationReactor) On(evt PaymentSucceeded) {
    // Only sends confirmation email
    r.emailService.SendPaymentConfirmation(evt)
}

// collect/handler/update_account_balance.go
type UpdateAccountBalanceReactor struct{}

func (r *UpdateAccountBalanceReactor) On(evt PaymentSucceeded) {
    // Only updates balance projection
    r.balanceProjection.ApplyPayment(evt)
}

// collect/handler/notify_collections.go
type NotifyCollectionsReactor struct{}

func (r *NotifyCollectionsReactor) On(evt PaymentSucceeded) {
    // Only notifies collections system
    r.collectionsAPI.RecordPayment(evt)
}
```

```go
// Bad: One reactor doing everything
type PaymentSucceededHandler struct{}

func (h *PaymentSucceededHandler) On(evt PaymentSucceeded) {
    h.emailService.SendConfirmation(evt)           // Side effect 1
    h.balanceProjection.Update(evt)                // Side effect 2
    h.collectionsAPI.Notify(evt)                   // Side effect 3
    h.analyticsService.Track(evt)                  // Side effect 4
    // If any fails, what happens to the others?
}
```

**Why it's good**:
- Each reactor can be retried independently
- Clear failure handling per effect
- Easy to add/remove effects

---

## Command Validation in Aggregates

**Pattern**: Aggregates own business rule validation; handlers orchestrate.

```go
// Good: Aggregate validates business rules
func (a *Account) Close(cmd CloseAccount) es.ValidationResult {
    if a.Status == vo.AccountStatusClosed {
        return es.Invalid("account already closed")
    }
    if a.Balance.IsPositive() {
        return es.Invalid("cannot close account with positive balance")
    }
    if a.HasPendingPayments() {
        return es.Invalid("cannot close account with pending payments")
    }

    return es.ValidWithEvents(&evt.AccountClosed{
        AccountID: a.ID,
        ClosedAt:  time.Now(),
        Reason:    cmd.Reason,
    })
}

// Handler just orchestrates
func (h *Handler) Handle(cmd CloseAccount) error {
    account := h.repo.Load(cmd.AccountID)
    result := account.Close(cmd)
    if !result.Valid() {
        return result.Error()
    }
    return h.repo.Save(account, result.Events())
}
```

**Why it's good**:
- Business rules are testable without infrastructure
- Aggregate is the single source of truth for its invariants
- Handler stays thin and focused

---

## Projection Independence

**Pattern**: Projections can be rebuilt from events without side effects.

```go
// Good: Pure projection - no side effects
type AccountBalanceProjector struct {
    store ProjectionStore
}

func (p *AccountBalanceProjector) On(evt PaymentSucceeded) {
    balance := p.store.Get(evt.AccountID)
    balance.Amount = balance.Amount.Subtract(evt.Amount)
    balance.LastPaymentAt = evt.ProcessedAt
    p.store.Save(balance)
    // No emails, no API calls, just data transformation
}

func (p *AccountBalanceProjector) Rebuild() {
    p.store.Clear()
    events := p.eventStore.LoadAll()
    for _, evt := range events {
        p.On(evt)  // Safe to replay - no side effects
    }
}
```

**Why it's good**:
- Can rebuild projections anytime (schema changes, bug fixes)
- No duplicate emails/notifications during rebuild
- Clear separation: projections read, reactors act
