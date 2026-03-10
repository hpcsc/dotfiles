# Testing Principles (Language-Agnostic)

## Core Principle: Test Behavior Through Public API Only

**Never test implementation details. Test observable behavior through public functions and methods.**

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

```
// The test knows $10.50 = 1050 cents — a mathematical fact independent of how convertToCents works.
test "convert USD to cents":
    assert convertToCents(10.50, "USD") == 1050
```

### Weak Independence (Change Detectors)

The expected value was copied from production code. The test detects changes but cannot tell you whether the new value is correct.

```
// Where does 2 come from? From looking at the production code.
test "default decimal places":
    assert defaultDecimalPlaces("USD") == 2
```

A particularly bad variant duplicates the production formula:

```
// BAD: Same formula as production — fails on change but provides no guidance on correctness.
test "discount":
    price = 100.0
    discount = 0.2
    expected = price - (price * discount)
    assert applyDiscount(price, discount) == expected
```

### No Independence (Tautologies)

The expected value is derived from the code under test at runtime. The test **cannot fail**.

```
// BAD: Both sides evaluate the same code path — passes no matter what applyDiscount does.
test "discount":
    expected = applyDiscount(100.0, 0.2)
    assert applyDiscount(100.0, 0.2) == expected
```

Other tautology forms:
- Asserting a mock returns what you told it to return
- Using a shared helper that computes both expected and actual values from the same source

### Prefer Higher-Level Behavioral Tests Over Change Detectors

When you notice a change-detector test, check whether a behavioral test already covers it. If so, the change detector is redundant. If not, write the behavioral test first.

```
// Change detector: weak independence
test "default decimal places":
    assert defaultDecimalPlaces("USD") == 2

// Behavioral: strong independence — failure is self-evidently wrong
test "format USD amount":
    assert formatAmount(10.5, "USD") == "$10.50"
```

If someone changes `defaultDecimalPlaces("USD")` to `3`, both fail. But the formatting test fails with `"$10.500" != "$10.50"` — self-evidently wrong. The change detector only says `3 != 2`.

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

❌ **Low Fidelity:**
```
// Only checks function was called, not what it did
assert callCount == 1
```

✅ **High Fidelity:**
```
// Verifies actual behavior and values
assert error == null
assert account.balance == expectedBalance
assert transaction.status == "COMPLETED"
```

### 2. Resilience: Tests Shouldn't Break from Harmless Changes
**Resilient tests only fail when breaking changes are made to the code under test.**

Achieve resilience by:
- Testing public APIs rather than internals
- Preferring fakes and in-memory implementations over mocks
- Avoiding verification of unnecessary dependency interactions
- Testing behavior, not implementation

❌ **Brittle (Low Resilience):**
```
// Breaks if we inline validation or refactor how validation happens
assert mockValidator.wasCalled == true
```

✅ **Resilient (High Resilience):**
```
// Survives refactoring as long as behavior is preserved
assert error.message == "amount must be positive"
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
```
// Which validation failed?
test "validation":
    assert validateAll(data) == success
```

✅ **Precise:**
```
test "validation":
    test "rejects negative amounts":
        error = validateAmount(-100)
        assert error.message == "amount must be positive"

    test "rejects invalid CVV":
        error = validateCVV("12")
        assert error.message == "CVV must be 3 or 4 digits"
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
❌ **Framework behavior**: language features

---

## What is a Unit of Behavior?

A **unit of behavior** is an observable outcome that a caller depends on. The "caller" might be a product user, another service, another package, or another developer on your team.

The key question: **"If this behavior changed, would someone outside this code need to know?"**

### Three Tiers of Behavioral Contracts

Not every behavior traces back to a user story. Infrastructure code has behavioral contracts too — the behavior just serves developers instead of end users.

| Tier | Who cares | Example |
|------|-----------|---------|
| **Domain** | Product owner, end user | "Paused accounts cannot receive payments" |
| **Contract** | Other services, other packages | "Events are published in order" |
| **Structural** | Other developers on your team | "Returns NotFound error when key is missing" |

