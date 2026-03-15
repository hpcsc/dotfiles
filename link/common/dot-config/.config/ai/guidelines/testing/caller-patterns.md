# Caller Patterns: Who Is the Test Written For?

Every test implicitly has a **caller** — the actor whose expectations define what "correct" means. Identifying the caller determines what to assert on and what to ignore.

The existing testing guidelines cover **how** to write good tests (public API, behavior over implementation, assertion strictness). This guide covers **which behaviors matter** based on who depends on them.

## Section Index

| Section | Line | Use when... |
|---|---|---|
| [How to Identify the Caller](#how-to-identify-the-caller) | ~25 | Deciding what to assert on for a given component |
| [UI](#1-ui-user--page) | ~48 | Testing pages, forms, rendered output |
| [Inbound](#2-inbound-external-system--handler) | ~100 | Testing webhooks, uploads, API requests from external systems |
| [Outbound](#3-outbound-our-system--external-service) | ~152 | Testing email sends, API calls to providers, file delivery |
| [Async Processing](#4-async-processing-trigger--side-effects) | ~210 | Testing message consumers, event reactors, scheduled jobs |
| [Exported API](#5-exported-api-other-code--this-interface) | ~271 | Testing packages used by other code in the system |
| [Quick Reference](#quick-reference) | ~327 | Lookup table for all five patterns |

---

## How to Identify the Caller

Ask two questions:

1. **Where does the input come from?** Outside the system, inside the system, or another package?
2. **Who observes the output?** The end user, an external service, internal infrastructure, or other developers?

The answers map to one of five patterns:

| Input from | Output observed by | Pattern |
|---|---|---|
| End user (browser, app) | End user | **UI** |
| External system (webhook, upload, API call) | Our system (acceptance/rejection) | **Inbound** |
| Our system (business logic) | External service (email provider, payment API) | **Outbound** |
| Infrastructure (queue, event bus, scheduler) | Infrastructure or downstream consumers | **Async Processing** |
| Other code in the system | Other code in the system | **Exported API** |

---

## 1. UI (User -> Page)

**Direction:** User action in -> rendered response out

**The caller is the end user** — a human looking at a screen, reading content, and clicking things. They don't know or care about HTML structure, CSS classes, view models, or which template engine rendered the page.

### What to assert on

| Assert on (behavior) | Why |
|---|---|
| Visible content ("$10.50", "Payment received") | User needs to see correct information |
| User-facing error messages ("Invalid amount") | User needs actionable feedback |
| Status codes and redirects | Determines what the user sees next |
| Key interaction outcomes (form submission result) | User expects their action to work |

### What NOT to assert on

| Don't assert on (implementation) | Why |
|---|---|
| HTML tags (`<div>`, `<span>`, `<iframe>`) | Template refactoring shouldn't break tests |
| CSS classes, data-attributes, inline styles | Presentation, not behavior |
| DOM structure, nesting depth, node count | Structural, not behavioral |
| View model fields, template data structs | Internal to the rendering pipeline |
| Which template engine or layout was used | Swappable without changing behavior |

### Litmus test

> If I swap the template engine, restructure the HTML, or rename a view model field — but the user sees the **same content** — should any test break?
>
> If yes, the test is asserting on implementation.

### Test shape

```
// Arrange
server = createTestServer(handler)

// Act — simulate what the user does
response = server.get("/account/123")

// Assert — what the user sees
assert response.status == 200
assert response.body.contains("$10.50")
assert response.body.contains("John Doe")
```

### Error scenario

```
response = server.post("/payment", invalidData)

assert response.status == 422
assert response.body.contains("Amount must be positive")
```

### When structure IS behavior

Sometimes HTML structure matters because a downstream caller depends on it — HTMX swap targets, accessibility landmarks, streaming chunk ordering. In those cases, the structure is a **contract** and is worth testing:

```
// HTMX swap targets are a contract — frontend depends on these IDs
assert response.swapTargets == ["day-0-30", "day-0-31"]
```

---

## 2. Inbound (External System -> Handler)

**Direction:** Outside -> in

**The caller is the external system** sending data to us — a payment provider webhook, an SMS delivery callback, a client CSV upload, an API request. They care whether we accepted or rejected their input correctly.

### What to assert on

| Assert on (behavior) | Why |
|---|---|
| Acceptance of valid input (events produced, state changed) | External system expects us to process valid data |
| Rejection of invalid input (validation errors, error codes) | External system needs to know what went wrong |
| Correct parsing of the external format | Contract between us and the provider |
| Idempotent handling of duplicate deliveries | External systems may retry |

### What NOT to assert on

| Don't assert on (implementation) | Why |
|---|---|
| Which internal service processed the input | Caller doesn't care about internal routing |
| Order of internal operations | Caller cares about the outcome, not the steps |
| Internal data structures used during processing | Could change without affecting the caller |
| Which validation ran first | Caller cares about the error, not the mechanism |

### Litmus test

> If I refactor how we process the webhook internally — but we still accept valid events and reject invalid ones with the same errors — should any test break?
>
> If yes, the test is asserting on implementation.

### Test shape

```
// Arrange — construct what the external system sends
event = WebhookEvent(type: "PAYMENT_APPROVED", transactionId: "txn-123", amount: 1050)

// Act — feed it to our handler
result = handler.handle(event)

// Assert — did we accept/reject correctly?
assert result.error == null
assert eventStore.lastEvent.type == "PaymentReceived"
assert eventStore.lastEvent.amount == 1050
```

### Error scenario

```
// Malformed input from external system
event = WebhookEvent(type: "UNKNOWN_TYPE", transactionId: "txn-456")

result = handler.handle(event)

assert result.error.contains("unmapped event")
assert eventStore.isEmpty()
```

### Boundary parsing

```
// External system sends raw JSON — verify we parse the contract correctly
rawJSON = '{"event_type":"SMS_STATUS","status":{"recipient":"15005550006","status":"SENT"}}'

parsed = parseProviderEvent(rawJSON)

assert parsed.recipient == "+15005550006"
assert parsed.status == "SENT"
```

---

## 3. Outbound (Our System -> External Service)

**Direction:** In -> outside

**The caller is the downstream recipient** — the customer receiving an email, the payment provider receiving an API call, the SFTP consumer receiving a file. They care about what arrives, not how we built it.

### What to assert on

| Assert on (behavior) | Why |
|---|---|
| Correct recipient (email address, phone number, API endpoint) | Wrong recipient = wrong person gets the data |
| Correct content (subject, body, amounts, names) | Recipient depends on accurate information |
| Correct data shape for the external service's contract | Provider will reject malformed requests |
| Nothing sent when it shouldn't be (suppression rules) | Sending when we shouldn't is a compliance/business failure |
| Error propagation when the external service fails | System needs to handle delivery failures |

### What NOT to assert on

| Don't assert on (implementation) | Why |
|---|---|
| Which template engine rendered the email | Swappable without changing what arrives |
| How the recipient was looked up | Internal query strategy |
| Internal batching or queuing strategy | Recipient cares about receipt, not delivery mechanism |
| Order of field population in the outbound payload | As long as the final payload is correct |

### Litmus test

> If I change how we build the email (swap template engine, refactor data lookups, restructure internal helpers) — but the recipient gets the **same email** — should any test break?
>
> If yes, the test is asserting on implementation.

### Test shape

Use a **recording test double** (in-memory mailer, fake API client) to capture what was sent, then assert on it.

```
// Arrange
mailer = createInMemoryMailer()
service = createEmailService(mailer)

// Act — trigger the outbound action
service.sendPaymentConfirmation(customerId: "cust-123", amount: 1050)

// Assert — what did the recipient receive?
sent = mailer.outbox()
assert sent.length == 1
assert sent[0].to == "customer@example.com"
assert sent[0].subject == "Payment Confirmed"
assert sent[0].body.contains("$10.50")
```

### Suppression scenario

```
// Customer has opted out — nothing should be sent
service.sendPaymentConfirmation(optedOutCustomerId)

assert mailer.outbox().length == 0
```

### External service failure

```
// Provider is down — error should propagate
mailer = createFailingMailer("SMTP unavailable")
service = createEmailService(mailer)

error = service.sendPaymentConfirmation(customerId: "cust-123", amount: 1050)

assert error.contains("SMTP unavailable")
```

---

## 4. Async Processing (Trigger -> Side Effects)

**Direction:** Trigger in -> side effects out

**The caller is the infrastructure** delivering a trigger — a message queue, an event bus, a scheduler, a cron job. The component reacts to something that happened and produces side effects (new events, state changes, outbound calls).

This differs from Inbound in a key way: Inbound is about the **boundary** (did we parse and accept/reject correctly?). Async Processing is about the **business logic** (given this trigger and current state, did we produce the right outcome?).

### What to assert on

| Assert on (behavior) | Why |
|---|---|
| Output events/state produced from input events | Downstream consumers depend on correct events |
| Business rules applied correctly | Domain logic must be right |
| Idempotency (processing same trigger twice = same outcome) | Infrastructure may deliver duplicates |
| Error events or compensation when something fails | System needs to handle failures gracefully |
| Correct handling of event ordering and history | State depends on the full history, not just the latest event |

### What NOT to assert on

| Don't assert on (implementation) | Why |
|---|---|
| Internal data structures during processing | Could be refactored freely |
| Which helper methods were called | Mechanism, not outcome |
| Intermediate state between processing steps | No caller observes this |
| Internal batching or grouping strategy | Consumer cares about the result, not how it was computed |

### Litmus test

> If I refactor the internal processing logic — but the same input events still produce the same output events and state — should any test break?
>
> If yes, the test is asserting on implementation.

### Sub-patterns

Async Processing has three common shapes. The testing approach is the same — assert on outcomes — but the trigger and output differ:

**Reactor:** Event in -> new events out
```
// Arrange — set up event history
eventStream.write([
    CustomerCreated(id: "cust-1", phone: "+61499999999"),
    PhoneOptedOut(customerId: "cust-1", phone: "+61499999999"),
    CustomerCreated(id: "cust-2", phone: "+61499999999"),
])

// Act — trigger the reactor
engine.react(3)

// Assert — correct output event produced
assert eventStream.events[3].type == "PhoneOptedOut"
assert eventStream.events[3].customerId == "cust-2"
```

**Projector:** Event in -> read model state out
```
// Arrange — set up event history
eventStream.write([
    AccountCreated(id: "acct-1", referredAt: "2024-01-01"),
    PaymentReceived(accountId: "acct-1", position: 2),
])

// Act — project the state
projector.load("acct-1")

// Assert — projected state is correct
assert projector.isFirstPayment(2) == true
assert projector.daysOnFile("2024-03-01") == 60
```

**Dispatcher:** Scheduled trigger -> events out
```
// Arrange — set up existing state
eventStream.write([CampaignCreated(id: "camp-1")])
dispatcher = createDispatcher(eventStore, clock)

// Act — scheduler fires
dispatcher.handle(campaignId: "camp-1")

// Assert — correct event emitted
assert eventStream.lastEvent.type == "CampaignExpired"
assert eventStream.lastEvent.campaignId == "camp-1"
```

---

## 5. Exported API (Other Code -> This Interface)

**Direction:** Cross-package/cross-module

**The caller is other code in the system** — another package, another service, another developer on your team. They depend on the interface contract: function signatures, return types, error types, and behavioral guarantees.

### What to assert on

| Assert on (behavior) | Why |
|---|---|
| Return values for given inputs | Other code branches on these values |
| Error types and sentinel errors | Other code handles specific error cases |
| Contract behavior across implementations | Any implementation must satisfy the same contract |
| Domain calculations and business rules | Other code trusts the results |
| Ordering, uniqueness, and other guarantees | Downstream code depends on these properties |

### What NOT to assert on

| Don't assert on (implementation) | Why |
|---|---|
| Which storage backend is used | Contract tests verify behavior, not mechanism |
| Internal caching or optimization strategies | Performance is separate from correctness |
| Private helper functions or internal structure | Could be refactored freely |
| Constructor success (non-null checks) | Other tests would fail if construction broke |

### Litmus test

> If I swap the implementation behind the interface (in-memory to PostgreSQL, one algorithm to another) — but the contract is preserved — should any test break?
>
> If yes, the test is asserting on implementation.

### Test shape: Contract test

The most powerful pattern here is the **contract test** — a single test suite that any implementation must pass:

```
// Parameterized over the implementation
function storeContractTest(t, newStore):

    test "saves and retrieves by ID":
        store = newStore()
        store.save(entity)
        assert store.byId(entity.id) == entity

    test "returns sorted by priority":
        store = newStore()
        store.save(lowPriority)
        store.save(highPriority)
        assert store.all() == [highPriority, lowPriority]

    test "returns empty when not found":
        store = newStore()
        assert store.byId("nonexistent") == empty
```

### Test shape: Error type contract

```
// Other code depends on this specific error
result, error = projector.isFirstPayment(unknownPosition)

assert error is ErrPaymentPositionNotFound
```

### Test shape: Domain logic

```
// Domain knowledge: $10.50 = 1050 cents
assert convertToCents(10.50, "USD") == 1050

// Business rule: paused accounts cannot receive payments
error = pausedAccount.receivePayment(amount)
assert error.message == "account is paused"
```

---

## Quick Reference

| Pattern | Direction | Caller | Assert on | Don't assert on |
|---|---|---|---|---|
| **UI** | User -> Page | End user | Visible content, error messages, redirects | HTML structure, CSS, view models |
| **Inbound** | Outside -> In | External system | Acceptance/rejection, validation errors, parsing | Internal routing, processing order |
| **Outbound** | In -> Outside | Downstream recipient | Content delivered, correct recipient, suppression | Template engine, data lookup strategy |
| **Async Processing** | Trigger -> Side effects | Infrastructure | Output events/state, business rules, idempotency | Internal data structures, intermediate state |
| **Exported API** | Cross-package | Other code | Contract behavior, error types, domain correctness | Storage backend, internal structure |

### Choosing the Right Pattern

When reviewing or writing a test, ask:

1. **Who would file a bug if this behavior broke?**
   - End user seeing wrong content -> **UI**
   - External system getting wrong response -> **Inbound**
   - Customer getting wrong email -> **Outbound**
   - Downstream consumer getting wrong events -> **Async Processing**
   - Another developer's code breaking -> **Exported API**

2. **What should I put in the assertion?**
   - What the **caller observes**, not how the system produced it.
