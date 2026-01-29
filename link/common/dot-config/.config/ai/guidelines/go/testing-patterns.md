# Go Testing Patterns

## Core Principle: Test Behavior Through Public API Only

**Never test implementation details. Test observable behavior through exported functions and methods.**

Tests should verify **what** the system does (observable behaviors), not **how** it does it (implementation details). This creates tests that are more resilient to refactoring and focuses on business value.

### Why This Matters
- Tests remain valid during refactoring
- Tests document intended behavior
- Tests catch genuine bugs, not implementation changes

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

❌ **Low Fidelity:**
```go
// Only checks function was called, not what it did
require.Equal(t, 1, spy.callCount)
```

✅ **High Fidelity:**
```go
// Verifies actual behavior and values
require.NoError(t, err)
require.Equal(t, expectedBalance, account.Balance)
require.Equal(t, "COMPLETED", transaction.Status)
```

### 2. Resilience: Tests Shouldn't Break from Harmless Changes
**Resilient tests only fail when breaking changes are made to the code under test.**

Achieve resilience by:
- Testing public APIs rather than internals
- Preferring fakes and in-memory implementations over mocks
- Avoiding verification of unnecessary dependency interactions
- Testing behavior, not implementation

❌ **Brittle (Low Resilience):**
```go
// Breaks if we inline validation or refactor how validation happens
require.True(t, mockValidator.called)
```

✅ **Resilient (High Resilience):**
```go
// Survives refactoring as long as behavior is preserved
require.EqualError(t, err, "amount must be positive")
```

**Note:** Flaky tests have poor resilience. Tests should be deterministic.

### 3. Precision: Failed Tests Should Pinpoint Problems
**High-precision tests tell you exactly where the defect lies.**

Achieve precision by:
- Keeping tests small and focused (one behavior per test)
- Using descriptive test names that explain what's being tested
- For integration tests, validating state at every boundary
- Using strict, specific assertions

❌ **Imprecise:**
```go
// Which validation failed?
func TestValidation(t *testing.T) {
    require.NoError(t, ValidateAll(data))
}
```

✅ **Precise:**
```go
func TestValidation(t *testing.T) {
    t.Run("rejects negative amounts", func(t *testing.T) {
        err := ValidateAmount(-100)
        require.EqualError(t, err, "amount must be positive")
    })

    t.Run("rejects invalid CVV", func(t *testing.T) {
        err := ValidateCVV("12")
        require.EqualError(t, err, "CVV must be 3 or 4 digits")
    })
}
```

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

// Table-driven tests for validation
for _, tc := range []struct {
    scenario      string
    prepare       func(request *provisioning.PostRequest) *provisioning.PostRequest
    expectedError string
}{...}
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

## Test Double Organization

Test doubles and real implementations are **co-located in the same package**:

```go
domain/event/stream/
├── esdb.go        // Real event.Stream implementation
├── memory.go      // Real event.Stream implementation
├── broken.go      // Broken event.Stream implementation for tests
└── fake.go        // Fake event.Stream implementation for tests

domain/command/bus/
├── inmemory.go    // Real command.Bus implementation
└── fake.go        // Fake command.Bus implementation for tests

domain/command/handler/
├── inmemory.go    // Real command.Handler implementation
└── fake.go        // Fake command.Handler implementation for tests

// All implementations (real and fake) implement the same interface
var _ command.Bus = (*inmemory.Bus)(nil)
var _ command.Bus = (*fake.Bus)(nil)
var _ event.Stream = (*esdb)(nil)
var _ event.Stream = (*fake.Stream)(nil)

// Test doubles have additional methods for setup and verification
func (f *FakeStream) WithError(err error) *FakeStream {...}
func (f *FakeBus) TriggeredWithCommand() *domain.Command {...}
```

---

## Testing Observable Behaviors: Examples

### Example 1: Test Validation Behavior, Not Internal Calls

❌ **Bad - Testing Implementation Details:**
```go
// BAD: Testing that internal validator was called
func TestProcess_CallsValidator(t *testing.T) {
    mockValidator := &mockAmountValidator{called: false}
    processor := &Processor{validator: mockValidator}

    processor.Process(100, "123")

    // Testing HOW, not WHAT
    require.True(t, mockValidator.called)
}
```

**Problem**: Test breaks if we refactor to inline validation or change how validation happens, even though behavior stays the same.

