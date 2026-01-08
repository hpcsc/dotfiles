# Test Helper Patterns

## Recording Test Doubles

Use test doubles that record what happened for later assertions.

### Pattern: Recording Sender

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

Usage:
```go
func TestNotifyCustomer(t *testing.T) {
    recorder := &recordingEmailSender{}
    service := &NotificationService{sender: recorder}

    service.NotifyCustomer("cust-123", "Payment received")

    lastCall := recorder.LastCall()
    require.Equal(t, "cust-123", lastCall.recipient)
    require.Equal(t, "Payment received", lastCall.message)
}
```

---

## Failing Test Doubles

Create test doubles that simulate failure scenarios.

### Pattern: Faulty Implementation

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

Usage:
```go
func TestNotifyCustomer_HandlesErrors(t *testing.T) {
    sender := NewFailingEmailSender(errors.New("SMTP unavailable"))
    service := &NotificationService{sender: sender}

    err := service.NotifyCustomer("cust-123", "Hello")

    require.EqualError(t, err, "SMTP unavailable")
}
```

---

## In-Memory Implementations

Create simple in-memory implementations for testing without external dependencies.

### Pattern: In-Memory Repository

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

Usage:
```go
func TestUserService_CreateUser(t *testing.T) {
    repo := NewInMemoryUserRepository()
    service := NewUserService(repo)

    user := &User{Name: "Alice"}
    err := service.CreateUser(user)

    require.NoError(t, err)
    require.NotEmpty(t, user.ID)

    found, err := repo.FindByID(user.ID)
    require.NoError(t, err)
    require.Equal(t, "Alice", found.Name)
}
```

---

## Var Blocks for Test Setup

Organize test dependencies with var blocks for clarity.

### Pattern: Var Block Setup

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

---

## Deterministic Test Data

Use deterministic ID generation for predictable tests.

### Pattern: Deterministic IDs

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

---

## Table-Driven Tests for Multiple Scenarios

Use table-driven tests when testing multiple similar scenarios.

### Pattern: Table Test

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

## Summary

| Pattern | Use When |
|---------|----------|
| **Recording doubles** | Need to verify data passed to dependencies |
| **Failing doubles** | Testing error handling |
| **In-memory implementations** | Avoiding external dependencies |
| **Var blocks** | Multiple related tests share setup |
| **Deterministic IDs** | Tests need reproducible data |
| **Table tests** | Testing multiple similar scenarios |
