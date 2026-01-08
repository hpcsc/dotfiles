# Test Clarity: Include Only Relevant Details

## The Principle

**Balance test clarity: include details necessary to understand what's being tested while hiding implementation noise that obscures the test's purpose.**

Tests should be self-documenting. A reader should understand what's being tested without jumping to helper functions or hunting through setup code.

---

## The Problem: Two Extremes

### Extreme 1: Too Much Noise (Bad)

```go
func TestAccount_GetBalance(t *testing.T) {
    settings := &BankSettings{
        FDICInsured: true,
        Regulated:   true,
        Country:     "US",
        Timezone:    "America/New_York",
        Currency:    "USD",
    }
    account := &Account{
        Settings:    settings,
        ID:          "acc-123",
        Balance:     1000,
        Address:     "123 Main St, New York, NY 10001",
        Name:        "John Doe",
        Email:       "john@example.com",
        Phone:       "+1-555-0100",
        CreatedAt:   time.Now(),
        UpdatedAt:   time.Now(),
        Status:      "active",
        AccountType: "checking",
    }

    balance := account.GetBalance()

    require.Equal(t, 1000, balance)
}
```

**Problem**: Too much noise in the account creation code makes it hard to tell which details are relevant to the test. The reader must mentally filter out irrelevant fields.

### Extreme 2: Too Much Abstraction (Also Bad)

```go
func TestAccount_GetBalance(t *testing.T) {
    account := createAccount()

    balance := account.GetBalance()

    require.Equal(t, 1000, balance)
}

func createAccount() *Account {
    settings := &BankSettings{
        FDICInsured: true,
        Regulated:   true,
        Country:     "US",
        Timezone:    "America/New_York",
        Currency:    "USD",
    }
    return &Account{
        Settings:    settings,
        ID:          "acc-123",
        Balance:     1000,
        Address:     "123 Main St",
        Name:        "John Doe",
        Email:       "john@example.com",
        Phone:       "+1-555-0100",
        CreatedAt:   time.Now(),
        UpdatedAt:   time.Now(),
        Status:      "active",
        AccountType: "checking",
    }
}
```

**Problem**: Critical details are hidden in the `createAccount()` helper. It's not obvious where the `Balance` value comes from or what parameters matter for this test.

---

## The Solution: Balanced Visibility

```go
func TestAccount_GetBalance(t *testing.T) {
    account := createAccountWithBalance(1000)

    balance := account.GetBalance()

    require.Equal(t, 1000, balance)
}

func createAccountWithBalance(balance int) *Account {
    return &Account{
        Settings:    defaultBankSettings(),
        ID:          "acc-123",
        Balance:     balance,
        Address:     "123 Main St",
        Name:        "John Doe",
        Email:       "john@example.com",
        Phone:       "+1-555-0100",
        CreatedAt:   time.Now(),
        UpdatedAt:   time.Now(),
        Status:      "active",
        AccountType: "checking",
    }
}

func defaultBankSettings() *BankSettings {
    return &BankSettings{
        FDICInsured: true,
        Regulated:   true,
        Country:     "US",
        Timezone:    "America/New_York",
        Currency:    "USD",
    }
}
```

**Why it's better**:
- **Parameter visibility**: The balance (1000) appears in the test itself
- **Clear relationships**: Readers see the input value matches the expected output
- **Easy traceability**: The test shows where important data originates
- **Reduced noise**: Boilerplate setup is hidden but still accessible

---

## Making Data Flow Explicit

### Bad: Hidden Relationships

```go
func TestAccount_Withdraw(t *testing.T) {
    account := createAccount()

    err := account.Withdraw(1500)

    require.EqualError(t, err, "insufficient funds")
}
```

**Problem**: Where does 1500 come from? Why does it cause insufficient funds? The relationship between balance and withdrawal amount is invisible.

### Good: Visible Relationships

```go
func TestAccount_Withdraw(t *testing.T) {
    balance := 1000
    account := createAccountWithBalance(balance)

    err := account.Withdraw(balance + 500)

    require.EqualError(t, err, "insufficient funds")
}
```

**Why it's better**: The test explicitly shows `balance + 500` exceeds the account balance. The relationship between input and expected outcome is clear.

---

## Parameterized Helpers Pattern

### Bad: One Giant Helper

```go
func createAccount() *Account {
    return &Account{
        Balance:     1000,
        Status:      "active",
        Validated:   true,
        CreditLimit: 5000,
        // ... 20 more fields
    }
}
```

**Problem**: Every test gets the same hardcoded values, whether relevant or not.

### Good: Composable Helpers

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

// Composition for complex scenarios
func createAccountWithBalanceAndLimit(balance, limit int) *Account {
    account := createAccountWithBalance(balance)
    account.CreditLimit = limit
    return account
}
```

Usage:
```go
func TestAccount_Withdraw(t *testing.T) {
    t.Run("succeeds with sufficient funds", func(t *testing.T) {
        account := createAccountWithBalance(1000)

        err := account.Withdraw(100)

        require.NoError(t, err)
        require.Equal(t, 900, account.Balance)
    })

    t.Run("fails when account is not validated", func(t *testing.T) {
        account := createUnvalidatedAccount()

        err := account.Withdraw(100)

        require.EqualError(t, err, "account must be validated before withdrawal")
    })
}
```

---

## Builder Pattern for Complex Objects

For objects with many fields, use the builder pattern to expose only relevant parameters.

```go
type AccountBuilder struct {
    account *Account
}

func NewAccountBuilder() *AccountBuilder {
    return &AccountBuilder{
        account: &Account{
            ID:          deterministicID("test-account"),
            Balance:     0,
            Status:      "active",
            Validated:   true,
            CreatedAt:   time.Now(),
            UpdatedAt:   time.Now(),
            AccountType: "checking",
        },
    }
}

func (b *AccountBuilder) WithBalance(balance int) *AccountBuilder {
    b.account.Balance = balance
    return b
}

func (b *AccountBuilder) WithStatus(status string) *AccountBuilder {
    b.account.Status = status
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
        account := NewAccountBuilder().
            WithBalance(balance).
            Build()

        err := account.Withdraw(balance + 50)

        require.EqualError(t, err, "insufficient funds")
    })

    t.Run("fails when unvalidated", func(t *testing.T) {
        account := NewAccountBuilder().
            WithBalance(1000).
            Unvalidated().
            Build()

        err := account.Withdraw(100)

        require.EqualError(t, err, "account must be validated")
    })
}
```

**Benefits**:
- Only relevant parameters appear in each test
- Clear, fluent API shows what matters
- Easy to extend without breaking existing tests

---

## Guidelines for Test Clarity

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

---

## Checklist for Reviewing Test Clarity

When reviewing a test, ask:
- [ ] Can I understand what's being tested without reading helper functions?
- [ ] Are the values that matter to the assertion visible in the test?
- [ ] Is the relationship between inputs and expected outputs clear?
- [ ] Does the test include any irrelevant details that obscure its purpose?
- [ ] Would hiding more details make the test harder to understand?
- [ ] Would exposing more details make the test easier to understand?

---

## Summary

| Approach | Problem | Solution |
|----------|---------|----------|
| **Too much noise** | Hard to identify relevant details | Use helpers for boilerplate |
| **Too much abstraction** | Critical details hidden | Pass relevant values as parameters |
| **Magic values** | Unclear relationships | Name values, show calculations |
| **One-size-fits-all helpers** | Forces irrelevant details | Create specific helpers or use builders |

**Goal: Make tests self-documenting by exposing only relevant details while hiding implementation noise.**