All three tiers are valid behaviors worth testing. The distinction between behavior and implementation isn't about who the caller is — it's about whether any caller depends on it.

### How to Tell Behavior from Implementation

Ask: **"Does any caller of this code depend on this specific detail?"**

| Assertion | Caller depends on it? | Verdict |
|-----------|-----------------------|---------|
| `get` returns the value after `set` | Yes — that's the contract | **Behavior** |
| Items are stored in a hash map | No — could be a list, tree, anything | **Implementation** |
| Concurrent `get`/`set` don't corrupt data | Yes — callers run this concurrently | **Behavior** |
| A read-write lock is used internally | No — callers care about thread-safety, not the mechanism | **Implementation** |

### What is NOT a Unit of Behavior

- Object existence (asserting non-null after construction)
- Constructor success (construction returning non-null)
- A test that only checks for absence of error with no other assertion
- Internal mechanisms (which data structure, which sync primitive, which call order)

### What IS a Unit of Behavior

An observable outcome that a caller depends on:
- **"rejects invalid input"** — domain: business validation
- **"saves data to database"** — domain: side effect
- **"returns sorted results"** — domain: output correctness
- **"publishes events in version order"** — contract: downstream consumers depend on ordering
- **"returns NotFound error when key is missing"** — structural: callers handle this case
- **"notifies subscribers on error"** — contract: external communication

---

## HTTP Handlers: The Component Is the Endpoint

An HTTP handler — whether it returns JSON, HTML, or streamed chunks — may be composed of multiple internal pieces (controllers, templates, view models, serializers, middleware). **These are implementation details. The unit of behavior is the HTTP response.**

The public API is: HTTP request in → HTTP response out. Test through a test server/recorder and the handler function, asserting on what the caller (browser, API client, frontend) observes.

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

### When Response Structure IS Behavior

Sometimes structure matters because a downstream caller depends on it (e.g., HTMX swap targets, streaming chunk target fields, accessibility landmarks, API field names). In those cases the structure is a **contract**, not an implementation detail, and is worth testing.

---

## Test Structure

```
// Arrange-Act-Assert pattern
test "feature description":
    // Arrange - set up test data
    subject = createSubject()

    // Act - execute the behavior
    result = subject.method(input)

    // Assert - verify observable outcomes
    assert result == expected
```

### Organize by Scenarios

```
test "feature name":
    test "describes specific scenario":
        // Arrange
        // Act
        // Assert

    test "describes error scenario":
        // Arrange
        // Act
        // Assert
```

---

## Testing Observable Behaviors: Examples

### Example 1: Test Validation Behavior, Not Internal Calls

❌ **Bad - Testing Implementation Details:**
```
// BAD: Testing that internal validator was called
test "process calls validator":
    mockValidator = createMockValidator()
    processor = Processor(validator: mockValidator)

    processor.process(100, "123")

    // Testing HOW, not WHAT
    assert mockValidator.wasCalled == true
```

**Problem**: Test breaks if we refactor to inline validation or change how validation happens, even though behavior stays the same.

✅ **Good - Testing Observable Behaviors:**
```
// GOOD: Testing through public API
test "process":
    processor = createProcessor()

    test "rejects negative amount":
        error = processor.process(-100, "123")
        assert error.message == "amount must be positive"

    test "rejects invalid CVV":
        error = processor.process(100, "12")
        assert error.message == "CVV must be 3 or 4 digits"

    test "succeeds with valid inputs":
        error = processor.process(100, "123")
        assert error == null
```

**Why it's better**: Tests verify actual business rules. Refactoring internal validation doesn't break tests as long as behavior is preserved.

### Example 2: Verify Side Effects, Not Just Invocations

❌ **Bad - Only Checking Call Happened:**
```
// BAD: Only verifying invocation count
test "notify customer calls sender":
    spy = createSpyEmailSender()
    service = NotificationService(sender: spy)

    service.notifyCustomer("cust-123", "Hello")

    // This proves nothing about correctness
    assert spy.callCount == 1
```

**Problem**: Test passes even if we send wrong recipient, wrong message, or ignore errors.

