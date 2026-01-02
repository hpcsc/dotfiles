# The Eight Deadly Anti-Patterns

Detailed detection and fixes for each architectural anti-pattern.

---

## 1. Wireframe-Driven Development

**What it is**: Starting architectural decisions from UI mockups rather than domain discovery.

**Why it's deadly**: Views aggregate information across logical contexts, embedding this conflation into the system's foundation.

**Real Example - Bad**:
```
UI shows: Customer Dashboard with Account Balance, Payment History, Communication Log
Result: CustomerAggregate becomes a god object holding account, payment, and communication concerns
```

**Detection**:
- Design conversations start with "The screen shows..."
- Entities mirror UI component structure
- Aggregates contain data from multiple bounded contexts

**Fix**: Start with domain events. Ask "What business facts need to be recorded?" not "What does the screen show?"

---

## 2. Noun-Based Modeling (God Objects)

**What it is**: Building domain models around nouns rather than behaviors.

**Why it's deadly**: Creates low-cohesion, high-coupling components that change for multiple unrelated reasons.

**Real Example - Bad**:
```go
// Account aggregate grows to handle unrelated concerns:
type Account struct {
    // Core account data
    ID, CustomerID, Balance

    // Payment processing (different concern)
    PaymentMethods, LastPaymentDate

    // Communication tracking (different concern)
    PreferredChannel, LastContactDate

    // Risk assessment (different concern)
    RiskScore, FraudFlags
}
```

**Detection**:
- Aggregate has 10+ event types
- Single file exceeds 500 lines
- Methods group into unrelated clusters
- "When X changes, we also need to update Y" where X and Y are unrelated

**Fix**: Split by behavior cohesion. Each aggregate should change for exactly one category of business reasons.

---

## 3. Context Violation (Cross-Context Coupling)

**What it is**: Business processes leaking between domains through direct service calls.

**Why it's deadly**: Creates invisible dependencies that prevent independent deployment and evolution.

**Real Example - Bad**:
```go
// In payment handler - direct call to another context
func (h *PaymentHandler) ProcessPayment(cmd ProcessPayment) error {
    // Direct call to another context's service
    customer := h.customerService.GetCustomer(cmd.CustomerID)  // Cross-context coupling

    if customer.RiskScore > threshold {  // Risk logic leaked into payment
        return ErrHighRisk
    }
    // ...
}
```

**Real Example - Good**:
```go
// Payment context maintains its own risk view from events
type CustomerRiskProjection struct {
    CustomerID string
    RiskLevel  string  // Derived from subscribed RiskAssessed events
}

func (h *PaymentHandler) ProcessPayment(cmd ProcessPayment) error {
    // Uses local projection - no cross-context call
    risk := h.riskProjection.Get(cmd.CustomerID)
    if risk.RiskLevel == "high" {
        return ErrHighRisk
    }
    // ...
}
```

**Detection**:
- Service A imports and calls Service B directly
- Handler needs data from multiple aggregates to make decisions
- "We need to add a dependency on X service" is common

**Fix**: Communicate through events. Subscribe to events, maintain local projections.

---

## 4. Blurred Domain Boundaries

**What it is**: Using generic terms (User, Account, Item) across different bounded contexts where they mean different things.

**Why it's deadly**: Forces single entities to carry responsibilities from multiple contexts, often including unnecessary PII.

**Real Example - Bad**:
```go
// One "Customer" struct used everywhere
type Customer struct {
    ID              string
    Name            string    // Needed by: Support, Billing, Communications
    Email           string    // Needed by: Auth, Communications
    SSN             string    // Needed by: Compliance only - PII leak!
    PaymentMethods  []PM      // Needed by: Billing only
    CommunicationPrefs Prefs  // Needed by: Communications only
}
```

**Real Example - Good**:
```go
// Context-specific models
// communications/domain.go
type ContactableCustomer struct {
    ID    string
    Email string
    Prefs CommunicationPreferences
}

// compliance/domain.go
type RegulatedCustomer struct {
    ID  string
    SSN string  // PII stays in compliance context only
}
```

**Detection**:
- Same struct imported by 5+ packages
- Fields marked "only used by X" in comments
- Sensitive data accessible in contexts that don't need it

**Fix**: Define context-specific models. Pass only required data between contexts.

---

## 5. Data Coupling Through Shared Persistence

**What it is**: Multiple contexts accessing the same database tables.

**Why it's deadly**: Creates inseparable services. Splitting later requires rewriting queries that span context boundaries.

