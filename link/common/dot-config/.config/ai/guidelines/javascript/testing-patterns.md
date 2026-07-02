# JavaScript Testing Patterns

## Core Principle: Test Behavior Through Public API Only

**Never test implementation details. Test observable behavior through exported functions and modules.**

Tests should verify **what** the system does (observable behaviors), not **how** it does it (implementation details).

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

### The Substitution Test: Is the Code Under Test Even Exercised?

A change detector restates a value the code produces. Its extreme form is the **vacuous test**: one whose assertions pass no matter what the code under test does, because they never exercise its logic.

> Mentally replace the function under test with a trivial stub — one that returns a hardcoded constant, returns its input unchanged, or forwards a collaborator's value verbatim. If every assertion still passes, the test is not testing that function.

Two shapes fail this test:

- **Constant pin** — the expected value is a literal copied from the production source, and the code performs no transformation to produce it. Any stub returning that constant passes. (This is the weak-independence change detector, seen from the code's side.)
- **Passthrough** — the function returns a collaborator's output verbatim and the assertion pins that output, so the assertion really tests the collaborator, not the function.

```js
// Production: getDisplayName just forwards the formatter's output
function getDisplayName(user, formatter) {
  return formatter.format(user);
}

// ❌ Vacuous — the assertion pins the collaborator's output, not getDisplayName's logic
it('returns the formatted name', () => {
  const formatter = { format: () => 'Ada L.' };
  expect(getDisplayName({ first: 'Ada' }, formatter)).toBe('Ada L.');
  // Same expected value without calling the code under test — it tests the formatter:
  // expect(formatter.format({ first: 'Ada' })).toBe('Ada L.');
});
```

**The tell:** if you can rewrite the assertion to produce the same expected value *without calling the code under test* — by calling the collaborator directly or just writing the constant — the code under test is not on trial.

**What legitimately survives substitution** (and is therefore NOT vacuous):
- A real transform — stub it and the assertion fails, because the code computes the value.
- A **golden / contract test** over frozen external input — parsing/decoding frozen input stubbed to a constant no longer reproduces the expected value, so it fails.

A test that survives substitution is exercising the code; a test that survives substitution *and* a behavior-preserving refactor is exercising it at the right altitude.

---

## What to Test

### Test-worthy
- Business logic and domain calculations
- Edge cases (empty arrays, null/undefined, boundary values)
- Error paths (rejected promises, validation failures)
- State transitions (before/after a mutation)
- Contract behavior of exported functions

### NOT test-worthy (skip these)
- Trivial getters/setters that return a field value
- Constructor calls that can't fail (factory returns default state)
- Language runtime behavior (Array.map, Object.assign)
- Internal helpers called only by other tested functions
- Private module-scoped functions tested indirectly through the public API

---

## Unit of Behavior

A **unit of behavior** is any piece of code that can produce an independently observable outcome — a return value, a state change, a side effect, or a thrown error — regardless of how many functions or modules it spans.

### Identifying the Unit

The unit is **one behavior**, not one function:

```js
// One unit: calculating discount
function calculateDiscount(price, tier) { ... }

// Another unit: applying it
function applyDiscount(order, discount) { ... }
```

### What is NOT a Unit of Behavior
- A helper function that just formats a string, when the only caller already tests the formatted output
- Internal state that no external caller observes
- A side effect that is always paired with another operation (save + log — test save, the log is incidental)

---

## Test Structure

Use `describe`/`it` blocks. Name tests as complete sentences about the observed behavior.

```js
describe('calculateDiscount', () => {
  it('returns 10% for premium tier', () => {
    expect(calculateDiscount(100, 'premium')).toBe(10);
  });

  it('returns 0 for basic tier', () => {
    expect(calculateDiscount(100, 'basic')).toBe(0);
  });

  it('throws for unknown tier', () => {
    expect(() => calculateDiscount(100, 'unknown')).toThrow('Unknown tier');
  });
});
```

### One Behavior Per Test
Each `it` block tests exactly one behavior. If a scenario has multiple assertions about the same outcome (e.g., a returned object has the right shape and values), group them in one block. If they test different outcomes, split.

---

## Assertion Patterns

### Strict Equality for Business Values
```js
// ✅ Good — exact values
expect(calculateTotal([5, 10])).toBe(15);

// ❌ Avoid — weak assertion for deterministic values
expect(calculateTotal([5, 10])).toBeGreaterThan(0);
```

### Object Shape
```js
// ✅ Good — checks the exact expected shape
expect(result).toEqual({ id: 'abc', amount: 50 });

// ❌ Avoid — partial match misses extra fields
expect(result.amount).toBe(50);
```

### Error Handling
```js
// ✅ Good — synchronous error
expect(() => validate(null)).toThrow('Input required');

// ✅ Good — async rejection
await expect(fetchData(null)).rejects.toThrow('Invalid ID');
```

### Side Effects
```js
// ✅ Good — check the side effect was produced
const events = [];
bus.on('payment:received', (e) => events.push(e));

await processPayment({ amount: 50 });

expect(events).toHaveLength(1);
expect(events[0].amount).toBe(50);
```

---

## DOM Testing

### Test Behavior, Not DOM Structure
```js
// ✅ Good — test the outcome
const el = renderBlock({ id: '1', label: 'Start' });
expect(el.getAttribute('data-node-id')).toBe('1');

// ❌ Avoid — test structural internals
expect(el.querySelector('rect').getAttribute('fill')).toBe('#fff');
```

### Event Delegation
Test that clicking a delegated element triggers the right handler:

```js
// ✅ Good — test the handler, not the event binding
const result = [];
const handler = (id) => result.push(id);

svgEl.addEventListener('click', (evt) => {
  const block = evt.target.closest('.diagram-node');
  if (block) handler(block.dataset.nodeId);
});

// Dispatch a click on a child element
const rect = svgEl.querySelector('rect');
rect.dispatchEvent(new MouseEvent('click', { bubbles: true }));

expect(result).toEqual(['node-1']);
```

---

## Async Testing

### Promises
```js
it('resolves with data', async () => {
  const data = await fetchData('/api/items');
  expect(data).toHaveLength(3);
});

it('rejects on network error', async () => {
  mockFetch.mockRejectedValue(new Error('NetworkError'));
  await expect(fetchData('/api/items')).rejects.toThrow('NetworkError');
});
```

### Callbacks
Wrap callback-based code in a promise for testing:

```js
it('calls the callback with result', () => {
  return new Promise((resolve) => {
    processAsync('input', (err, result) => {
      expect(err).toBeNull();
      expect(result).toBe('processed');
      resolve();
    });
  });
});
```

---

## Test Double Patterns

### Fakes (Preferred)
Use in-memory implementations of interfaces for fast, reliable tests:

```js
function createInMemoryStore() {
  const data = new Map();
  return {
    save(id, item) { data.set(id, item); },
    byId(id) { return data.get(id) ?? null; },
    all() { return [...data.values()]; },
    clear() { data.clear(); },
  };
}

it('saves and retrieves by ID', () => {
  const store = createInMemoryStore();
  store.save('1', { name: 'test' });
  expect(store.byId('1')).toEqual({ name: 'test' });
});
```

### Recording Doubles
Capture calls for assertion:

```js
function createRecordingMailer() {
  const sent = [];
  return { send: (to, msg) => sent.push({ to, msg }), sent, };
}

it('sends confirmation email', () => {
  const mailer = createRecordingMailer();
  const service = createNotificationService(mailer);
  service.sendConfirmation('user@example.com');
  expect(mailer.sent).toHaveLength(1);
  expect(mailer.sent[0].to).toBe('user@example.com');
});
```

### Mock Boundaries
Only mock at module boundaries (network, filesystem, timers). Do NOT mock internal modules of the system under test.

```js
// ✅ Good — mock at the boundary
vi.mock('../api/client');

// ❌ Avoid — mocking internal modules
vi.mock('../utils/helpers');
```

---

## Anti-Patterns

| # | Anti-pattern | Looks like | Instead |
|---|---|---|---|
| 1 | Testing implementation details | `expect(store.getState().items.length).toBe(3)` | Test the public API outcome |
| 2 | Change detector (weak independence) | Expected value copied from production code | Use domain knowledge |
| 3 | Tautology | `const x = fn(); expect(fn()).toBe(x)` | Fixed expected value |
| 4 | No behavioral assertion | `expect(err).toBeNull()` without other assertions | Assert on the business outcome |
| 5 | Multiple behaviors in one test | One `it` block testing 5 scenarios | One scenario per `it` |
| 6 | Mocking internals | `vi.mock('../internal/helper')` | Test through the public module boundary |
| 7 | Testing framework behavior | Testing that `Array.map` works | Trust the runtime |
| 8 | DOM structure assertions | `expect(el.innerHTML).toBe('<div>...</div>')` | Assert on visible attributes or outcomes |
| 9 | Async without await | `expect(fetchData()).resolves.toBe(...)` (missing `await`) | `await expect(fetchData()).resolves.toBe(...)` |
| 10 | Test pollution | Shared mutable state between tests | Fresh state in `beforeEach` or per-test factory |

---

## Detection Checklist

When reviewing a test, check for these red flags:

- [ ] Expected value is computed from the code under test → tautology
- [ ] Only assertion is `not.toBeNull` or `not.toThrow` → missing behavioral assertion
- [ ] Test accesses internal module state not exported → implementation detail
- [ ] Test mocks a module internal to the system → mock boundary violation
- [ ] Test calls multiple functions and doesn't distinguish which one is under test → unclear scope
- [ ] Expected values are copied from production code without domain justification → weak independence
- [ ] Assertion still passes when the code under test is replaced by a constant or passthrough stub → vacuous test (substitution test)
- [ ] Test checks `innerHTML` or DOM structure for elements that don't carry behavioral content → structural coupling
- [ ] Test doesn't `await` an async operation → flaky test

---

## Quick Reference

| Practice | Rule |
|---|---|
| Test runner | vitest preferred; jest acceptable |
| Test structure | `describe`/`it` blocks, one behavior per `it` |
| Module scope | Test through exported functions only |
| Naming | `describe('functionName', ...)`, `it('does what when condition', ...)` |
| Expected values | From domain knowledge, not production code |
| Assertion strictness | `toEqual` for objects, `toBe` for primitives |
| Async | `async/await` with `.resolves`/`.rejects` |
| Test doubles | Fakes > recording doubles > mocks at boundaries |
| DOM | Assert on attributes/outcomes, not structure |
| State isolation | Fresh state per test, no shared mutable fixtures |
| Coverage target | 80%+ line coverage, 100% for critical business logic |