✅ **Good - Verify Actual Side Effects:**
```
// GOOD: Testing observable outcomes
test "notify customer":
    test "sends email with correct recipient and message":
        recorder = createRecordingEmailSender()
        service = NotificationService(sender: recorder)

        error = service.notifyCustomer("cust-123", "Payment received")

        assert error == null
        assert recorder.lastRecipient == "cust-123"
        assert recorder.lastMessage == "Payment received"

    test "propagates sender errors":
        failingSender = createFailingEmailSender("SMTP unavailable")
        service = NotificationService(sender: failingSender)

        error = service.notifyCustomer("cust-123", "Hello")

        assert error.message == "SMTP unavailable"
```

### Example 3: Test Business Behavior, Not Trivial Getters/Setters

❌ **Bad - Testing Simple Accessors:**
```
// BAD: Testing trivial getters/setters
test "account set validated":
    account = createAccount()
    account.setValidated(true)
    // This test adds no value
    assert account.isValidated() == true
```

**Problem**: Tests add no value. They test language features (field assignment, zero values) not business logic.

✅ **Good - Test Business Behavior:**
```
// GOOD: Testing business rules
test "account withdraw":
    test "rejects withdrawal from unvalidated account":
        account = createAccount(balance: 1000, validated: false)

        error = account.withdraw(100)

        assert error.message == "account must be validated before withdrawal"

    test "allows withdrawal from validated account with sufficient funds":
        account = createAccount(balance: 1000, validated: true)

        error = account.withdraw(100)

        assert error == null
        assert account.balance == 900

    test "rejects withdrawal exceeding balance":
        account = createAccount(balance: 100, validated: true)

        error = account.withdraw(500)

        assert error.message == "insufficient funds"
```

**Why it's better**: Tests verify business rules. The `validated` field matters only because it affects withdrawal behavior.

---

## Principle: Never Expose Internals Just for Testing

**Don't make private fields or methods public just to achieve test coverage. Test as a regular client would use the API.**

### The Problem: Test-Induced Design Damage

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

```
// Customer with internal status
class Customer:
    private name: string
    private status: Status  // Internal state used to calculate discounts

    function promote():
        this.status = PREMIUM

    function getDiscount():
        if this.status == PREMIUM:
            return 0.15  // 15% for premium
        return 0.0  // 0% for regular
```

#### ❌ WRONG: Expose Private State for Testing

```
// BAD: Exposing internal state
class Customer:
    private name: string
    public status: Status  // Made public just for testing

// Or even worse - adding a getter just for tests
class Customer:
    function getStatus():  // Getter added solely for test assertions
        return this.status

// BAD: Testing internal state
test "customer promote":
    customer = createCustomer("Alice")

    customer.promote()

    // Testing implementation, not behavior
    assert customer.status == PREMIUM
    // Or: assert customer.getStatus() == PREMIUM
```

**Why this is wrong:**
- Tests internal implementation, not observable behavior
- Breaks encapsulation - clients can now access/modify Status
- Test breaks if we change how premium status is represented internally
- Doesn't verify the actual business outcome (discount calculation)

#### ✅ CORRECT: Test Observable Behavior

```
// GOOD: Testing through observable behavior
test "customer promote":
    test "regular customer gets no discount":
        customer = createCustomer("Alice")

        discount = customer.getDiscount()

        assert discount == 0.0

    test "promoted customer gets premium discount":
        customer = createCustomer("Alice")

        customer.promote()
        discount = customer.getDiscount()

        assert discount == 0.15
```

**Why this is better:**
- Tests the actual business outcome (discount amount)
- Doesn't depend on internal status representation
- Test survives refactoring (e.g., changing Status type, adding tiers, etc.)
- Tests as a regular client would use the API

### Red Flags: You're About to Make a Mistake If...

- ❌ You're adding a getter method just so tests can inspect a private field
- ❌ You're making a private field/method public just for test access
- ❌ You're using reflection in tests to access private members
- ❌ You're thinking "I need to verify this internal state changed correctly"

### Green Flags: You're Doing It Right If...

