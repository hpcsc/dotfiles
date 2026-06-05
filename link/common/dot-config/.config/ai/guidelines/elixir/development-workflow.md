# Elixir Development Workflow

## When Creating New Components

Follow this workflow when adding new functionality:

### 1. Identify the Business Concept
Choose a noun that represents the application concept. Think domain language, not technical implementation.

Examples:
- ✅ `Provisioning`, `Billing`, `EventStream`, `Mailer`
- ❌ `MailerManager`, `HandlerHelper`, `Utils`

### 2. Define the Behaviour in the Parent Module
The capability is the parent module; it holds the contract and (optionally) the public API that dispatches to the configured implementation.

```elixir
defmodule MyApp.Mailer do
  @callback deliver(Email.t()) :: {:ok, map()} | {:error, term()}

  def deliver(email), do: impl().deliver(email)

  defp impl, do: Application.get_env(:my_app, :mailer, MyApp.Mailer.SMTP)
end
```

### 3. Create Implementation Submodules
Separate implementations from the contract, one submodule per implementation, named for what it is or how it works.

```
lib/my_app/
├── mailer.ex          # Behaviour + public API
└── mailer/
    ├── smtp.ex        # Real implementation
    └── fake.ex        # Test double
```

### 4. Declare Compliance
`@behaviour` plus `@impl true` on every callback — the compiler verifies the contract.

```elixir
defmodule MyApp.Mailer.SMTP do
  @behaviour MyApp.Mailer

  @impl true
  def deliver(email), do: ...
end
```

### 5. Create Test Doubles in the Implementation Subpackage
Test doubles and real implementations co-located, both implementing the same behaviour.

```elixir
# In lib/my_app/mailer/fake.ex (or test/support/ if test-only)
defmodule MyApp.Mailer.Fake do
  @behaviour MyApp.Mailer

  @impl true
  def deliver(email) do
    send(self(), {:delivered, email})
    {:ok, %{id: "fake"}}
  end
end
```

For contract-verified mocks, define the Mox mock against the same behaviour:

```elixir
# In test/test_helper.exs
Mox.defmock(MyApp.Mailer.Mock, for: MyApp.Mailer)
```

### 6. Inject the Implementation
Pass the module as an option for per-call injection, or configure it per environment:

```elixir
# config/test.exs
config :my_app, :mailer, MyApp.Mailer.Mock
```

## When Organizing Code

### 1. Use Feature-Based Organization
Group related functionality by business domain (context), not by technical layer.

```
lib/my_app/
├── provisioning/
│   ├── request.ex
│   ├── validator.ex
│   └── handler.ex
├── billing/
│   ├── invoice.ex
│   └── payment.ex
└── event_stream.ex
    event_stream/
```

### 2. Apply Natural Language Naming
Make code self-documenting through thoughtful naming.

### 3. Write Comprehensive Tests
Use the established testing patterns:
- Test observable behaviors through public functions
- Use `describe` blocks per operation, sentence-style test names
- `async: true` unless the test touches shared global state
- Co-locate test doubles with implementations
- Include both happy path and error scenarios

## Quality Gates

Run before considering any change done:

```bash
mix format                          # canonical formatting
mix compile --warnings-as-errors    # warnings are defects
mix test                            # full suite green
mix credo --strict                  # lint (when the project uses Credo)
mix dialyzer                        # type checks (when the project uses Dialyzer)
```

## Quick Checklist

When creating new components, verify:
- [ ] Module name is a domain noun (not `Manager`, `Helper`, `Utils`)
- [ ] Behaviour lives in the parent module; implementations in submodules with descriptive names
- [ ] Every callback implementation marked `@impl true`
- [ ] Implementation selected via config or injected argument, not hardcoded
- [ ] Test doubles co-located with real implementations (or Mox mock defined against the behaviour)
- [ ] Public functions documented with `@doc`; primary struct typed as `t()`
- [ ] `mix format` and `mix compile --warnings-as-errors` clean
- [ ] Comprehensive tests covering behavior

## Example Complete Structure

```
lib/my_app/
├── provisioning.ex             # Context: public API for the domain
├── provisioning/
│   ├── request.ex              # Domain struct
│   ├── validator.ex            # MyApp.Provisioning.Validator behaviour
│   └── validator/
│       ├── policy.ex           # Real validator implementation
│       └── fake.ex             # Fake validator for testing
test/my_app/
└── provisioning_test.exs       # Tests through the context's public API
```
