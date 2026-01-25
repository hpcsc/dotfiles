# Go Development Workflow

## When Creating New Components

Follow this workflow when adding new functionality:

### 1. Identify the Business Concept
Choose a noun that represents the application concept. Think domain language, not technical implementation.

Examples:
- ✅ `provisioning`, `command`, `event`, `route`
- ❌ `busimplementation`, `handler_manager`

### 2. Define Interfaces in the Appropriate Package
Use natural language naming that reads well when combined with the package name.

```go
package command

// command.Bus reads naturally
type Bus interface {
    Register(cmdType string, handler Handler) error
    Dispatch(ctx context.Context, cmd Command) error
}
```

### 3. Create Implementation Subpackages
Separate implementations from interfaces, with one subpackage per interface.

```
command/
├── bus.go           # Interface definition
└── bus/
    ├── inmemory.go  # Real implementation
    └── fake.go      # Test double
```

### 4. Write Constructors That Return Interfaces
Hide implementation details from consumers.

```go
// Real implementations return interfaces
func NewBus() command.Bus {
    return &bus{
        handlers: make(map[string]command.Handler),
    }
}

// Fakes return concrete types (they have additional setup methods)
func NewFakeBus() *FakeBus {
    return &FakeBus{
        commands: make([]*domain.Command, 0),
    }
}
```

### 5. Add Interface Compliance Checks
Compile-time verification that your type implements the interface.

```go
var _ command.Bus = (*bus)(nil)
```

### 6. Create Test Doubles in the Same Package
Test doubles and real implementations co-located in the same package, both implementing the same interface.

```go
// In command/bus/fake.go
type FakeBus struct {
    commands []*domain.Command
    err      error
}

func NewFakeBus() *FakeBus { ... }

func (f *FakeBus) Register(cmdType string, handler command.Handler) error { ... }
func (f *FakeBus) Dispatch(ctx context.Context, cmd command.Command) error { ... }

// Additional methods for test setup and verification
func (f *FakeBus) WithError(err error) *FakeBus { ... }
func (f *FakeBus) TriggeredWithCommand() *command.Command { ... }

var _ command.Bus = (*FakeBus)(nil)
```

## When Organizing Code

### 1. Use Feature-Based Organization
Group related functionality together by business domain.

```
domain/
├── provisioning/
│   ├── request.go
│   ├── validator.go
│   └── handler.go
├── command/
│   ├── bus.go
│   └── bus/
└── event/
    ├── stream.go
    └── stream/
```

### 2. Apply Natural Language Naming
Make code self-documenting through thoughtful naming.

### 3. Write Comprehensive Tests
Use the established testing patterns:
- Test observable behaviors through public APIs
- Use subtest organization (`t.Run`)
- Co-locate test doubles with implementations
- Apply appropriate build tags (`//go:build unit` or `//go:build integration`)
- Include both happy path and error scenarios

## Quick Checklist

When creating new components, verify:
- [ ] Package name is a domain noun (not `impl`, `manager`, etc.)
- [ ] Interface name reads naturally with package name
- [ ] Implementation in subpackage with descriptive name
- [ ] Constructor returns interface (or concrete for fakes)
- [ ] Interface compliance check included
- [ ] Test doubles co-located with real implementations
- [ ] Comprehensive tests covering behavior

## Example Complete Structure

```
provisioning/
├── request.go              # Domain types
├── validator.go            # provisioning.Validator interface
├── handler.go              # provisioning.Handler interface
├── validator/
│   ├── default.go          # Real validator implementation
│   ├── default_test.go     # Tests for validator
│   └── fake.go             # Fake validator for testing
└── handler/
    ├── http.go             # HTTP handler implementation
    ├── http_test.go        # Tests for HTTP handler
    └── fake.go             # Fake handler for testing
```
