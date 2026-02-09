# Common CUE Patterns and Anti-Patterns

Best practices and common pitfalls when working with CUE.

## Best Practices

### 1. Use Definitions for Schemas

Prefix reusable schemas with `#`:

```cue
// GOOD: Reusable schema
#Server: {
    host: string
    port: int & >0
    tls:  bool | *false
}

server1: #Server & {host: "a.com", port: 443}
server2: #Server & {host: "b.com", port: 80}

// BAD: Duplicated structure
server1: {
    host: "a.com"
    port: 443
    tls:  false
}
```

### 2. Use Hidden Fields for Internal Values

Prefix with `_` to exclude from exports:

```cue
// GOOD: Internal helpers hidden
_baseURL: "https://api.example.com"
_version: "v1"

endpoint: "\(_baseURL)/\(_version)/users"

// BAD: Internal values pollute output
baseURL: "https://api.example.com"  // Exported unnecessarily
version: "v1"
endpoint: "\(baseURL)/\(version)/users"
```

### 3. Prefer Unification Over Assignment

Let CUE validate consistency:

```cue
// GOOD: Multiple constraints unify
config: {host: string}
config: {port: int}
config: {host: "localhost", port: 8080}

// GOOD: Assertion via unification
expected: 42
actual:   someCalculation()
assert:   expected & actual  // Fails if not equal
```

### 4. Use List Comprehensions

Avoid hardcoded indices:

```cue
// GOOD: Search for what you need
_deploySteps: [for s in steps if s.type == "deploy" {s}]
deployCommand: _deploySteps[0].command

// BAD: Brittle - breaks if order changes
deployCommand: steps[5].command
```

### 5. Validate Incrementally

Run `cue vet` frequently during development:

```bash
# After each change
cue vet .

# Watch for changes (if using tools)
watch -n 1 cue vet .
```

## Anti-Patterns

### 1. Field Name Collisions in Nested Definitions

**Problem**: When outer and inner definitions have fields with the same name, inner scope wins.

```cue
// BAD: Name collision
#Outer: {
    #values: [...string] | *[]

    #Inner & {
        if len(#values) > 0 {  // Resolves to #Inner's #values!
            #values: #values
        }
    }
}

#Inner: {
    #values: [...string] | *["inner-default"]
}

// Result: conditional always sees #Inner's default!
```

**Solution**: Use different field names:

```cue
// GOOD: Different names avoid collision
#Outer: {
    #outerValues: [...string] | *[]

    #Inner & {
        if len(#outerValues) > 0 {  // Unambiguous!
            #values: #outerValues
        }
    }
}

#Inner: {
    #values: [...string] | *["inner-default"]
}
```

### 2. Testing Hidden Fields with Defaults

**Problem**: Definition fields with defaults don't properly unify across packages.

```cue
// BAD: May silently pass with wrong expected value
_testInfraDir: {
    actual:   _pipeline.#infraDir  // Field with default
    expected: "wrong/value"  // Test passes even though wrong!
    assert:   actual & expected
}
```

**Solution**: Test observable outputs:

```cue
// GOOD: Test what actually appears in output
_testInfraDir: {
    _steps:   [for step in _pipeline.steps if step.key == "plan" {step}]
    actual:   _steps[0].directory
    expected: "fuel/infra"
    assert:   actual & expected
}
```

### 3. Skipping Test Verification

**Problem**: Tests that can't fail are worse than no tests.

```cue
// BAD: Never verified this test can fail
_testValue: {
    actual:   config.someField
    expected: "anything"
    assert:   actual & expected
}
```

**Solution**: Always break code temporarily to verify test fails:

```bash
# 1. Add test
cue vet .  # Passes

# 2. Break the code being tested
cue vet .  # MUST fail - if not, test is broken

# 3. Restore code
```

### 4. Hardcoded Array Indices

**Problem**: Brittle tests that break when order changes.

```cue
// BAD: Hardcoded position
deployStep: steps[3]

// BAD: Assumes order
firstEnv: environments[0]
```

**Solution**: Search for what you need:

```cue
// GOOD: Find by attribute
_deploySteps: [for s in steps if s.type == "deploy" {s}]
deployStep: _deploySteps[0]

// GOOD: Find by name
_prodEnvs: [for e in environments if e.name == "prod" {e}]
prodEnv: _prodEnvs[0]
```

### 5. Generic Field Names

**Problem**: Vague names that don't convey meaning.

```cue
// BAD: What does 'data' mean?
#Config: {
    data: {...}
    items: [...]
    value: _
}

// GOOD: Specific names
#Config: {
    serverSettings: {...}
    deploymentSteps: [...]
    retryCount: int
}
```

### 6. Overly Permissive Constraints

**Problem**: Constraints that don't validate enough.

```cue
// BAD: Too loose
port: int  // Allows negative, zero, > 65535

// GOOD: Appropriate constraints
port: int & >0 & <65536

// BAD: Any string accepted
email: string

// GOOD: Validated format
email: string & =~"^[^@]+@[^@]+\\.[^@]+$"
```

### 7. Exporting Internal Implementation Details

**Problem**: Internal helpers pollute the output.

```cue
// BAD: Implementation details exported
baseURL: "https://api.com"
version: "v1"
internalCache: {...}
endpoint: "\(baseURL)/\(version)"

// GOOD: Hide internal details
_baseURL: "https://api.com"
_version: "v1"
_internalCache: {...}
endpoint: "\(_baseURL)/\(_version)"
```

## Workflow Patterns

### Configuration Pipeline

```cue
// 1. Define schema
#Config: {
    #service: string
    #env:     "dev" | "staging" | "prod"

    host: string | *"\(#service).\(#env).example.com"
    port: int | *8080
}

// 2. Create instance
myService: #Config & {
    #service: "api"
    #env:     "prod"
    port:     443  // Override default
}

// 3. Export
// Run: cue export --out yaml
```

### Conditional Configuration

```cue
#Pipeline: {
    #enableCache: bool | *false

    steps: [
        {name: "build", command: "make build"},
        if #enableCache {
            {name: "cache", command: "save-cache"}
        },
        {name: "deploy", command: "make deploy"},
    ]
}
```

### Multi-Environment Configuration

```cue
#Service: {
    #env: "dev" | "staging" | "prod"

    replicas: int | *1
    if #env == "prod" {
        replicas: 3
    }

    resources: {
        memory: string | *"256Mi"
        if #env == "prod" {
            memory: "1Gi"
        }
    }
}

dev:     #Service & {#env: "dev"}
staging: #Service & {#env: "staging"}
prod:    #Service & {#env: "prod"}
```

## Summary

**Do**:
- Use `#` for schemas
- Use `_` for internal values
- Test observable outputs
- Use list comprehensions
- Validate incrementally
- Use unique field names in nested definitions
- Always verify tests can fail

**Don't**:
- Use same field names in nested definitions
- Test hidden fields with defaults
- Use hardcoded array indices
- Export internal implementation details
- Skip test verification
- Use overly permissive constraints