✅ **Good - Testing Observable Behaviors:**
```go
// GOOD: Testing through public API
func TestProcess(t *testing.T) {
    processor := NewProcessor()

    t.Run("rejects negative amount", func(t *testing.T) {
        err := processor.Process(-100, "123")

        require.EqualError(t, err, "amount must be positive")
    })

    t.Run("rejects invalid CVV", func(t *testing.T) {
        err := processor.Process(100, "12")

        require.EqualError(t, err, "CVV must be 3 or 4 digits")
    })

    t.Run("succeeds with valid inputs", func(t *testing.T) {
        err := processor.Process(100, "123")

        require.NoError(t, err)
    })
}
```

**Why it's better**: Tests verify actual business rules. Refactoring internal validation doesn't break tests as long as behavior is preserved.

### Example 2: Verify Side Effects, Not Just Invocations

❌ **Bad - Only Checking Call Happened:**
```go
// BAD: Only verifying invocation count
func TestNotifyCustomer_CallsSender(t *testing.T) {
    spy := &spyEmailSender{callCount: 0}
    service := &NotificationService{sender: spy}

    service.NotifyCustomer("cust-123", "Hello")

    // This proves nothing about correctness
    require.Equal(t, 1, spy.callCount)
}
```

**Problem**: Test passes even if we send wrong recipient, wrong message, or ignore errors.

✅ **Good - Verify Actual Side Effects:**
```go
// GOOD: Testing observable outcomes
func TestNotifyCustomer(t *testing.T) {
    t.Run("sends email with correct recipient and message", func(t *testing.T) {
        recorder := &recordingEmailSender{}
        service := &NotificationService{sender: recorder}

        err := service.NotifyCustomer("cust-123", "Payment received")

        require.NoError(t, err)
        require.Equal(t, "cust-123", recorder.lastRecipient)
        require.Equal(t, "Payment received", recorder.lastMessage)
    })

    t.Run("propagates sender errors", func(t *testing.T) {
        failingSender := &failingEmailSender{err: errors.New("SMTP unavailable")}
        service := &NotificationService{sender: failingSender}

        err := service.NotifyCustomer("cust-123", "Hello")

        require.EqualError(t, err, "SMTP unavailable")
    })
}
```

### Example 3: Test Business Behavior, Not Trivial Getters/Setters

❌ **Bad - Testing Simple Accessors:**
```go
// BAD: Testing trivial getters/setters
func TestAccount_SetValidated(t *testing.T) {
    account := &Account{}
    account.SetValidated(true)
    // This test adds no value
    require.True(t, account.IsValidated())
}
```

**Problem**: Tests add no value. They test language features (field assignment, zero values) not business logic.

✅ **Good - Test Business Behavior:**
```go
// GOOD: Testing business rules
func TestAccount_Withdraw(t *testing.T) {
    t.Run("rejects withdrawal from unvalidated account", func(t *testing.T) {
        account := &Account{balance: 1000, validated: false}

        err := account.Withdraw(100)

        require.EqualError(t, err, "account must be validated before withdrawal")
    })

    t.Run("allows withdrawal from validated account with sufficient funds", func(t *testing.T) {
        account := &Account{balance: 1000, validated: true}

        err := account.Withdraw(100)

        require.NoError(t, err)
        require.Equal(t, 900, account.balance)
    })

    t.Run("rejects withdrawal exceeding balance", func(t *testing.T) {
        account := &Account{balance: 100, validated: true}

        err := account.Withdraw(500)

        require.EqualError(t, err, "insufficient funds")
    })
}
```

**Why it's better**: Tests verify business rules. The `validated` field matters only because it affects withdrawal behavior.

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
- Violate the principle of testing as a regular client

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

### Example: Private State That Can't Be Directly Tested

```go
// customer.go
package customer

type Status int

const (
    Regular Status = iota
    Premium
)

type Customer struct {
    name   string
    status Status  // Internal state used to calculate discounts
}

func NewCustomer(name string) *Customer {
    return &Customer{
        name:   name,
        status: Regular,
    }
}

func (c *Customer) Promote() {
    c.status = Premium
}

func (c *Customer) GetDiscount() float64 {
    if c.status == Premium {
        return 0.15  // 15% for premium
    }
    return 0.0  // 0% for regular
}
```

#### ❌ WRONG: Expose Private State for Testing

```go
// customer.go - BAD: Exposing internal state
type Customer struct {
    name   string
    Status Status  // Made public just for testing
}

// Or even worse - adding a getter just for tests
func (c *Customer) GetStatus() Status {
    return c.status  // Getter added solely for test assertions
}

// customer_test.go - BAD: Testing internal state
func TestCustomer_Promote(t *testing.T) {
    customer := NewCustomer("Alice")

    customer.Promote()

    // Testing implementation, not behavior
    require.Equal(t, Premium, customer.Status)
    // Or: require.Equal(t, Premium, customer.GetStatus())
}
```

