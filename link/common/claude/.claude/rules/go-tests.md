---
paths:
  - "**/*_test.go"
---

# Go Testing Principles

When writing or modifying Go test files, follow these universal principles:

- **Public API only** — Test through exported (capitalized) functions/methods. Never access unexported fields or methods.
- **Assert on outcomes, not implementation** — Verify return values and side effects, not internal calls or invocation counts.
- **No mocking types you don't own** — Use `httptest`, fakes, or thin wrappers instead of mocking `database/sql`, `http.Client`, AWS/GCP SDKs, or third-party library interfaces.
- **No trivial tests** — Skip constructors returning non-nil, zero-value behavior, getter/setter passthrough. If construction fails, other tests will catch it.
- **No `require.NoError` as the sole assertion** — Every test must assert something meaningful beyond the absence of an error.
- **Test independence** — No shared mutable state, no order dependence. Each test must run in isolation and in any order.
- **Relevant values visible in the test** — Values that affect assertions belong in the test body, not hidden inside helpers. Helpers should accept parameters for relevant values.
- **One behavior per test** — Each test has a single reason to fail, with a name describing that scenario (e.g., "fails with insufficient funds"), not implementation (e.g., "CallsValidator"). Integration tests may verify multiple behaviors in one flow.
