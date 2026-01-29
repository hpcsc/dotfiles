# Go Testing Principles: Behavior Over Implementation

## Principle: Test Through Public API Only

**Never test implementation details. Test behavior through exported functions and methods.**

### Why This Matters
- Tests remain valid during refactoring
- Tests document intended behavior
- Tests catch genuine bugs, not implementation changes

### Wrong: Testing Implementation Details

```go
// payment.go
package payment

type Processor struct {
    validator *amountValidator
}

func (p *Processor) Process(amount int, cvv string) error {
    if err := p.validator.validate(amount); err != nil {
        return err
    }
    // ... process payment
    return nil
}

// payment_test.go - BAD: Testing internal validator was called
func TestProcess_CallsValidator(t *testing.T) {
    mockValidator := &mockAmountValidator{called: false}
    processor := &Processor{validator: mockValidator}

    processor.Process(100, "123")

    // Testing HOW, not WHAT
    require.True(t, mockValidator.called, "validator should be called")
}
```

**Problem**: This test breaks if we refactor to inline validation or change how validation happens, even though the behavior stays the same.

### Correct: Testing Observable Behavior

```go
// payment_test.go - GOOD: Testing through public API
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

**Why it's better**: Tests verify the actual business rules. Refactoring internal validation doesn't break tests as long as behavior is preserved.

---

## Principle: Verify Behavior, Not Invocations

**Don't mock the thing you're testing just to verify it was invoked.**

### Wrong: Verifying Invocation Without Behavior

```go
// notification.go
type NotificationService struct {
    sender EmailSender
}

func (n *NotificationService) NotifyCustomer(customerID string, message string) error {
    return n.sender.Send(customerID, message)
}

// notification_test.go - BAD: Only checking the call happened
func TestNotifyCustomer_CallsSender(t *testing.T) {
    spy := &spyEmailSender{}
    service := &NotificationService{sender: spy}

    service.NotifyCustomer("cust-123", "Hello")

    // This proves nothing about correctness
    require.Equal(t, 1, spy.callCount)
}

type spyEmailSender struct {
    callCount int
}

func (s *spyEmailSender) Send(to, msg string) error {
    s.callCount++
    return nil
}
```

**Problem**: Test passes even if we send wrong recipient, wrong message, or ignore errors. It only proves the method ran.

### Correct: Verify Actual Behavior and Side Effects

```go
// notification_test.go - GOOD: Testing observable outcomes
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

type recordingEmailSender struct {
    lastRecipient string
    lastMessage   string
}

func (r *recordingEmailSender) Send(to, msg string) error {
    r.lastRecipient = to
    r.lastMessage = msg
    return nil
}
```

**Why it's better**: Tests verify the actual behavior - correct data was sent and errors are handled properly.

---

## Principle: Test Business Behavior, Not Trivial Code

**Don't write tests for simple field access. Test business behavior that uses those fields.**

### Wrong: Testing Simple Accessors

```go
// account.go
type Account struct {
    validated bool
    balance   int
}

func (a *Account) SetValidated(v bool) {
    a.validated = v
}

func (a *Account) IsValidated() bool {
    return a.validated
}

// account_test.go - BAD: Testing trivial getters/setters
func TestAccount_SetValidated(t *testing.T) {
    account := &Account{}

    account.SetValidated(true)

    // This test adds no value
    require.True(t, account.IsValidated())
}

func TestAccount_IsValidated_DefaultsFalse(t *testing.T) {
    account := &Account{}

    // Testing Go's zero value behavior
    require.False(t, account.IsValidated())
}
```

**Problem**: These tests add no value. They test language features (field assignment, zero values) not business logic.

### Correct: Test Business Behavior That Depends on State

```go
// account.go
type Account struct {
    validated bool
    balance   int
}

func (a *Account) Withdraw(amount int) error {
    if !a.validated {
        return errors.New("account must be validated before withdrawal")
    }
    if amount > a.balance {
        return errors.New("insufficient funds")
    }
    a.balance -= amount
    return nil
}

// account_test.go - GOOD: Testing business rules
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

## Summary

| Practice | Instead Of | Do This |
|----------|-----------|---------|
| **Test public API** | Spying on internal methods | Call exported functions, verify results |
| **Verify behavior** | Counting function calls | Assert on outputs, side effects, state changes |
| **Skip trivial tests** | Testing getters/setters | Test business logic that uses those values |
| **Never expose internals** | Adding getters for testing | Extract to pure functions OR test through observable behavior |
| **Test as a client** | Inspecting private state | Verify the outcomes that matter to real users |

**Goal: Tests that verify business behavior and survive refactoring.**
