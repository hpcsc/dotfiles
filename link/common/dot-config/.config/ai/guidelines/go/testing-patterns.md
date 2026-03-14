# Go Testing Patterns

## Section Index

| Section | Line | Use when... |
|---|---|---|
| [Core Principle](#core-principle-test-behavior-through-public-api-only) | ~26 | Foundation — all consumers |
| [Independent Verification](#independent-verification) | ~39 | Reviewing test quality, judging expected values |
| [Three Essential Qualities](#three-essential-qualities-of-effective-tests) | ~131 | Designing or reviewing tests |
| [What to Test](#what-to-test) | ~178 | Deciding whether something is worth testing |
| [Unit of Behavior](#what-is-a-unit-of-behavior) | ~190 | Deciding test boundaries, filtering worthless tests |
| [HTTP Handlers](#http-handlers-the-component-is-the-endpoint) | ~238 | Testing HTTP endpoints (HTML, JSON, streaming) |
| [Test Structure](#test-structure) | ~318 | Writing new tests (templates, build tags) |
| [Test Double Patterns](#test-double-patterns) | ~360 | Writing or reviewing fakes, broken, recording, memory |
| [Never Expose Internals](#principle-never-expose-internals-just-for-testing) | ~476 | When tempted to export private state for tests |
| [Test Clarity](#test-clarity-include-only-relevant-details) | ~609 | Balancing helper abstraction vs inline detail |
| [Assertion Strictness](#assertion-strictness-match-to-what-youre-testing) | ~749 | Choosing strict vs loose assertions |
| [Test Helper Patterns](#test-helper-patterns) | ~803 | Writing var blocks, deterministic data, table-driven tests |
| [Anti-Patterns](#common-anti-patterns) | ~883 | Reviewing tests for common mistakes (0–8) |
| [Detection Checklist](#anti-pattern-detection-checklist) | ~1111 | Quick scan for red flags in test reviews |
| [Quick Testing Checklist](#quick-testing-checklist) | ~1129 | Pre-flight check before writing or approving tests |
| [Summary](#summary) | ~1160 | Reference table of practices |

---

## Core Principle: Test Behavior Through Public API Only

**Never test implementation details. Test observable behavior through exported functions and methods.**

Tests should verify **what** the system does (observable behaviors), not **how** it does it (implementation details). This creates tests that are more resilient to refactoring and focuses on business value.

### Why This Matters
- Tests remain valid during refactoring
- Tests document intended behavior
- Tests catch genuine bugs, not implementation changes

---

## Independent Verification

A test provides independent verification when its expected values come from **outside the implementation** — from business requirements, specifications, or domain knowledge — rather than restating what the code does.

The key question: **if the implementation breaks, will this test catch it?**

### Degrees of Independence

| Degree | Expected value source | Can it fail on a bug? | Value |
|---|---|---|---|
| Strong | Domain knowledge / spec | Yes, and failure is self-evidently wrong | High |
| Moderate | Externally verified lookup | Yes, but correctness requires checking an external source | Medium |
| Weak | Copied from production code | Yes, but correctness requires checking production intent | Low (change detector) |
| None (tautology) | Computed from production code | No | Zero |

### Strong Independence

The test encodes domain knowledge the implementation must satisfy. The test and the implementation arrive at the same answer from different directions.

```go
// The test knows $10.50 = 1050 cents — a mathematical fact independent of how ConvertToCents works.
func TestConvertUSDToCents(t *testing.T) {
    require.Equal(t, int64(1050), ConvertToCents(10.50, "USD"))
}
```

### Weak Independence (Change Detectors)

The expected value was copied from production code. The test detects changes but cannot tell you whether the new value is correct.

```go
// Where does 2 come from? From looking at the production code.
func TestDefaultDecimalPlaces(t *testing.T) {
    require.Equal(t, 2, DefaultDecimalPlaces("USD"))
}
```

A particularly bad variant duplicates the production formula:

```go
// BAD: Same formula as production — fails on change but provides no guidance on correctness.
func TestDiscount(t *testing.T) {
    price := 100.0
    discount := 0.2
    expected := price - (price * discount)
    require.Equal(t, expected, ApplyDiscount(price, discount))
}
```

### No Independence (Tautologies)

The expected value is derived from the code under test at runtime. The test **cannot fail**.

```go
// BAD: Both sides evaluate the same code path — passes no matter what ApplyDiscount does.
func TestDiscount(t *testing.T) {
    expected := ApplyDiscount(100.0, 0.2)
    require.Equal(t, expected, ApplyDiscount(100.0, 0.2))
}
```

Other tautology forms:
- Asserting a mock returns what you told it to return
- Using a shared helper that computes both expected and actual values from the same source

### Prefer Higher-Level Behavioral Tests Over Change Detectors

When you notice a change-detector test, check whether a behavioral test already covers it. If so, the change detector is redundant. If not, write the behavioral test first.

```go
// Change detector: weak independence
func TestDefaultDecimalPlaces(t *testing.T) {
    require.Equal(t, 2, DefaultDecimalPlaces("USD"))
}

// Behavioral: strong independence — failure is self-evidently wrong
func TestFormatUSDAmount(t *testing.T) {
    require.Equal(t, "$10.50", FormatAmount(10.5, "USD"))
}
```

If someone changes `DefaultDecimalPlaces("USD")` to `3`, both fail. But the formatting test fails with `"$10.500" != "$10.50"` — self-evidently wrong. The change detector only says `3 != 2`.

### Identifying the Degree

Two questions, applied in order:

1. **Can the test fail at all?** If the expected value is derived from the code under test at runtime, it's a tautology. Remove it or replace it with a hardcoded expected value.
2. **If it fails, is the failure self-evidently wrong?** If yes, the test has strong independence. If you'd just update the test to match the new production value, it has weak independence.

---

## Three Essential Qualities of Effective Tests

Every test should maximize these interconnected qualities:

### 1. Fidelity: Tests Should Catch Defects
**High-fidelity tests are sensitive to defects in the code under test.**

Achieve fidelity by:
- Covering all critical code paths (especially error paths)
- Including comprehensive assertions about expected outcomes
- Testing edge cases and boundary conditions
- Asserting on actual values, not just that functions ran

### 2. Resilience: Tests Shouldn't Break from Harmless Changes
**Resilient tests only fail when breaking changes are made to the code under test.**

Achieve resilience by:
- Testing public APIs rather than internals
- Preferring fakes and in-memory implementations over mocks
- Avoiding verification of unnecessary dependency interactions
- Testing behavior, not implementation

**Note:** Flaky tests have poor resilience. Tests should be deterministic.

### 3. Precision: Failed Tests Should Pinpoint Problems
**High-precision tests tell you exactly where the defect lies.**

Achieve precision by:
- Keeping tests small and focused (one behavior per test)
- Using descriptive test names that explain what's being tested
- For integration tests, validating state at every boundary
- Using strict, specific assertions

### Balancing the Three Qualities

These qualities often conflict:
- It's easy to write highly resilient but low-fidelity tests (empty tests pass but catch nothing)
- Balancing resilience with fidelity requires deliberate effort
- Over-mocking increases precision but decreases resilience

**Apply all three qualities as a framework when designing tests:**
- Will this test catch the defect? (Fidelity)
- Will this test break when I refactor internals? (Resilience)
- Will this failure tell me exactly what's wrong? (Precision)

---

## What to Test

✅ **Observable behavior**: outputs, return values, state changes, side effects
✅ **Business rules**: domain logic, validation rules, error conditions
✅ **Integration points**: how components interact through public interfaces

❌ **Implementation details**: internal method calls, private fields
❌ **Trivial code**: simple getters/setters, field assignments
❌ **Framework behavior**: Go language features

---

## What is a Unit of Behavior?

A **unit of behavior** is an observable outcome that a caller depends on. The "caller" might be a product user, another service, another package, or another developer on your team.

The key question: **"If this behavior changed, would someone outside this code need to know?"**

### Three Tiers of Behavioral Contracts

Not every behavior traces back to a user story. Infrastructure code has behavioral contracts too — the behavior just serves developers instead of end users.

| Tier | Who cares | Example |
|------|-----------|---------|
| **Domain** | Product owner, end user | "Paused accounts cannot receive payments" |
| **Contract** | Other services, other packages | "Events are published to SNS in order" |
| **Structural** | Other developers on your team | "Returns ErrNotFound when key is missing" |

All three tiers are valid behaviors worth testing. The distinction between behavior and implementation isn't about who the caller is — it's about whether any caller depends on it.

### How to Tell Behavior from Implementation

Ask: **"Does any caller of this code depend on this specific detail?"**

| Assertion | Caller depends on it? | Verdict |
|-----------|-----------------------|---------|
| `Get` returns the value after `Set` | Yes — that's the contract | **Behavior** |
| Items are stored in a `map[string]entry` | No — could be a slice, tree, anything | **Implementation** |
| Concurrent `Get`/`Set` don't panic | Yes — callers run this concurrently | **Behavior** |
| A `sync.RWMutex` is used internally | No — callers care about thread-safety, not the mechanism | **Implementation** |

### What is NOT a Unit of Behavior:

- Object existence (`require.NotNil(t, p)`)
- Constructor success (`NewX()` returns non-nil)
- A test that only checks `require.NoError(t, err)` with no other assertion
- Internal mechanisms (which data structure, which sync primitive, which call order)

### What IS a Unit of Behavior:

An observable outcome that a caller depends on:
- **"rejects invalid input"** - domain: business validation
- **"saves data to database"** - domain: side effect
- **"returns sorted results"** - domain: output correctness
- **"publishes events in version order"** - contract: downstream consumers depend on ordering
- **"returns ErrNotFound when key is missing"** - structural: callers handle this case
- **"notifies subscribers on error"** - contract: external communication

---

## HTTP Handlers: The Component Is the Endpoint

An HTTP handler — whether it returns JSON, HTML, or streamed chunks — may be composed of multiple internal pieces (controllers, templates, view models, serializers, middleware). **These are implementation details. The unit of behavior is the HTTP response.**

The public API is: HTTP request in → HTTP response out. Test through `httptest.NewRecorder` and the handler function, asserting on what the caller (browser, API client, frontend) observes.

### What Is Observable Behavior

| Observable (test this) | Why |
|---|---|
| Status codes (200, 422, 500) | API contract — callers branch on this |
| Error messages shown to the user | User-visible feedback |
| Response body data values (IDs, amounts, names) | Correctness of business logic |
| Content-Type, Location, and other semantic headers | API contract — callers depend on these |
| Ordering of streamed chunks | Contract — frontend relies on skeleton-before-content |
| Presence of key content in rendered output | "Does the user see the error / the subject / the amount?" |

### What Is Implementation Detail

| Implementation (don't test this) | Why |
|---|---|
| Specific HTML tags or elements (`<iframe>`, `<details>`, `<div>`) | Template refactoring shouldn't break tests |
| CSS classes, inline styles, data-attributes | Presentation, not behavior |
| Number of DOM nodes, nesting depth | Structural, not behavioral |
| Whether a value is in a `<span>` vs `<p>` vs `<h4>` | Irrelevant to the user |
| Internal types (view models, template data structs) | Private to the handler package |
| Which template engine or serializer is used | Swappable without changing behavior |

### The Litmus Test

> "If I change **how** the response is built (swap template engine, restructure HTML, rename a view model field) but the user sees the **same content** — should any test break?"
>
> If yes, the test is asserting on implementation.

### Example: HTML Handler

```go
// BAD: Testing HTML structure
doc := parseHTML(w.Body)
require.Equal(t, 1, doc.Find("iframe").Length())
require.Equal(t, "day-card", doc.Find("div").First().AttrOr("class", ""))

// GOOD: Testing user-visible content
require.Equal(t, http.StatusOK, w.Result().StatusCode)
require.Contains(t, dayCard.HTML, "Day 42")
require.Contains(t, dayCard.HTML, "Test Subject")
require.Contains(t, dayCard.HTML, "provider unavailable")
```

### Example: API Handler

```go
// BAD: Testing JSON field ordering or internal serialization
require.JSONEq(t, `{"status":"ok","data":{"id":"123"}}`, w.Body.String())

// GOOD: Testing response contract and data values
require.Equal(t, http.StatusOK, w.Result().StatusCode)
require.Equal(t, "application/json", w.Result().Header.Get("Content-Type"))

var resp ResponseBody
require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
require.Equal(t, "123", resp.Data.ID)
require.Equal(t, "ok", resp.Status)
```

### When HTML Structure IS Behavior

Sometimes structure matters because a downstream caller depends on it (e.g., HTMX swap targets, streaming chunk `target` fields, accessibility landmarks). In those cases the structure is a **contract**, not an implementation detail, and is worth testing:

```go
// Target IDs are a contract — HTMX swaps depend on them
require.ElementsMatch(t, []string{"day-0-30", "day-0-31"}, targets)

// Streaming order is a contract — frontend renders progressively
require.Equal(t, "skeleton", chunks[0].Type)
require.Equal(t, "summary", chunks[len(chunks)-1].Type)
```

---

## Test Structure

```go
// Build tags for test categories
//go:build unit

package inmemory_test

// Subtest organization
func TestProvisioning(t *testing.T) {
    t.Run("scenario description", func(t *testing.T) {
        // Arrange - set up test data
        // Act - execute the behavior
        // Assert - verify observable outcomes
    })
}
```

### Template

```go
func TestFeatureName(t *testing.T) {
    t.Run("describes specific scenario", func(t *testing.T) {
        // Arrange - set up test data
        subject := NewSubject()

        // Act - execute the behavior
        result, err := subject.Method(input)

        // Assert - verify observable outcomes
        require.NoError(t, err)
        require.Equal(t, expected, result)
    })

    t.Run("describes error scenario", func(t *testing.T) {
        // Test error paths with same structure
    })
}
```

---

## Test Double Patterns

**Use concrete implementations (memory, broken, recording) instead of mocks whenever possible.**

### Why Prefer These Over Mocks

1. **More realistic**: Behave like real implementations, testing actual code paths
2. **Less setup code**: No need to configure mock expectations
3. **Better resilience**: Tests survive internal refactoring without changes
4. **Easier debugging**: Behavior is transparent, not hidden behind mock expectations

### When to Use Each Type

| Priority | Type | File | Use When |
|----------|------|------|----------|
| 1st | Real implementation | - | Always prefer when feasible |
| 2nd | Memory | `memory.go` | Testing happy paths, verifying storage/retrieval |
| 3rd | Broken | `broken.go` | Testing error handling, resilience patterns |
| 4th | Recording | `fake.go` | Need to verify specific call details |
| Last | Mock | - | Last resort — verifying call sequences only |

When in doubt: prefer concrete implementations over mocks. They provide better test fidelity with less code.

### Pattern 1: Memory (Happy Path)

In-memory implementation for testing successful operations:

```go
// Fresh empty state
memoryStream := stream.NewMemoryStream()

// Or pre-populated state
memoryStore := store.NewMemory(map[string]uint64{
    "projection-1": 100,
})

s := store.New(memoryStream)
err := s.Save(streamID, aggregate, 0)
require.NoError(t, err)

// Verify actual behavior
events, _ := memoryStream.EventsForStream(ctx, streamID)
require.Len(t, events, 1)
```

### Pattern 2: Broken (Error Path)

Always-fails implementation with fluent API for configuring errors:

```go
// Configure specific errors
brokenStream := stream.NewBroken().
    WithSaveError(errors.New("save failed")).
    WithEventsForStreamError(errors.New("read failed"))

brokenStore := store.NewBroken().
    WithGetError(errors.New("get failed")).
    WithSetError(errors.New("set failed"))
```

Benefits:
- **Readable**: Intent is clear from method names
- **Flexible**: Configure only what you need
- **Type-safe**: Compile-time checking

### Pattern 3: Recording (Call Verification)

Use when you need to verify specific call details that aren't observable through the public API:

```go
type recordingEmailSender struct {
	calls []emailCall
}

type emailCall struct {
	recipient string
	message   string
}

func (r *recordingEmailSender) Send(to, msg string) error {
	r.calls = append(r.calls, emailCall{recipient: to, message: msg})
	return nil
}

func (r *recordingEmailSender) LastCall() emailCall {
	if len(r.calls) == 0 {
		return emailCall{}
	}
	return r.calls[len(r.calls)-1]
}
```

**Note**: Prefer memory/broken patterns first. Only use recording when you truly need to verify call details.

### Collocation

All test doubles live **alongside** the real implementation:

```
internal/domain/event/stream/
├── esdb.go        // Real implementation
├── memory.go      // In-memory for happy path
├── broken.go      // Always-fails for errors
└── fake.go       // Recording for call verification
```

Each implementation satisfies the same interface:

```go
var _ event.Stream = (*esdb)(nil)
var _ event.Stream = (*memory)(nil)
var _ event.Stream = (*broken)(nil)
```

---

## Principle: Never Expose Internals Just for Testing

**Don't make private fields or methods public just to achieve test coverage. Test as a regular client would use the API.**

### The Problem: Test-Induced Design Damage

> "Always write unit tests as if they were a regular client of the SUT, don't expose state getters solely for satisfying a test."
> — [Enterprise Craftsmanship](https://enterprisecraftsmanship.com/posts/exposing-private-state-to-enable-unit-testing/)

When you expose internal implementation details solely for testing, you:
- Break encapsulation
- Create brittle tests that break during refactoring
- Encourage testing HOW instead of WHAT
- Make future changes harder because internals become part of the public contract

### Decision Tree: When You Can't Test Through Public API

When logic seems untestable through the public interface:

#### 1. Can it be tested through the public interface via observable behavior?
- **YES** → Write tests through the public interface only
- **NO** → Continue to step 2

#### 2. Is the logic significant and independent enough to warrant its own component?
- **YES** → Refactor it into a separate component with its own public API and tests
- **NO** → Continue to step 3

#### 3. Is the logic complex enough that lack of direct testing creates unacceptable risk?
- **YES** → This is a design smell. The component is doing too much. Consider:
  - Extracting the complex logic into a pure function
  - Using functional approaches (operations returning values vs modifying hidden state)
  - Breaking coupling between collaborators
- **NO** → Skip the tests. Trust that the public interface tests provide sufficient coverage.

### Example: Private State

```go
// customer.go
package customer

type Customer struct {
    name   string
    status Status  // Internal state used to calculate discounts
}

func (c *Customer) Promote()            { c.status = Premium }
func (c *Customer) GetDiscount() float64 {
    if c.status == Premium { return 0.15 }
    return 0.0
}
```

❌ **WRONG**: Expose private state or add getter just for tests:
```go
require.Equal(t, Premium, customer.Status)       // Made field public
require.Equal(t, Premium, customer.GetStatus())   // Added getter for tests
```

✅ **CORRECT**: Test observable behavior:
```go
func TestCustomer_Promote(t *testing.T) {
    t.Run("regular customer gets no discount", func(t *testing.T) {
        customer := NewCustomer("Alice")
        require.Equal(t, 0.0, customer.GetDiscount())
    })

    t.Run("promoted customer gets premium discount", func(t *testing.T) {
        customer := NewCustomer("Alice")
        customer.Promote()
        require.Equal(t, 0.15, customer.GetDiscount())
    })
}
```

### Example: Complex Internal Logic

When private logic is too complex to test only through the public interface, extract it as a pure function:

```go
// Instead of making Order.recalculateTotal() public:
func CalculateTotal(items []Item) float64 {
    total := 0.0
    for _, item := range items {
        total += item.Price * (1 - item.Discount)
    }
    return total
}

// Test the pure function directly
func TestCalculateTotal(t *testing.T) {
    t.Run("calculates total with discounts", func(t *testing.T) {
        items := []Item{
            {Price: 100, Discount: 0.1},  // 90
            {Price: 50, Discount: 0.2},   // 40
        }
        require.Equal(t, 130.0, CalculateTotal(items))
    })
}

// And test Order through its public interface
func TestOrder_AddItem(t *testing.T) {
    order := &Order{}
    order.AddItem(Item{Price: 100, Discount: 0.1})
    order.AddItem(Item{Price: 50, Discount: 0.2})
    require.Equal(t, 130.0, order.GetTotal())
}
```

### Red Flags / Green Flags

**You're making a mistake if:**
- Adding a getter/exporting a field just so tests can inspect it
- Using reflection to access unexported fields
- Moving test files into the same package just for private access
- Adding `// exported for testing` comments

**You're doing it right if:**
- All tests call only exported functions/methods
- Tests verify behavior through inputs and observable outputs
- Complex internal logic is extracted to testable pure functions
- You can refactor internals without changing tests

### When to Legitimize Private State

Only make internal state public when:
1. **It becomes a genuine requirement**: External clients actually need to query this information
2. **It's part of the domain model**: The state represents a first-class domain concept
3. **It has independent meaning**: The state has value beyond just internal calculations

If you're only exposing it for tests, that's the wrong reason.

---

## Test Clarity: Include Only Relevant Details

**Balance test clarity: include details necessary to understand what's being tested while hiding implementation noise that obscures the test's purpose.**

Tests should be self-documenting. A reader should understand what's being tested without jumping to helper functions or hunting through setup code.

### The Problem: Two Extremes

#### Extreme 1: Too Much Noise

```go
func TestAccount_GetBalance(t *testing.T) {
    settings := &BankSettings{
        FDICInsured: true, Regulated: true,
        Country: "US", Timezone: "America/New_York", Currency: "USD",
    }
    account := &Account{
        Settings: settings, ID: "acc-123", Balance: 1000,
        Address: "123 Main St", Name: "John Doe", Email: "john@example.com",
        Phone: "+1-555-0100", CreatedAt: time.Now(), Status: "active",
    }

    balance := account.GetBalance()
    require.Equal(t, 1000, balance)
}
```

**Problem**: Too much noise — the reader must mentally filter out irrelevant fields.

#### Extreme 2: Too Much Abstraction

```go
func TestAccount_GetBalance(t *testing.T) {
    account := createAccount()       // Where does 1000 come from?
    balance := account.GetBalance()
    require.Equal(t, 1000, balance)
}
```

**Problem**: Critical details hidden in the helper. Not obvious where `Balance` comes from.

### The Solution: Balanced Visibility

```go
func TestAccount_GetBalance(t *testing.T) {
    account := createAccountWithBalance(1000)

    balance := account.GetBalance()

    require.Equal(t, 1000, balance)
}
```

**When to expose** a detail in the test:
- It directly affects the assertion
- It explains why the expected outcome occurs
- It shows a relationship between input and output
- Hiding it would require jumping to another function to understand the test

**When to hide** a detail in a helper:
- It's required for object construction but irrelevant to the test
- It's the same boilerplate across many tests
- Exposing it adds noise that obscures the test's purpose

### Composable Helpers

```go
// Helper accepts parameters for values that matter
func createAccountWithBalance(balance int) *Account {
    return &Account{
        ID:        deterministicID("test-account"),
        Balance:   balance,
        Status:    "active",
        Validated: true,
        CreatedAt: time.Now(),
    }
}

// Separate helper for different scenarios
func createUnvalidatedAccount() *Account {
    return &Account{
        ID:        deterministicID("test-account"),
        Balance:   0,
        Status:    "active",
        Validated: false,
        CreatedAt: time.Now(),
    }
}
```

### Builder Pattern for Complex Objects

For objects with many fields, use the builder pattern to expose only relevant parameters.

```go
type AccountBuilder struct {
    account *Account
}

func NewAccountBuilder() *AccountBuilder {
    return &AccountBuilder{
        account: &Account{
            ID: deterministicID("test-account"),
            Balance: 0, Status: "active", Validated: true,
            CreatedAt: time.Now(), AccountType: "checking",
        },
    }
}

func (b *AccountBuilder) WithBalance(balance int) *AccountBuilder {
    b.account.Balance = balance
    return b
}

func (b *AccountBuilder) Unvalidated() *AccountBuilder {
    b.account.Validated = false
    return b
}

func (b *AccountBuilder) Build() *Account {
    return b.account
}
```

Usage:
```go
func TestAccount_Withdraw(t *testing.T) {
    t.Run("fails with insufficient funds", func(t *testing.T) {
        balance := 100
        account := NewAccountBuilder().WithBalance(balance).Build()

        err := account.Withdraw(balance + 50)

        require.EqualError(t, err, "insufficient funds")
    })
}
```

---

## Assertion Strictness: Match to What You're Testing

**Not all assertions should be strict. Match assertion strictness to the stability and importance of what you're verifying.**

### Use Strict Assertions For:

```go
// Business logic and data values
require.Equal(t, 1000, account.Balance)
require.Equal(t, "COMPLETED", payment.Status)

// Error codes and types
require.ErrorIs(t, err, vo.ErrInsufficientFunds)

// API contracts
require.Equal(t, 400, response.StatusCode)
require.Equal(t, "INVALID_AMOUNT", response.ErrorCode)
```

### Use Loose Assertions For:

```go
// User-facing display text (may change for UX reasons)
require.Contains(t, response.ButtonText, "Payment")

// Error messages meant for end-users
require.Contains(t, err.Error(), "insufficient funds")

// Log messages and debug output
require.Contains(t, logOutput, "payment processed")
```

### Decision Guide

| What You're Testing | Strictness | Why |
|---------------------|-----------|-----|
| Domain values (amounts, IDs, counts) | Strict | Changes indicate bugs |
| Business state (status, flags) | Strict | Changes indicate bugs |
| Error codes/types | Strict | Changes may break API contracts |
| API field names/structure | Strict | Changes break clients |
| User-facing display text | Loose/None | UX improvements shouldn't fail tests |
| Log/debug messages | Loose | Format changes are harmless |
| Error message wording | Loose | Improved clarity is good |

### Rule of Thumb

**If changing the value would be:**
- A bug → Use strict assertions
- An improvement → Use loose assertions or don't assert
- Breaking for API consumers → Use strict assertions
- Harmless for API consumers → Use loose assertions

---

## Test Helper Patterns

### Var Blocks for Test Setup

```go
func TestCustomerSearch(t *testing.T) {
    var (
        secureCodeStore = securecode.NewInMemorySecureCodeStore()
        repository      = rocket.NewInMemoryRepository()
        searchRepo      = rocket.NewDefaultSearchRepository(secureCodeStore, repository)
    )

    t.Run("finds customer by secure code", func(t *testing.T) {
        // Test using pre-configured dependencies
    })
}
```

### Deterministic Test Data

```go
func deterministicID(seed string) string {
    hash := sha256.Sum256([]byte(seed))
    return fmt.Sprintf("test-%x", hash[:8])
}

func TestAccountCreation(t *testing.T) {
    accountID := deterministicID("account-1")
    customerID := deterministicID("customer-1")

    cmd := &cmd.CreateAccount{
        AccountID:  accountID,
        CustomerID: customerID,
    }

    // Tests are now deterministic and reproducible
}
```

### Table-Driven Tests

```go
func TestValidateAmount(t *testing.T) {
    tests := []struct {
        name      string
        amount    int
        wantError string
    }{
        {
            name:   "accepts positive amount",
            amount: 100,
        },
        {
            name:      "rejects negative amount",
            amount:    -100,
            wantError: "amount must be positive",
        },
        {
            name:      "rejects zero amount",
            amount:    0,
            wantError: "amount must be positive",
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            err := ValidateAmount(tt.amount)

            if tt.wantError != "" {
                require.EqualError(t, err, tt.wantError)
            } else {
                require.NoError(t, err)
            }
        })
    }
}
```

---

## Common Anti-Patterns

### Anti-Pattern 0: Testing Constructor Returns Non-Nil

```go
// BAD: Only tests object exists
func TestNewProjector(t *testing.T) {
    p := projection.NewProjector(proj, store, sub, logger)
    require.NotNil(t, p)  // Useless - other tests would fail if this returned nil
}

// GOOD: Test the actual behavior of the constructed object
func TestProjector_Start(t *testing.T) {
    t.Run("saves checkpoint after processing events", func(t *testing.T) {
        projector := projection.NewProjector(proj, store, sub, logger)
        err := projector.Start(ctx)

        cp, err := store.Get("projection")
        require.Equal(t, uint64(10), cp)
    })
}
```

---

### Anti-Pattern 1: Mocking Internal Dependencies

```go
// BAD: Testing that internal validator was called
func TestProcess_CallsValidator(t *testing.T) {
    mockValidator := &mockAmountValidator{called: false}
    processor := &Processor{validator: mockValidator}
    processor.Process(100, "123")
    require.True(t, mockValidator.called)  // Testing HOW, not WHAT
}

// GOOD: Test the actual validation behavior
func TestProcess(t *testing.T) {
    processor := NewProcessor()

    t.Run("rejects negative amount", func(t *testing.T) {
        err := processor.Process(-100, "123")
        require.EqualError(t, err, "amount must be positive")
    })
}
```

---

### Anti-Pattern 2: Testing Only That a Function Was Called

```go
// BAD: Only verifying invocation count — proves nothing about correctness
func TestNotifyCustomer_CallsSender(t *testing.T) {
    spy := &spyEmailSender{callCount: 0}
    service := &NotificationService{sender: spy}
    service.NotifyCustomer("cust-123", "Hello")
    require.Equal(t, 1, spy.callCount)
}

// GOOD: Verify the actual side effects
func TestNotifyCustomer(t *testing.T) {
    t.Run("sends email with correct recipient and message", func(t *testing.T) {
        recorder := &recordingEmailSender{}
        service := &NotificationService{sender: recorder}

        err := service.NotifyCustomer("cust-123", "Payment received")

        require.NoError(t, err)
        require.Equal(t, "cust-123", recorder.lastRecipient)
        require.Equal(t, "Payment received", recorder.lastMessage)
    })
}
```

---

### Anti-Pattern 3: Testing Trivial Getters and Setters

```go
// BAD: Testing simple field access — no business logic
func TestAccount_SetValidated(t *testing.T) {
    account := &Account{}
    account.SetValidated(true)
    require.True(t, account.IsValidated())
}

// GOOD: Test business behavior that uses those fields
func TestAccount_Withdraw(t *testing.T) {
    t.Run("rejects withdrawal from unvalidated account", func(t *testing.T) {
        account := &Account{balance: 1000, validated: false}
        err := account.Withdraw(100)
        require.EqualError(t, err, "account must be validated before withdrawal")
    })

    t.Run("allows withdrawal with sufficient funds", func(t *testing.T) {
        account := &Account{balance: 1000, validated: true}
        err := account.Withdraw(100)
        require.NoError(t, err)
        require.Equal(t, 900, account.balance)
    })
}
```

---

### Anti-Pattern 4: Loose Assertions Where Strict Are Needed

```go
// BAD: Using Contains for strict requirements
func TestGenerateID(t *testing.T) {
    id := GenerateID()
    require.Contains(t, id, "user-")
}

// GOOD: Use exact assertions
func TestGenerateID(t *testing.T) {
    id := GenerateID()
    require.Regexp(t, `^user-[a-f0-9]{32}$`, id)
}
```

---

### Anti-Pattern 5: Testing Private Methods Directly

```go
// BAD: Exporting private methods for testing
func (a *Account) ValidateAmount(amount int) error { ... }  // exported for tests

// GOOD: Test through public methods that use validation
func TestAccount_Withdraw(t *testing.T) {
    t.Run("rejects negative withdrawal amount", func(t *testing.T) {
        account := &Account{balance: 1000, validated: true}
        err := account.Withdraw(-100)
        require.EqualError(t, err, "amount must be positive")
    })
}
```

---

### Anti-Pattern 6: Over-Mocking

```go
// BAD: Mocking everything
func TestGetUser(t *testing.T) {
    mockDB := &mockDatabase{}
    mockCache := &mockCache{}
    mockLogger := &mockLogger{}
    mockMetrics := &mockMetrics{}
    service := NewService(mockDB, mockCache, mockLogger, mockMetrics)
}

// GOOD: Use real implementations or minimal test doubles
func TestGetUser(t *testing.T) {
    db := NewInMemoryDB()
    service := NewService(db)

    t.Run("returns user when found", func(t *testing.T) {
        db.Insert(User{ID: "123", Name: "Alice"})

        user, err := service.GetUser("123")

        require.NoError(t, err)
        require.Equal(t, "Alice", user.Name)
    })
}
```

---

### Anti-Pattern 7: Tautology Tests and Change Detectors

```go
// BAD (tautology): Expected value comes from the code under test — cannot fail.
func TestDiscount(t *testing.T) {
    expected := ApplyDiscount(100.0, 0.2)
    require.Equal(t, expected, ApplyDiscount(100.0, 0.2))
}

// BAD (change detector): Expected value copied from production — detects change but not correctness.
func TestDefaultTimeout(t *testing.T) {
    require.Equal(t, 30, DefaultTimeout())
}

// GOOD: Domain knowledge — $10.50 = 1050 cents is a mathematical fact.
func TestConvertUSDToCents(t *testing.T) {
    require.Equal(t, int64(1050), ConvertToCents(10.50, "USD"))
}
```

When a change-detector test is the only coverage, prefer replacing it with a higher-level behavioral test whose failure is self-evidently wrong.

---

### Anti-Pattern 8: One Giant Test

```go
// BAD: Testing multiple scenarios in one test — coupled, order-dependent, hard to debug
func TestAccountOperations(t *testing.T) {
    account := &Account{}
    require.False(t, account.IsValidated())
    account.SetValidated(true)
    account.Deposit(100)
    err := account.Withdraw(50)
    require.Equal(t, 50, account.balance)
}

// GOOD: Separate independent test cases
func TestAccount_Withdraw(t *testing.T) {
    t.Run("succeeds with sufficient funds", func(t *testing.T) {
        account := &Account{balance: 1000, validated: true}
        err := account.Withdraw(100)
        require.NoError(t, err)
        require.Equal(t, 900, account.balance)
    })

    t.Run("fails with insufficient funds", func(t *testing.T) {
        account := &Account{balance: 50, validated: true}
        err := account.Withdraw(100)
        require.EqualError(t, err, "insufficient funds")
    })
}
```

---

### Anti-Pattern Detection Checklist

When reviewing tests, check for these red flags:

- [ ] Test names include "Calls", "Invokes", "Uses" (testing HOW, not WHAT)
- [ ] Mocking internal dependencies of the subject under test
- [ ] Asserting on call counts without verifying behavior
- [ ] Testing getters/setters without business logic
- [ ] Using `require.Contains` where exact match is needed
- [ ] Not asserting on error messages
- [ ] Exporting private methods just for testing
- [ ] Heavy mocking setup (>3 mocks)
- [ ] Tests break when refactoring without behavior changes
- [ ] Expected values copied from production code without domain justification (change detector)
- [ ] Expected values computed from the code under test at runtime (tautology)

---

## Quick Testing Checklist

**Fidelity (catches defects):**
- [ ] Covers critical code paths (especially error paths)
- [ ] Includes comprehensive assertions about expected outcomes
- [ ] Tests edge cases and boundary conditions
- [ ] Asserts on actual values, not just that functions ran
- [ ] Expected values have independent verification (domain knowledge, not copied from production code)

**Resilience (survives harmless changes):**
- [ ] Testing through public/exported API only
- [ ] Using fakes/in-memory implementations instead of mocks when possible
- [ ] Using broken implementations to test error paths
- [ ] Not verifying unnecessary dependency interactions
- [ ] Tests are deterministic (no flakiness)

**Precision (pinpoints problems):**
- [ ] Test names describe the specific scenario clearly
- [ ] One behavior per test (separated with subtests)
- [ ] Using appropriate assertion strictness (strict for contracts, loose for presentation)
- [ ] Only relevant details are visible in the test

**General:**
- [ ] Asserting on actual behavior (outputs, side effects, state)
- [ ] Not testing trivial code (getters/setters)
- [ ] Not just verifying functions were called
- [ ] Tests are independent and can run in any order
- [ ] Both happy path and error cases are covered

---

## Summary

| Practice | Instead Of | Do This |
|----------|-----------|---------|
| **Test public API** | Spying on internal methods | Call exported functions, verify results |
| **Verify behavior** | Counting function calls | Assert on outputs, side effects, state changes |
| **Skip trivial tests** | Testing getters/setters | Test business logic that uses those values |
| **Match assertion strictness** | Always strict or always loose | Strict for contracts, loose for presentation |
| **Expose relevant details** | Hide everything in helpers | Show values that affect assertions |
| **Use real implementations** | Mock everything | In-memory implementations when possible |
| **Test error paths** | Mock errors | Use broken implementations |
| **Independent verification** | Copy expected values from production code | Derive expected values from domain knowledge or specs |

**Goal: 100% coverage of business behavior through public API, not implementation details.**
