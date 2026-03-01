# Go Naming Patterns

## Natural Language Interface Pattern

A key architectural pattern is the **Package.Interface → Natural Language** convention that creates self-documenting, readable code:

```go
// Reads as natural English phrases
command.Bus        // "command bus"
event.Stream       // "event stream"
command.Handler   // "command handler"
route.Routable     // "route routable"
```

## Pattern Structure

```
domain/
├── command/           # Interface definition package
│   ├── bus.go         # command.Bus interface
│   ├── handler.go     # command.Handler interface
│   ├── bus/           # command.Bus implementation subpackage
│   │   ├── inmemory.go # In-memory command.Bus implementation
│   │   └── fake.go     # Fake command.Bus implementation for tests
│   └── handler/        # command.Handler implementation subpackage
│       ├── inmemory.go # In-memory command.Handler implementation
│       └── fake.go     # Fake command.Handler implementation for tests
└── event/
    ├── stream.go      # event.Stream interface
    └── stream/        # Implementation subpackage
        ├── esdb.go    # Implements event.Stream
        ├── memory.go  # Implements event.Stream
        ├── broken.go  # Implements event.Stream
        └── fake.go    # Fake event.Stream implementation for tests
```

## Implementation Guidelines

### 1. Package Naming Rules

```go
// ✅ Good - Domain concepts as nouns
package command
package event
package route
package provisioning

// ❌ Avoid - Technical or implementation-focused names
package busimplementation
package eventstreamhandler
```

**Important:** Implementation package and file names should describe **what** they are or **how** they work, never use generic names like `impl`, `implementation`, `default`, or variations.

```go
// ✅ Good - Descriptive implementation names
command/bus/inmemory.go     // Describes storage mechanism
event/stream/esdb.go        // Describes backing technology
event/stream/memory.go      // Describes storage approach

// ❌ Avoid - Generic implementation names
command/bus/impl.go         // Says nothing about the implementation
command/bus/busimpl.go      // Redundant and uninformative
command/bus/default.go      // Which default? Why?
command/bus/implementation.go // Too verbose and generic
```

### 2. Interface Naming Rules

```go
// ✅ Good - Capabilities or roles
type Bus interface {...}
type Stream interface {...}
type Handler interface {...}
type Routable interface {...}

// ❌ Avoid - Including package name in interface
type CommandBus interface {...}  // Redundant with package name
type EventStream interface {...} // Redundant with package name
```

### 3. Concrete Struct Naming (No Interface)

When a package has a single concrete struct with no interface (no need for multiple implementations or test fakes), prefer a **role or capability noun** that describes what the struct does. Fall back to `Instance` when no better name exists.

```go
// ✅ Best — descriptive role noun, no stuttering
package lexer
type Tokenizer struct { ... }    // lexer.Tokenizer — describes what it does
func New(...) *Tokenizer { ... }

package config
type Loader struct { ... }       // config.Loader
func New(...) *Loader { ... }
```

```go
// ✅ Acceptable — when no descriptive name adds clarity over the package name
package lexer
type Instance struct { ... }     // lexer.Instance — fallback
func New(...) *Instance { ... }
```

**Naming priority:**
1. A role/capability noun that describes what the struct does (`Tokenizer`, `Loader`, `Resolver`)
2. `Instance` as a fallback when the package name already says it all

**When NOT to use either:**
- Multiple implementations exist or are likely → use an interface
- Consumers need to stub it in tests → define an interface instead

### 4. Constructor Pattern

```go
// Return interface types for real implementations
func NewBus() command.Bus {...}
func NewESDBStream(...) (event.Stream, error) {...}

// Return concrete fake types for test doubles (they have additional setup methods)
func NewFakeBus() *FakeBus {...}
func NewFakeStream() *FakeStream {...}
```

### 5. Interface Compliance Check

```go
// Clear assertion of interface implementation
var _ command.Bus = (*bus)(nil)
var _ event.Stream = (*esdb)(nil)
```

## Summary

Following these naming patterns creates:
- **Self-documenting code**: `command.Bus`, `event.Stream` read as natural English
- **Clear package boundaries**: Each package has focused responsibility
- **Discoverable APIs**: Interfaces are easy to find and understand
- **Consistent structure**: Predictable organization across the codebase

**Key Takeaways:**
- Package names are domain nouns, interface names are capabilities/roles
- Implementation files describe what they are or how they work (never `impl` or `default`)
- Real constructors return interfaces, fake constructors return concrete types
- Always include interface compliance checks with `var _ Interface = (*implementation)(nil)`