- ✅ All tests call only public functions/methods
- ✅ Tests verify behavior through inputs and observable outputs
- ✅ Complex internal logic is either:
  - Extracted to separate, testable pure functions
  - Tested indirectly through public behavior with comprehensive scenarios
- ✅ Private fields remain private and tests don't inspect them
- ✅ You can refactor internal implementation without changing tests
- ✅ Tests read like specifications: "when X happens, then Y should result"

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
```
test "account withdraw":
    account = createAccount()

    error = account.withdraw(1500)

    assert error.message == "insufficient funds"
```

✅ **Good - Visible Relationships:**
```
test "account withdraw":
    balance = 1000
    account = createAccountWithBalance(balance)

    error = account.withdraw(balance + 500)

    assert error.message == "insufficient funds"
```

**Why it's better**: The test explicitly shows `balance + 500` exceeds the account balance. The relationship is clear.

---

## Assertion Strictness: Match to What You're Testing

**Not all assertions should be strict. Match assertion strictness to the stability and importance of what you're verifying.**

### Use Strict Assertions For:

**Business logic and data values:**
```
✅ assert account.balance == 1000
✅ assert payment.status == "COMPLETED"
✅ assert payment.customerId == customerId
```

**Error codes and types:**
```
✅ assert error.code == INSUFFICIENT_FUNDS
✅ assert error.type == AmountMustBePositive
```

**API contracts:**
```
✅ assert response.statusCode == 400
✅ assert response.errorCode == "INVALID_AMOUNT"
```

### Use Loose Assertions For:

**User-facing display text (may change for UX reasons):**
```
// ✅ Good - Just ensure it exists
assert buttonText != ""

// ✅ Good - Verify key information is present
assert buttonText.contains("Payment")

// ❌ Bad - Breaks when UX updates copy
assert buttonText == "Submit Payment Now"
```

**Error messages meant for end-users:**
```
// ✅ Good - Verify key information is present
assert error != null
assert error.message.contains("insufficient funds")
assert error.message.contains(accountId)

// ❌ Bad - Breaks when we improve error message clarity
assert error.message == "Insufficient funds. Please add money to your account and try again."
```

**Log messages and debug output:**
```
// ✅ Good - Verify key information is logged
assert logOutput.contains(accountId)
assert logOutput.contains("payment processed")
assert logOutput.contains(amount.toString())

// ❌ Bad - Breaks when log format changes
assert logOutput == "Payment 123 processed for account ABC at 2024-01-01"
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

### Rule of Thumb

**If changing the value would be:**
- A bug → Use strict assertions
- An improvement → Use loose assertions or don't assert
- Breaking for API consumers → Use strict assertions
- Harmless for API consumers → Use loose assertions

---

## Common Anti-Patterns to Avoid

### Anti-Pattern 0: Testing Constructor Returns Non-Null

#### Problem
```
// BAD: Only tests object exists
test "create projector":
    p = createProjector(proj, store, sub, logger)
    assert p != null  // Useless — other tests would fail if this returned null
```

#### Why It's Wrong
- Tests object existence, not behavior
- If construction fails, other tests would catch it anyway
- Provides no value in catching bugs

#### Fix
```
// GOOD: Test the actual behavior of the constructed object
test "projector start":
    test "saves checkpoint after processing events":
        projector = createProjector(proj, store, sub, logger)
        projector.start()

        checkpoint = checkpointStore.get("projection")
        assert checkpoint == 10
```

---

### Anti-Pattern 1: Mocking Internal Dependencies

#### Problem
```
// BAD: Testing that internal validator was called
test "process calls validator":
    mockValidator = createMockValidator()
    processor = Processor(validator: mockValidator)

    processor.process(100, "123")

    assert mockValidator.wasCalled == true
```

#### Why It's Wrong
- Breaks when refactoring internal structure
- Doesn't verify actual behavior
- Tests implementation, not requirements

#### Fix
```
// GOOD: Test the actual validation behavior
test "process":
    processor = createProcessor()

    test "rejects negative amount":
        error = processor.process(-100, "123")
        assert error.message == "amount must be positive"