**Why this is wrong:**
- Tests internal implementation, not observable behavior
- Breaks encapsulation - clients can now access/modify Status
- Test breaks if we change how premium status is represented internally
- Doesn't verify the actual business outcome (discount calculation)

#### ✅ CORRECT: Test Observable Behavior

```go
// customer_test.go - GOOD: Testing through observable behavior
func TestCustomer_Promote(t *testing.T) {
    t.Run("regular customer gets no discount", func(t *testing.T) {
        customer := NewCustomer("Alice")

        discount := customer.GetDiscount()

        require.Equal(t, 0.0, discount)
    })

    t.Run("promoted customer gets premium discount", func(t *testing.T) {
        customer := NewCustomer("Alice")

        customer.Promote()
        discount := customer.GetDiscount()

        require.Equal(t, 0.15, discount)
    })
}
```

**Why this is better:**
- Tests the actual business outcome (discount amount)
- Doesn't depend on internal status representation
- Test survives refactoring (e.g., changing Status to string, adding tiers, etc.)
- Tests as a regular client would use the API

### Example: Complex Internal Logic

```go
// order.go
package order

type Order struct {
    items []Item
    total float64  // Cached total
}

func (o *Order) AddItem(item Item) {
    o.items = append(o.items, item)
    o.recalculateTotal()  // Private method
}

func (o *Order) recalculateTotal() {
    // Complex calculation logic
    total := 0.0
    for _, item := range o.items {
        total += item.Price * (1 - item.Discount)
    }
    o.total = total
}

func (o *Order) GetTotal() float64 {
    return o.total
}
```

#### ❌ WRONG: Make Private Method Public to Test Calculation

```go
// DON'T DO THIS
func (o *Order) RecalculateTotal() {  // Made public for testing
    // ...
}

// order_test.go - BAD
func TestOrder_RecalculateTotal(t *testing.T) {
    order := &Order{items: []Item{{Price: 100, Discount: 0.1}}}

    order.RecalculateTotal()

    require.Equal(t, 90.0, order.total)  // Accessing private field
}
```

#### ✅ CORRECT Approach A: Extract Complex Logic to Pure Function

```go
// order.go
package order

type Order struct {
    items []Item
    total float64
}

func (o *Order) AddItem(item Item) {
    o.items = append(o.items, item)
    o.total = CalculateTotal(o.items)  // Use testable pure function
}

func (o *Order) GetTotal() float64 {
    return o.total
}

// Pure function - independently testable
func CalculateTotal(items []Item) float64 {
    total := 0.0
    for _, item := range items {
        total += item.Price * (1 - item.Discount)
    }
    return total
}

// order_test.go - Test pure function separately
func TestCalculateTotal(t *testing.T) {
    t.Run("calculates total with discounts", func(t *testing.T) {
        items := []Item{
            {Price: 100, Discount: 0.1},  // 90
            {Price: 50, Discount: 0.2},   // 40
        }

        total := CalculateTotal(items)

        require.Equal(t, 130.0, total)
    })
}

// Test Order through public interface
func TestOrder_AddItem(t *testing.T) {
    order := &Order{}

    order.AddItem(Item{Price: 100, Discount: 0.1})
    order.AddItem(Item{Price: 50, Discount: 0.2})

    require.Equal(t, 130.0, order.GetTotal())
}
```

**Benefits:**
- Complex calculation logic has direct unit tests
- `Order` doesn't expose internals
- Pure function is easier to test (no state, no dependencies)
- Clear separation between state management and calculation

#### ✅ CORRECT Approach B: Test Only Through Observable Outcomes

If the calculation is simple enough:

```go
// order_test.go - Test only through public interface
func TestOrder(t *testing.T) {
    t.Run("calculates total for single item", func(t *testing.T) {
        order := &Order{}

        order.AddItem(Item{Price: 100, Discount: 0})

        require.Equal(t, 100.0, order.GetTotal())
    })

    t.Run("applies discounts correctly", func(t *testing.T) {
        order := &Order{}

        order.AddItem(Item{Price: 100, Discount: 0.25})

        require.Equal(t, 75.0, order.GetTotal())
    })

    t.Run("sums multiple items", func(t *testing.T) {
        order := &Order{}

        order.AddItem(Item{Price: 100, Discount: 0.1})
        order.AddItem(Item{Price: 50, Discount: 0.2})

        require.Equal(t, 130.0, order.GetTotal())
    })
}
```

### Red Flags: You're About to Make a Mistake If...