**Real Example - Bad**:
```sql
-- Query in payment service that joins across contexts
SELECT p.amount, c.risk_score, comm.last_contact
FROM payments p
JOIN customers c ON p.customer_id = c.id       -- Customer context
JOIN communications comm ON c.id = comm.customer_id  -- Communication context
WHERE p.status = 'pending'
```

**Detection**:
- Migrations in one service add columns for another service's needs
- Queries with 3+ table joins spanning different domains
- "We can't deploy this without also deploying X"

**Fix**: Each context owns its tables. Share through events and local projections.

---

## 6. Leaking Domain Logic

**What it is**: Exposing internal implementation details that external code begins depending on.

**Why it's deadly**: Creates hidden contracts. Refactoring becomes risky because you don't know who depends on internals.

**Real Example - Bad**:
```go
// Account exposes internal calculation
func (a *Account) GetRiskFactors() []RiskFactor {
    return a.riskFactors  // Internal detail exposed
}

// Somewhere else, code depends on this implementation detail
func AssessLoan(account *Account) {
    factors := account.GetRiskFactors()
    // Now loan assessment is coupled to Account's internal risk model
}
```

**Detection**:
- Public methods that expose internal collections/state
- Other packages reaching into aggregate internals
- Changes to internal structures require changes in consuming code

**Fix**: Expose behaviors, not data. If external code needs risk info, emit a `RiskAssessed` event.

---

## 7. Dependency Injection Without Event Decoupling

**What it is**: Using DI for loose object construction while maintaining tight behavioral coupling.

**Why it's deadly**: DI doesn't solve coupling - services still call each other synchronously, creating runtime dependencies.

**Real Example - Bad**:
```go
// Looks loosely coupled because of interface...
type PaymentHandler struct {
    riskService RiskService  // Injected interface
}

func (h *PaymentHandler) Process(cmd Command) {
    // But still synchronously coupled!
    risk := h.riskService.Assess(cmd.CustomerID)  // Sync call
    // Payment processing blocked if risk service is down
}
```

**Real Example - Good**:
```go
// Risk context emits event
// RiskAssessed { CustomerID, Level, AssessedAt }

// Payment context maintains local projection from events
type PaymentHandler struct {
    riskView *CustomerRiskProjection  // Local data, no runtime dependency
}

func (h *PaymentHandler) Process(cmd Command) {
    risk := h.riskView.Get(cmd.CustomerID)  // No external call
    // Payment works even if risk service is down
}
```

**Detection**:
- Services inject other service interfaces
- Method calls cross aggregate/context boundaries
- Failures in one service cascade to others

**Fix**: Use events for cross-context communication. Maintain local projections.

---

## 8. Missing Design Phase (Accidental Architecture)

**What it is**: Translating requirements directly to code without intentional boundary discovery.

**Why it's deadly**: Architecture emerges accidentally through implementation. Refactoring becomes the primary design tool, compounding technical debt.

**The Compound Effect**:
```
Day 1:  "User needs to see their balance" → Add Balance field to User
Day 30: "User needs payment history" → Add Payments[] to User
Day 60: "User needs risk score" → Add RiskScore to User
Day 90: User is now a god object with 50 fields
```

Each change seemed manageable. Collectively, they created unmaintainable code.

**Detection**:
- PRs add fields to existing entities without architectural discussion
- No event modeling sessions before implementation
- "We'll refactor later" is common
- Single aggregate grows continuously

**Fix**: Design before implementation:
1. Conduct event storming / event modeling session
2. Identify bounded context boundaries
3. Define aggregate responsibilities
4. Document with diagrams
5. Review design before writing code

---

## Anti-Pattern Detection Checklist

| Pattern | Detection Signal | Question to Ask |
|---------|------------------|-----------------|
| Wireframe-Driven | Design starts with "the screen shows..." | "What business facts need recording?" |
| Noun-Based Modeling | Aggregate changes for multiple unrelated reasons | "What behaviors does this entity own?" |
| Context Violation | Service A directly calls Service B | "Can these deploy independently?" |
| Blurred Boundaries | Same struct used across 5+ packages | "Does this mean the same thing everywhere?" |
| Data Coupling | Cross-context database joins | "Who owns this table?" |
| Leaking Domain Logic | External code depends on internal state | "Is this a contract or an implementation detail?" |
| DI Without Decoupling | Services inject other service interfaces | "What happens if that service is down?" |
| Missing Design Phase | PRs add fields without design discussion | "Did we intentionally design this boundary?" |
