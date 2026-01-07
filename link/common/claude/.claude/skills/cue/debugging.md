# Debugging CUE

Troubleshooting validation errors and understanding CUE behavior.

## Debugging Commands

### See What CUE Evaluates To

```bash
# Evaluate and print CUE values
cue eval file.cue

# Show specific field
cue eval file.cue -e fieldName

# Show specific nested field
cue eval file.cue -e 'config.server.host'

# Show all fields including hidden (_prefix)
cue eval -a file.cue
```

### Validation Errors

```bash
# Basic validation
cue vet file.cue

# Verbose errors with context
cue vet -v file.cue

# Concrete mode - require all values to be concrete
cue vet -c file.cue
```

### Export and Inspect

```bash
# Export to JSON for inspection
cue export file.cue --out json | jq .

# Export to YAML
cue export file.cue --out yaml

# Export specific field
cue export file.cue -e config --out json
```

### Definition Inspection

```bash
# Show schema/definition structure
cue def file.cue

# Show definition for specific field
cue def file.cue -e '#Config'
```

## Common Error Patterns

### Conflicting Values

```
error: conflicting values 8080 and 9000
    file.cue:10:10
    file.cue:15:10
```

**Cause**: Same field assigned two different values.

**Debug**:
```bash
# Find both assignments
grep -n "port:" file.cue
```

**Fix**: Ensure unification compatibility or use conditionals:
```cue
// BAD
port: 8080
port: 9000

// GOOD: Conditional
port: 8080
if #production {
    port: 9000
}
```

### Incomplete Values

```
error: incomplete value
    file.cue:20:5
```

**Cause**: A field requires a concrete value but only has a type constraint.

**Debug**:
```bash
# Check what's incomplete
cue eval -c file.cue
```

**Fix**: Provide concrete values:
```cue
// BAD: Type only, no value
config: {
    host: string  // Incomplete
}

// GOOD: Concrete value
config: {
    host: "localhost"
}

// GOOD: Type with default
#Config: {
    host: string | *"localhost"
}
```

### Field Not Found

```
error: field not found: someField
    file.cue:25:12
```

**Cause**: Referencing a field that doesn't exist.

**Debug**:
```bash
# Show all available fields
cue eval -a file.cue

# Check definition structure
cue def file.cue -e '#Config'
```

**Fix**: Verify field name and path:
```cue
// Check if field is hidden
cue eval -a file.cue  # Shows _hidden fields

// Check if in different scope
config: {
    inner: {
        value: 42
    }
}
// Access as: config.inner.value
```

### Invalid Regex

```
error: invalid regex pattern
    file.cue:30:15
```

**Cause**: Malformed regular expression.

**Debug**: Test regex separately:
```bash
# Test with echo
echo "test@example.com" | grep -E '^[^@]+@[^@]+\.[^@]+$'
```

**Fix**: Escape special characters properly:
```cue
// BAD: Single backslash
email: =~"^[\w]+@[\w]+\.[\w]+$"

// GOOD: Double backslash in CUE strings
email: =~"^[\\w]+@[\\w]+\\.[\\w]+$"
```

### List Index Out of Range

```
error: index out of range [3] with length 2
    file.cue:35:20
```

**Cause**: Accessing list element that doesn't exist.

**Debug**:
```bash
# Check list length
cue eval file.cue -e 'list.Len(myList)'
```

**Fix**: Use safe access patterns:
```cue
// BAD: Hardcoded index
value: items[3]

// GOOD: Search and verify
_found: [for i in items if i.name == "target" {i}]
value: *null | _found[0]  // Default to null if not found

// GOOD: Length check
value: if list.Len(items) > 3 {items[3]}
```

### Circular Reference

```
error: structural cycle
    file.cue:40:8
```

**Cause**: Field depends on itself directly or indirectly.

**Debug**: Trace dependency chain:
```bash
# Evaluate with verbose errors
cue eval -v file.cue
```

**Fix**: Break the cycle:
```cue
// BAD: Circular
a: b + 1
b: a - 1

// GOOD: Both depend on external value
base: 10
a: base + 1
b: base - 1
```

## Debugging Techniques

### Progressive Evaluation

Narrow down errors by evaluating progressively:

```bash
# Start with just definitions
cue eval -e '#Config' file.cue

# Add instance
cue eval -e 'config' file.cue

# Check specific field
cue eval -e 'config.server.host' file.cue
```

### Isolate the Problem

Create minimal reproduction:

```cue
// Copy problematic section to new file
#Test: {
    // Minimal fields that reproduce error
}

instance: #Test & {
    // Minimal values that trigger error
}
```

### Use Hidden Debug Fields

Add temporary debug fields:

```cue
config: {
    host: "example.com"
    port: 8080

    // Debug: Check what CUE sees
    _debug: {
        hostType: "\(typeof(host))"
        portValue: port
        _allFields: config  // See full structure
    }
}
```

### Compare Expectations

Use assertions to find divergence:

```cue
_test: {
    actual: someComplexExpression

    _debugActual: json.Marshal(actual)

    expected: {
        field1: "value1"
        field2: 42
    }

    _debugExpected: json.Marshal(expected)

    // This will fail with full diff if not equal
    assert: actual & expected
}
```

### Check Type Information

```bash
# Show concrete types
cue eval file.cue | jq 'walk(if type == "object" then . + {"_type": type} else . end)'
```

## Validation Anti-Patterns

### Silent Failures

**Problem**: Tests pass when they shouldn't.

**Debug**:
```bash
# Temporarily break the code
# If validation still passes, test is broken
```

**Fix**: Always verify tests can fail.

### Default Value Surprises

**Problem**: Defaults override your values.

```cue
// Check what defaults are active
cue eval -a file.cue
```

**Fix**: Use explicit values or adjust default precedence:
```cue
// Default: *8080 means 8080 unless overridden
port: int | *8080

// Override works
port: 9000  // Results in 9000
```

### Cross-Package Issues

**Problem**: Values work in one file but not when imported.

**Debug**:
```bash
# Evaluate with imports
cue eval ./...

# Check import paths
cue mod init github.com/user/repo
```

**Fix**: Ensure proper package structure and imports.

## Performance Issues

### Slow Validation

```bash
# Profile evaluation time
time cue eval file.cue > /dev/null

# Check for expensive operations
# - Large list comprehensions
# - Deep nesting
# - Complex regex patterns
```

**Fix**: Optimize hot paths:
```cue
// Cache expensive computations
_computed: expensiveOperation()
use1: _computed.field1
use2: _computed.field2
```

## Debugging Checklist

When stuck:

1. [ ] Run `cue vet -v` for detailed errors
2. [ ] Use `cue eval -a` to see all fields including hidden
3. [ ] Isolate problem in minimal file
4. [ ] Check for field name typos
5. [ ] Verify import paths
6. [ ] Test regex patterns separately
7. [ ] Add `_debug` fields to inspect values
8. [ ] Verify test can fail by breaking code
9. [ ] Check for circular dependencies
10. [ ] Look for field name collisions in nested definitions