- ❌ You're adding a getter method just so tests can inspect a private field
- ❌ You're capitalizing a private field/method name just for test access
- ❌ You're using reflection in tests to access unexported fields
- ❌ You're moving test files into the same package just to access private members
- ❌ You're adding `// exported for testing` comments
- ❌ You're thinking "I need to verify this internal state changed correctly"

### Green Flags: You're Doing It Right If...

- ✅ All tests call only exported functions/methods
- ✅ Tests verify behavior through inputs and observable outputs
- ✅ Complex internal logic is either:
  - Extracted to separate, testable pure functions
  - Tested indirectly through public behavior with comprehensive scenarios
- ✅ Private fields remain private and tests don't inspect them
- ✅ You can refactor internal implementation without changing tests
- ✅ Tests read like specifications: "when X happens, then Y should result"

### When to Legitimize Private State

Only make internal state public when:
1. **It becomes a genuine requirement**: External clients actually need to query this information
2. **It's part of the domain model**: The state represents a first-class domain concept
3. **It has independent meaning**: The state has value beyond just internal calculations

If you're only exposing it for tests, that's the wrong reason.

---

## Test Clarity: Include Only Relevant Details

**Balance test clarity: include details necessary to understand what's being tested while hiding implementation noise.**

### When to Expose Details

Expose a detail in the test if:
- ✅ It directly affects the assertion
- ✅ It explains why the expected outcome occurs
- ✅ It shows a relationship between input and output
- ✅ Hiding it would require jumping to another function to understand the test

### When to Hide Details

Hide a detail in a helper if:
- ✅ It's required for object construction but irrelevant to the test
- ✅ It's the same boilerplate across many tests
- ✅ It's an implementation detail that doesn't affect behavior
- ✅ Exposing it adds noise that obscures the test's purpose

### Example: Making Data Flow Explicit

❌ **Bad - Hidden Relationships:**
```go
func TestAccount_Withdraw(t *testing.T) {
    account := createAccount()

    err := account.Withdraw(1500)

    require.EqualError(t, err, "insufficient funds")
}
```

✅ **Good - Visible Relationships:**
```go
func TestAccount_Withdraw(t *testing.T) {
    balance := 1000
    account := createAccountWithBalance(balance)

    err := account.Withdraw(balance + 500)

    require.EqualError(t, err, "insufficient funds")
}
```

**Why it's better**: The test explicitly shows `balance + 500` exceeds the account balance. The relationship is clear.

---

## Assertion Strictness: Match to What You're Testing

**Not all assertions should be strict. Match assertion strictness to the stability and importance of what you're verifying.**

### Use Strict Assertions For:

**Business logic and data values:**
```go
✅ require.Equal(t, 1000, account.Balance)
✅ require.Equal(t, "COMPLETED", payment.Status)
✅ require.Equal(t, customerID, payment.CustomerID)
```

**Error codes and types:**
```go
✅ require.ErrorIs(t, err, vo.ErrInsufficientFunds)
✅ require.Equal(t, vo.AmountMustBePositive, err)
```

**API contracts:**
```go
✅ require.Equal(t, 400, response.StatusCode)
✅ require.Equal(t, "INVALID_AMOUNT", response.ErrorCode)
```

### Use Loose Assertions For:

**User-facing display text (may change for UX reasons):**
```go
// ✅ Good - Just ensure it exists
require.NotEmpty(t, response.ButtonText)

// ✅ Good - Verify key information is present
require.Contains(t, response.ButtonText, "Payment")

// ❌ Bad - Breaks when UX updates copy
require.Equal(t, "Submit Payment Now", response.ButtonText)
```

**Error messages meant for end-users:**
```go
// ✅ Good - Verify key information is present
require.Error(t, err)
require.Contains(t, err.Error(), "insufficient funds")
require.Contains(t, err.Error(), accountID)

// ❌ Bad - Breaks when we improve error message clarity
require.EqualError(t, err, "Insufficient funds. Please add money to your account and try again.")
```

**Log messages and debug output:**
```go
// ✅ Good - Verify key information is logged
require.Contains(t, logOutput, accountID)
require.Contains(t, logOutput, "payment processed")
require.Contains(t, logOutput, strconv.Itoa(amount))

// ❌ Bad - Breaks when log format changes
require.Equal(t, "Payment 123 processed for account ABC at 2024-01-01", logOutput)
```

### The Trade-off: Resilience vs. Precision

Strict assertions increase **precision** (failures pinpoint exactly what changed) but decrease **resilience** (tests break from harmless changes).

**Decision Guide:**