```

---

### Anti-Pattern 2: Testing Only That a Function Was Called

#### Problem
```
// BAD: Only verifying invocation count
test "notify customer calls sender":
    spy = createSpyEmailSender()
    service = NotificationService(sender: spy)

    service.notifyCustomer("cust-123", "Hello")

    assert spy.callCount == 1
```

#### Why It's Wrong
- Doesn't verify correct data was passed
- Doesn't verify errors are handled
- Test passes even with wrong behavior

#### Fix
```
// GOOD: Verify the actual side effects
test "notify customer":
    test "sends email with correct recipient and message":
        recorder = createRecordingEmailSender()
        service = NotificationService(sender: recorder)

        error = service.notifyCustomer("cust-123", "Payment received")

        assert error == null
        assert recorder.lastRecipient == "cust-123"
        assert recorder.lastMessage == "Payment received"
```

---

### Anti-Pattern 3: Testing Trivial Getters and Setters

#### Problem
```
// BAD: Testing simple field access
test "account set validated":
    account = createAccount()
    account.setValidated(true)
    assert account.isValidated() == true

test "account get balance":
    account = createAccount(balance: 100)
    assert account.getBalance() == 100
```

#### Why It's Wrong
- No business logic to test
- Tests language features, not your code
- Adds maintenance burden without value

#### Fix
```
// GOOD: Test business behavior that uses those fields
test "account withdraw":
    test "rejects withdrawal from unvalidated account":
        account = createAccount(balance: 1000, validated: false)

        error = account.withdraw(100)

        assert error.message == "account must be validated before withdrawal"

    test "allows withdrawal with sufficient funds":
        account = createAccount(balance: 1000, validated: true)

        error = account.withdraw(100)

        assert error == null
        assert account.balance == 900
```

---

### Anti-Pattern 4: Loose Assertions

#### Problem
```
// BAD: Using contains for strict requirements
test "generate ID":
    id = generateID()
    assert id.contains("user-")

// BAD: Not checking error messages
test "validate":
    error = validate(-10)
    assert error != null
```

#### Why It's Wrong
- Contains passes for wrong results
- Missing error message validation
- Doesn't catch subtle bugs

#### Fix
```
// GOOD: Use exact assertions
test "generate ID":
    id = generateID()
    assert id.matches(/^user-[a-f0-9]{32}$/)

test "validate":
    error = validate(-10)
    assert error.message == "amount must be positive"
```

---

### Anti-Pattern 5: Testing Private Methods Directly

#### Problem
```
// BAD: Exposing private methods for testing
class Account:
    public function validateAmount(amount):  // Made public for tests
        if amount < 0:
            return error("amount must be positive")
        return null

test "account validate amount":
    account = createAccount()
    error = account.validateAmount(-10)
    assert error != null
```

#### Why It's Wrong
- Pollutes public API
- Creates maintenance burden
- Tests aren't resilient to refactoring

#### Fix
```
// GOOD: Test through public methods that use validation
test "account withdraw":
    test "rejects negative withdrawal amount":
        account = createAccount(balance: 1000, validated: true)

        error = account.withdraw(-100)

        assert error.message == "amount must be positive"
```

---

### Anti-Pattern 6: Over-Mocking

#### Problem
```
// BAD: Mocking everything
test "get user":
    mockDB = createMockDatabase()
    mockCache = createMockCache()
    mockLogger = createMockLogger()
    mockMetrics = createMockMetrics()

    service = createService(mockDB, mockCache, mockLogger, mockMetrics)
    // Complex test setup...
```

#### Why It's Wrong
- Brittle: breaks when adding dependencies
- Complex: hard to understand and maintain
- Doesn't test real integration

#### Fix
```
// GOOD: Use real implementations or minimal test doubles
test "get user":
    db = createInMemoryDB()
    service = createService(db)

    test "returns user when found":
        db.insert(User(id: "123", name: "Alice"))

        user, error = service.getUser("123")

        assert error == null
        assert user.name == "Alice"
