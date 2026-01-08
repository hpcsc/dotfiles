# Common Testing Anti-Patterns

## Anti-Pattern 1: Mocking Internal Dependencies

### Problem
```go
// BAD: Testing that internal validator was called
func TestProcess_CallsValidator(t *testing.T) {
    mockValidator := &mockAmountValidator{called: false}
    processor := &Processor{validator: mockValidator}

    processor.Process(100, "123")

    require.True(t, mockValidator.called)
}
```

### Why It's Wrong
- Breaks when refactoring internal structure
- Doesn't verify actual behavior
- Tests implementation, not requirements

### Fix
```go
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

## Anti-Pattern 2: Testing Only That a Function Was Called

### Problem
```go
// BAD: Only verifying invocation count
func TestNotifyCustomer_CallsSender(t *testing.T) {
    spy := &spyEmailSender{callCount: 0}
    service := &NotificationService{sender: spy}

    service.NotifyCustomer("cust-123", "Hello")

    require.Equal(t, 1, spy.callCount)
}
```

### Why It's Wrong
- Doesn't verify correct data was passed
- Doesn't verify errors are handled
- Test passes even with wrong behavior

### Fix
```go
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

## Anti-Pattern 3: Testing Trivial Getters and Setters

### Problem
```go
// BAD: Testing simple field access
func TestAccount_SetValidated(t *testing.T) {
    account := &Account{}
    account.SetValidated(true)
    require.True(t, account.IsValidated())
}

func TestAccount_GetBalance(t *testing.T) {
    account := &Account{balance: 100}
    require.Equal(t, 100, account.GetBalance())
}
```

### Why It's Wrong
- No business logic to test
- Tests language features, not your code
- Adds maintenance burden without value

### Fix
```go
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

## Anti-Pattern 4: Loose Assertions

### Problem
```go
// BAD: Using Contains for strict requirements
func TestGenerateID(t *testing.T) {
    id := GenerateID()
    require.Contains(t, id, "user-")
}

// BAD: Not checking error messages
func TestValidate(t *testing.T) {
    err := Validate(-10)
    require.Error(t, err)
}
```

### Why It's Wrong
- `require.Contains` passes for wrong results
- Missing error message validation
- Doesn't catch subtle bugs

### Fix
```go
// GOOD: Use exact assertions
func TestGenerateID(t *testing.T) {
    id := GenerateID()
    require.Regexp(t, `^user-[a-f0-9]{32}$`, id)
}

func TestValidate(t *testing.T) {
    err := Validate(-10)
    require.EqualError(t, err, "amount must be positive")
}
```

---

## Anti-Pattern 5: Testing Private Methods Directly

### Problem
```go
// BAD: Exporting private methods for testing
func (a *Account) ValidateAmount(amount int) error { // exported for tests
    if amount < 0 {
        return errors.New("amount must be positive")
    }
    return nil
}

func TestAccount_ValidateAmount(t *testing.T) {
    account := &Account{}
    err := account.ValidateAmount(-10)
    require.Error(t, err)
}
```

### Why It's Wrong
- Pollutes public API
- Creates maintenance burden
- Tests aren't resilient to refactoring

### Fix
```go
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

## Anti-Pattern 6: Over-Mocking

### Problem
```go
// BAD: Mocking everything including the database
func TestGetUser(t *testing.T) {
    mockDB := &mockDatabase{}
    mockCache := &mockCache{}
    mockLogger := &mockLogger{}
    mockMetrics := &mockMetrics{}

    service := NewService(mockDB, mockCache, mockLogger, mockMetrics)
    // Complex test setup...
}
```

### Why It's Wrong
- Brittle: breaks when adding dependencies
- Complex: hard to understand and maintain
- Doesn't test real integration

### Fix
```go
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

## Anti-Pattern 7: One Giant Test

### Problem
```go
// BAD: Testing multiple scenarios in one test
func TestAccountOperations(t *testing.T) {
    account := &Account{}

    // Test creation
    require.False(t, account.IsValidated())

    // Test validation
    account.SetValidated(true)
    require.True(t, account.IsValidated())

    // Test deposit
    account.Deposit(100)
    require.Equal(t, 100, account.balance)

    // Test withdrawal
    err := account.Withdraw(50)
    require.NoError(t, err)
    require.Equal(t, 50, account.balance)
}
```

### Why It's Wrong
- Hard to identify which scenario failed
- Tests are coupled and order-dependent
- Can't run scenarios independently

### Fix
```go
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

## Detection Checklist

When reviewing tests, check for these smells:

- [ ] Test names include "Calls", "Invokes", "Uses" (testing HOW, not WHAT)
- [ ] Mocking internal dependencies of the subject under test
- [ ] Asserting on call counts without verifying behavior
- [ ] Testing getters/setters without business logic
- [ ] Using `require.Contains` where exact match is needed
- [ ] Not asserting on error messages
- [ ] Exporting private methods just for testing
- [ ] Heavy mocking setup (>3 mocks)
- [ ] Tests break when refactoring without behavior changes
