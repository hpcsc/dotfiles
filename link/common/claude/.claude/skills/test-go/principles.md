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

## Summary

| Practice | Instead Of | Do This |
|----------|-----------|---------|
| **Test public API** | Spying on internal methods | Call exported functions, verify results |
| **Verify behavior** | Counting function calls | Assert on outputs, side effects, state changes |
| **Skip trivial tests** | Testing getters/setters | Test business logic that uses those values |

**Goal: 100% coverage through business behavior, not implementation details.**
