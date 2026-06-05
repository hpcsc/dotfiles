# Elixir Architecture Principles

## Core Principles

### 1. Natural Language Readability
- Module names combined with function names create English phrases (`Billing.create_invoice`, `Mailer.deliver`)
- Code reads like documentation
- Domain terminology drives naming

### 2. Functional Core, Imperative Shell
- Domain logic lives in pure functions over plain data (structs) — no processes, no I/O
- Side effects (Repo calls, HTTP, message publishing) happen at the edges, in thin orchestrating modules
- Pure core functions are trivially testable without doubles; only the shell needs them

### 3. Dependency Inversion via Behaviours
- High-level modules depend on behaviours (contracts), not concrete modules
- Behaviours are defined by consuming layers for external dependencies
- Implementations declare `@behaviour` and are selected at the composition root

### 4. Single Responsibility Principle (SRP)
- Each context owns one well-defined domain responsibility
- Behaviours are small and focused
- Clear separation between concerns — a context exposes intent-revealing functions, not its schemas

### 5. Role Behaviour Pattern
- Define behaviours based on what consumers need, not what implementers provide
- A behaviour represents the role a collaborator plays in a specific interaction
- Expose only the callbacks required for that interaction

**Two Approaches:**
- **Provider-Defined**: module defines a behaviour for pluggable implementations (e.g., `MyApp.EventStream`, `MyApp.Mailer`)
- **Consumer-Defined**: consumer defines a behaviour for only what it needs (e.g., wrapping the Stripe SDK, testing seams)

**Rule of Thumb:**
- Building reusable infrastructure → provider-defined behaviour
- Consuming external dependencies → consumer-defined (role) behaviour
- In doubt → start with consumer-defined (easier to refactor later)

### 6. Dependency Injection
- Pass the implementing module as an argument or option (`mailer: MyApp.Mailer.Fake`), or
- Resolve it from config at the composition root (`Application.compile_env(:my_app, :mailer, MyApp.Mailer.SMTP)`)
- Never hardcode a concrete implementation deep inside domain logic
- Avoid mutating `Application` env in tests — inject per call instead

### 7. Processes Are Runtime Concerns, Not Code Organization
- Reach for a process (GenServer, Agent) only for runtime properties: shared state, serialization, fault isolation, backpressure
- Never wrap pure logic in a GenServer just to "structure" code — modules and functions are the unit of organization
- A process added without a runtime justification is a bottleneck and a test burden

### 8. Let It Crash — for Unexpected Errors Only
- Expected, recoverable failures return tagged tuples (`{:error, :not_found}`) the caller handles
- Unexpected failures (bugs, violated invariants) raise and let the supervisor restart
- Don't write defensive `try/rescue` around code that should crash; don't crash on input the caller can reasonably send

## Application

These principles work together to create:
- **Highly maintainable code** — pure core logic that is easy to understand and modify
- **Testable components** — every boundary dependency can be replaced via its behaviour
- **Readable business logic** — contexts express domain concepts naturally
- **Resilient runtime** — supervision handles the unexpected, tagged tuples handle the expected
