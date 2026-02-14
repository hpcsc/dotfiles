---
disable-model-invocation: true
---

Implement Go interface test doubles claude: $ARGUMENTS

## Overview

This command creates a complete implementation folder structure for a Go interface, or reviews an existing implementation package to find and implement missing pieces.

## Arguments

- `$ARGUMENTS` - Either:
  - Interface name (e.g., `checkpoint.Store`) - creates new implementation package
  - Path to existing implementation package (e.g., `internal/domain/checkpoint/store`) - reviews and fills missing implementations

## Mode 1: Create New Implementation

### Step 1: Analyze the Interface

1. Find the interface in the codebase by searching for `type InterfaceName interface`
2. Parse the interface to extract:
   - Package name
   - Interface name
   - All method signatures (name, parameters, return values)
3. Determine the implementation package path based on interface location:
   - If interface is in `domain/checkpoint/store.go`, implementation goes in `domain/checkpoint/store/`

### Step 2: Create Implementation Package Structure

Create the following folder structure:

```
{implementation_package_path}/
├── blank.go           // Stub implementation
├── memory.go          // In-memory implementation for happy path tests
├── broken.go          // Always-fails implementation for error tests
├── fake.go            // Recording implementation for call verification
└── memory_test.go     // Tests for memory implementation
```

### Step 3: Implement Each File

#### blank.go
- Create a stub implementation of the interface
- Include interface assertion: `var _ {InterfaceType} = (*{ImplementationType})(nil)`
- Leave methods as stubs returning nil or zero values
- Example: `var _ checkpoint.Store = (*blank)(nil)`

#### memory.go
- Create in-memory implementation
- Include factory functions:
  - `NewEmpty{Interface}()` - returns empty state (e.g., `NewEmptyMemory()`)
  - `New{Interface}(initialData)` - returns pre-populated state (e.g., `NewMemory(map[string]uint64{...})`)
- Include interface assertion
- Methods should store data in memory and return successfully

#### broken.go
- Create always-fails implementation with fluent API
- Include factory: `NewBroken() *broken`
- Include fluent setters: `With{Method}Error(err error) *broken` for each method
- Include interface assertion
- Each method returns the configured error

#### fake.go
- Create recording implementation for call verification
- Include factory: `NewFake() *fake`
- Include fields to record calls: `CalledMethodName`, etc.
- Include fluent setters for configurable behavior
- Include interface assertion

#### memory_test.go
- Test the memory implementation
- Use testify `require` for assertions

### Step 4: Verify

Run `go build` to ensure all implementations compile correctly.

---

## Mode 2: Review Existing Package

When given a path to an existing implementation package, review it and create missing files.

### Step 1: Analyze Existing Package

1. List all `.go` files in the package (excluding test files)
2. Identify which implementations exist: blank, memory, broken, fake
3. Find the interface being implemented by:
   - Looking for interface assertion `var _ Interface = ...`
   - Or finding the interface in the parent package

### Step 2: Identify Missing Implementations

Check for:
- `blank.go` - stub implementation (skip if an actual production implementation exists in the package)
- `memory.go` - in-memory implementation with `NewEmpty*()` and `New*()` factories
- `broken.go` - error implementation with fluent API
- `fake.go` - recording implementation
- `memory_test.go` - tests for memory implementation

### Step 3: Implement Missing Files

For each missing implementation, create the file following the patterns in Mode 1.

### Step 4: Verify

Run `go build` to ensure all implementations compile correctly.

---

## Example

### Create new:
```
/implement-go-interface checkpoint.Store

// Creates:
internal/domain/checkpoint/store/
├── blank.go
├── memory.go
├── broken.go
├── fake.go
└── memory_test.go
```

### Review existing:
```
/implement-go-interface internal/domain/checkpoint/store

// Reviews and creates missing files
```

## Requirements

Follow the patterns from testing-patterns.md:
- All implementations must have interface assertion: `var _ Interface = (*Implementation)(nil)`
- Use fluent API for broken implementation: `NewBroken().WithMethodError(err)`
- Memory implementation should support both empty (`NewEmptyMemory()`) and pre-populated state (`NewMemory(data)`)
- Recording implementation should track all method calls
- All files should be properly formatted with `go fmt`
- Tests must use testify `require` for assertions
