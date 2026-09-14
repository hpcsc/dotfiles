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
var _ command.Bus = (*inMemory)(nil)
var _ event.Stream = (*esdb)(nil)
```

### 6. File Naming Rules

**A file is named for the type it declares.** The file name is the type's name, or its main noun, in the repository's file-name style. Most repositories use snake_case.

```
✅ document_uploader.go     declares documentUploader
✅ condition.go             declares closeCondition and its constructors
✅ esdb.go                  declares esdb, the event.Stream that uses EventStoreDB

❌ documentupload.go        the name is an action, and the repository writes document_uploader.go
❌ ticketlinkreader.go      the repository writes ticket_link_reader.go
❌ corpus.go                declares five ...Spec types and no corpus
```

**A file whose name matches none of its declarations is misnamed.** Rename the file, or move each declaration to the file that has its name. A file that declares two unrelated types is two files (`architecture-principles.md` §7).

**A test file has the name of the file it tests, plus `_test`.** `condition_test.go` tests `condition.go`. Do not add a qualifier such as `_internal`: the `package` line already says whether the test is inside the package.

**A file of test support is named for the type it declares, not for its role.** `harness.go` declares `harness`. `support_test.go` reads as the tests for `support`, and `instruments_test.go` reads as the tests for `instruments`.

In an implementation subpackage (§1), name the type for its mechanism too, so the file and the type agree: `inmemory.go` declares `inMemory`.

## Summary

Following these naming patterns creates:
- **Self-documenting code**: `command.Bus`, `event.Stream` read as natural English
- **Clear package boundaries**: Each package has focused responsibility
- **Discoverable APIs**: Interfaces are easy to find and understand
- **Consistent structure**: Predictable organization across the codebase

**Key Takeaways:**
- Package names are domain nouns, interface names are capabilities/roles
- Implementation files describe what they are or how they work (never `impl` or `default`)
- Each file is named for the type it declares; its test file is that name plus `_test`
- Real constructors return interfaces, fake constructors return concrete types
- Always include interface compliance checks with `var _ Interface = (*implementation)(nil)`