| What You're Testing | Strictness | Why |
|---------------------|-----------|-----|
| Domain values (amounts, IDs, counts) | Strict | Changes indicate bugs |
| Business state (status, flags) | Strict | Changes indicate bugs |
| Error codes/types | Strict | Changes may break API contracts |
| API field names/structure | Strict | Changes break clients |
| User-facing display text | Loose/None | UX improvements shouldn't fail tests |
| Log/debug messages | Loose | Format changes are harmless |
| Error message wording | Loose | Improved clarity is good |

### Example: Validation Error Response

```go
// Domain API - strict assertions on contract
func TestValidateAmount(t *testing.T) {
    err := ValidateAmount(-100)

    // Strict: Error type is your API contract
    require.ErrorIs(t, err, vo.ErrInsufficientFunds)
}

// HTTP API - mixed assertions
func TestPaymentEndpoint(t *testing.T) {
    response := callAPI(PaymentRequest{Amount: -100})

    // Strict: API contract
    require.Equal(t, 400, response.StatusCode)
    require.Equal(t, "INVALID_AMOUNT", response.ErrorCode)

    // Loose: User-facing message (may improve for UX)
    require.Contains(t, response.ErrorMessage, "amount")
    require.Contains(t, response.ErrorMessage, "positive")
}
```

### Rule of Thumb

**If changing the value would be:**
- A bug → Use strict assertions
- An improvement → Use loose assertions or don't assert
- Breaking for API consumers → Use strict assertions
- Harmless for API consumers → Use loose assertions

---

## Test Helper Patterns

### Recording Test Doubles

```go
type recordingEmailSender struct {
    calls []emailCall
}

type emailCall struct {
    recipient string
    message   string
}

func (r *recordingEmailSender) Send(to, msg string) error {
    r.calls = append(r.calls, emailCall{
        recipient: to,
        message:   msg,
    })
    return nil
}

func (r *recordingEmailSender) LastCall() emailCall {
    if len(r.calls) == 0 {
        return emailCall{}
    }
    return r.calls[len(r.calls)-1]
}
```

### Failing Test Doubles

```go
type failingEmailSender struct {
    err error
}

func NewFailingEmailSender(err error) *failingEmailSender {
    return &failingEmailSender{err: err}
}

func (f *failingEmailSender) Send(to, msg string) error {
    return f.err
}
```

### In-Memory Implementations

```go
type InMemoryUserRepository struct {
    users  map[string]*User
    nextID int
}

func NewInMemoryUserRepository() *InMemoryUserRepository {
    return &InMemoryUserRepository{
        users:  make(map[string]*User),
        nextID: 1,
    }
}

func (r *InMemoryUserRepository) Save(user *User) error {
    if user.ID == "" {
        user.ID = fmt.Sprintf("user-%d", r.nextID)
        r.nextID++
    }
    r.users[user.ID] = user
    return nil
}

func (r *InMemoryUserRepository) FindByID(id string) (*User, error) {
    user, ok := r.users[id]
    if !ok {
        return nil, errors.New("user not found")
    }
    return user, nil
}
```

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

### Parameterized Helpers

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

## Common Anti-Patterns to Avoid

1. **Testing internal calls** - Don't spy on whether internal methods were invoked
2. **Call count assertions** - Don't just verify a function ran; verify what it did
3. **Testing trivial code** - Skip getters/setters; test business logic that uses them
4. **Mocking the subject** - Don't mock the thing you're testing
5. **Over-mocking** - Use real objects when possible (prefer in-memory implementations)
6. **Too much noise** - Don't expose irrelevant setup details that obscure the test
7. **Too much abstraction** - Don't hide critical values in helper functions
8. **Inappropriate assertion strictness** - Match assertion strictness to what you're testing (see Assertion Strictness section above)
9. **Testing private methods directly** - Test through public API that uses them
10. **One giant test** - Separate independent scenarios with subtests

---

## Quick Testing Checklist

Before writing a test, verify the three essential qualities:

**Fidelity (catches defects):**
- [ ] Covers critical code paths (especially error paths)
- [ ] Includes comprehensive assertions about expected outcomes
- [ ] Tests edge cases and boundary conditions
- [ ] Asserts on actual values, not just that functions ran

**Resilience (survives harmless changes):**
- [ ] Testing through public/exported API only
- [ ] Using fakes/in-memory implementations instead of mocks when possible
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

## Key Benefits

- **Refactoring Safety:** Tests survive internal changes when observable behavior remains the same
- **Business Focus:** Tests verify user-facing behavior and business rules
- **Test Stability:** Tests intent rather than implementation, reducing maintenance

**Rule of thumb:** If you can change the internal implementation without changing the test, you're testing the right behavior. If the test breaks when you rename a private field or change an internal method, you're testing implementation details.

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

**Goal: 100% coverage of business behavior through public API, not implementation details.**
