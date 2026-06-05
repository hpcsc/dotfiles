# Elixir Naming Patterns

## Natural Language Module Pattern

A key architectural pattern is the **Behaviour module → implementation submodule** convention that creates self-documenting, readable code:

```elixir
# Reads as natural English phrases
MyApp.Mailer            # "mailer" — the behaviour (contract)
MyApp.Mailer.SMTP       # "SMTP mailer" — an implementation
MyApp.EventStream       # "event stream" — the behaviour
MyApp.EventStream.ESDB  # "ESDB event stream" — an implementation
```

## Pattern Structure

```
lib/my_app/
├── mailer.ex             # MyApp.Mailer behaviour + public API
├── mailer/
│   ├── smtp.ex           # MyApp.Mailer.SMTP implementation
│   ├── local.ex          # MyApp.Mailer.Local implementation (dev)
│   └── fake.ex           # MyApp.Mailer.Fake implementation for tests
└── event_stream.ex       # MyApp.EventStream behaviour
    event_stream/
    ├── esdb.ex           # MyApp.EventStream.ESDB
    ├── memory.ex         # MyApp.EventStream.Memory
    └── fake.ex           # MyApp.EventStream.Fake for tests
```

## Implementation Guidelines

### 1. Module Naming Rules

```elixir
# ✅ Good — domain concepts as nouns
defmodule MyApp.Billing do ... end
defmodule MyApp.Billing.Invoice do ... end
defmodule MyApp.Provisioning do ... end

# ❌ Avoid — technical or implementation-focused names
defmodule MyApp.BillingManager do ... end
defmodule MyApp.InvoiceHelper do ... end
defmodule MyApp.Utils do ... end
```

**Important:** Implementation modules should describe **what** they are or **how** they work, never generic names like `Impl`, `Default`, or `Base`.

```elixir
# ✅ Good — descriptive implementation names
MyApp.Mailer.SMTP          # Describes the delivery mechanism
MyApp.EventStream.ESDB     # Describes the backing technology
MyApp.EventStream.Memory   # Describes the storage approach

# ❌ Avoid — generic implementation names
MyApp.Mailer.Impl          # Says nothing about the implementation
MyApp.Mailer.Default       # Which default? Why?
MyApp.MailerImplementation # Verbose and uninformative
```

File paths mirror module names: `MyApp.Mailer.SMTP` lives in `lib/my_app/mailer/smtp.ex`.

### 2. Behaviour Naming Rules

The behaviour is the capability; it lives in the parent module so implementations read naturally beneath it:

```elixir
# ✅ Good — capability as the parent module
defmodule MyApp.Mailer do
  @callback deliver(Email.t()) :: {:ok, map()} | {:error, term()}
end

# ❌ Avoid — Behaviour/Contract suffixes
defmodule MyApp.MailerBehaviour do ... end
defmodule MyApp.MailerContract do ... end
```

### 3. Function Naming Rules

```elixir
# Predicates end in ? and return booleans (no is_ prefix outside guards)
def valid?(changeset), do: ...
defguard is_adult(age) when age >= 18   # is_ only for guards

# Tagged-tuple / raising pairs: fetch returns {:ok, _} | :error, fetch! raises
def fetch(id), do: ...
def fetch!(id), do: ...

# get returns the value or a default — reserve it for that contract
def get(id, default \\ nil), do: ...

# No get_ prefix for plain field access — name the thing itself
def balance(account), do: account.balance     # ✅
def get_balance(account), do: ...              # ❌
```

### 4. Struct and Constructor Pattern

```elixir
defmodule MyApp.Billing.Invoice do
  @type t :: %__MODULE__{total: Money.t(), status: atom()}
  defstruct [:total, status: :draft]

  # Infallible constructor returns the struct
  def new(fields), do: struct!(__MODULE__, fields)

  # Fallible constructor returns a tagged tuple
  def from_params(params) do
    with {:ok, total} <- parse_total(params) do
      {:ok, %__MODULE__{total: total}}
    end
  end
end
```

- The primary struct type is `t()`
- `new/0,1` for construction that cannot fail; tagged tuples when it can

### 5. Behaviour Compliance

```elixir
defmodule MyApp.Mailer.SMTP do
  @behaviour MyApp.Mailer

  @impl true
  def deliver(email), do: ...
end
```

`@behaviour` + `@impl true` is the compliance check — the compiler warns on missing or mistyped callbacks. Every callback implementation carries `@impl true`.

## Summary

Following these naming patterns creates:
- **Self-documenting code**: `MyApp.Mailer.SMTP`, `MyApp.EventStream.Memory` read as natural English
- **Clear module boundaries**: each context has a focused responsibility
- **Discoverable contracts**: behaviours are easy to find — they are the parent module
- **Consistent structure**: predictable organization across the codebase

**Key Takeaways:**
- Module names are domain nouns; behaviours are capabilities living in the parent module
- Implementation modules describe what they are or how they work (never `Impl` or `Default`)
- Predicates end in `?`, raising variants end in `!` and pair with a tagged-tuple variant
- Always mark callback implementations with `@behaviour` + `@impl true`