```

---

### Anti-Pattern 7: One Giant Test

#### Problem
```
// BAD: Testing multiple scenarios in one test
test "account operations":
    account = createAccount()

    // Test creation
    assert account.isValidated() == false

    // Test validation
    account.setValidated(true)
    assert account.isValidated() == true

    // Test deposit
    account.deposit(100)
    assert account.balance == 100

    // Test withdrawal
    error = account.withdraw(50)
    assert error == null
    assert account.balance == 50
```

#### Why It's Wrong
- Hard to identify which scenario failed
- Tests are coupled and order-dependent
- Can't run scenarios independently

#### Fix
```
// GOOD: Separate independent test cases
test "account withdraw":
    test "succeeds with sufficient funds":
        account = createAccount(balance: 1000, validated: true)

        error = account.withdraw(100)

        assert error == null
        assert account.balance == 900

    test "fails with insufficient funds":
        account = createAccount(balance: 50, validated: true)

        error = account.withdraw(100)

        assert error.message == "insufficient funds"
```

---

### Anti-Pattern 8: Tautology Tests and Change Detectors

#### Problem: Tautology (No Independence)
```
// BAD: Expected value comes from the code under test — cannot fail.
test "discount":
    expected = applyDiscount(100.0, 0.2)
    assert applyDiscount(100.0, 0.2) == expected
```

#### Why It's Wrong
- The test is true by construction — both sides run the same code path
- No matter what `applyDiscount` does (wrong formula, panics, returns zero), the test passes
- Provides zero defect detection while giving false coverage confidence

#### Problem: Change Detector (Weak Independence)
```
// BAD: Expected value copied from production code — detects change but not correctness.
test "default timeout":
    assert defaultTimeout() == 30
```

#### Why It's Limited
- If someone changes `defaultTimeout()` to `60`, the test fails, but the developer has no way to know if `60` is wrong without consulting an external source
- The test becomes a mechanical "copy the new value" chore with no guidance on correctness

#### Fix: Use Domain-Derived Values or Behavioral Tests
```
// GOOD (strong independence): Domain knowledge — $10.50 = 1050 cents is a mathematical fact.
test "convert USD to cents":
    assert convertToCents(10.50, "USD") == 1050

// GOOD (behavioral): Failure is self-evidently wrong — "$10.500" is clearly incorrect.
test "format USD amount":
    assert formatAmount(10.5, "USD") == "$10.50"
```

When a change-detector test is the only coverage, prefer replacing it with a higher-level behavioral test whose failure is self-evidently wrong.

---

### Detection Checklist

When reviewing tests, check for these red flags:

- [ ] Test names include "Calls", "Invokes", "Uses" (testing HOW, not WHAT)
- [ ] Mocking internal dependencies of the subject under test
- [ ] Asserting on call counts without verifying behavior
- [ ] Testing getters/setters without business logic
- [ ] Using contains/substring match where exact match is needed
- [ ] Not asserting on error messages
- [ ] Exposing private methods/fields just for testing
- [ ] Heavy mocking setup (>3 mocks)
- [ ] Tests break when refactoring without behavior changes
- [ ] Expected values copied from production code without domain justification (change detector)
- [ ] Expected values computed from the code under test at runtime (tautology)

---

## Quick Testing Checklist

Before writing a test, verify the three essential qualities:

**Fidelity (catches defects):**
- [ ] Covers critical code paths (especially error paths)
- [ ] Includes comprehensive assertions about expected outcomes
- [ ] Tests edge cases and boundary conditions
- [ ] Asserts on actual values, not just that functions ran
- [ ] Expected values have independent verification (domain knowledge, not copied from production code)

**Resilience (survives harmless changes):**
- [ ] Testing through public API only
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
| **Test public API** | Spying on internal methods | Call public functions, verify results |
| **Verify behavior** | Counting function calls | Assert on outputs, side effects, state changes |
| **Skip trivial tests** | Testing getters/setters | Test business logic that uses those values |
| **Match assertion strictness** | Always strict or always loose | Strict for contracts, loose for presentation |
| **Expose relevant details** | Hide everything in helpers | Show values that affect assertions |
| **Use real implementations** | Mock everything | In-memory implementations when possible |

**Goal: 100% coverage of business behavior through public API, not implementation details.**
