# CUE Testing Patterns

Comprehensive guide to testing CUE configurations.

## Critical Rule: Verify Tests Can Fail

**ALWAYS verify tests can actually detect failures**. CUE's unification behavior can create false positives where tests pass even when they shouldn't.

### For New Code (TDD Approach)

1. Write a failing test first with expected behavior
2. Run `cue vet` - it MUST fail
3. Implement the code to make the test pass
4. Run `cue vet` - it should pass now

```bash
# Write test first
cue vet .  # MUST fail (no implementation yet)

# Implement code
cue vet .  # Should pass now
```

### For Existing Code (Retrospective Tests)

1. Write the test for existing behavior
2. Run `cue vet` - it should pass
3. **Temporarily break the code** being tested
4. Run `cue vet` - it MUST fail (proves test works)
5. Restore the original code

```bash
# 1. Add test for existing behavior
cue vet .  # Should pass

# 2. Temporarily modify code to break the behavior
cue vet .  # MUST fail - if it passes, the test is broken!

# 3. Restore original code
cue vet .  # Should pass again
```

## Basic Test Structure

Tests are hidden fields (prefix with `_`) containing assertions:

```cue
_testMyDefinition: {
    testCaseName: {
        actual:   (#MyDef & {input: "value"}).output
        expected: "expected result"
        assert:   actual & expected
    }
}
```

If `actual` and `expected` don't unify, `cue vet` fails.

## Testing Complex Types

Use `json.Marshal` for clearer error messages with arrays and objects:

```cue
import "encoding/json"

_testArrays: {
    matchesExpected: {
        actual:   [1, 2, 3]
        expected: [1, 2, 3]
        _got:     json.Marshal(actual)
        _want:    json.Marshal(expected)
        assert:   _got & _want
    }
}

_testStructs: {
    configMatches: {
        actual:   {host: "localhost", port: 8080}
        expected: {host: "localhost", port: 8080}
        _got:     json.Marshal(actual)
        _want:    json.Marshal(expected)
        assert:   _got & _want
    }
}
```

## Finding Nested Values

Use list comprehensions instead of hardcoded array indices:

```cue
import "strings"

_testPlugins: {
    findsDockerPlugin: {
        // GOOD: Search for the plugin
        _plugins: [for p in config.plugins for k, v in p if strings.HasPrefix(k, "docker") {v}]
        actual:   _plugins[0].image
        expected: "myimage:latest"
        assert:   actual & expected
    }

    // BAD: Hardcoded index - brittle if order changes
    badTest: {
        actual:   config.plugins[2].docker.image
        expected: "myimage:latest"
        assert:   actual & expected
    }
}
```

## Test Fixtures

Create multiple fixture configurations for different test scenarios:

```cue
// Default configuration
_pipelineDefault: lib.#MyPipeline & {
    #service: "myservice"
    #prodEnvs: ["prod"]
}

// Configuration with feature enabled
_pipelineFeatureEnabled: lib.#MyPipeline & {
    #service: "myservice"
    #prodEnvs: ["prod"]
    #enableFeature: true
}

// Test both fixtures
_testDefaults: {
    usesDefaultBehavior: {
        actual:   _pipelineDefault.someField
        expected: "default-value"
        assert:   actual & expected
    }
}

_testFeatureEnabled: {
    overridesDefault: {
        actual:   _pipelineFeatureEnabled.someField
        expected: "feature-value"
        assert:   actual & expected
    }
}
```

## Testing Observable Outputs vs Hidden Fields

**Prefer testing observable outputs** - fields that appear in the final YAML/JSON export.

### Good: Test Observable Outputs

```cue
_testSteps: {
    generatesPlanStep: {
        // Test via observable step key in output
        _steps:   [for step in _pipeline.steps if step.key == "plan-fuel-infra-dev" {step}]
        actual:   len(_steps)
        expected: 1
        assert:   actual & expected
    }

    stepHasCorrectCommand: {
        _steps:   [for step in _pipeline.steps if step.key == "plan-fuel-infra-dev" {step}]
        actual:   _steps[0].command
        expected: "terraform plan"
        assert:   actual & expected
    }
}
```

### Avoid: Testing Hidden Fields with Defaults

```cue
// BAD: This may silently pass due to CUE limitation
_testInfraDir: {
    actual:   _pipeline.#infraDir  // Definition field with default
    expected: "fuel/infra"
    assert:   actual & expected
}
```

**CUE Limitation**: Definition fields with default values (`#field: string | *"default"`) don't properly participate in unification when accessed from another package. Tests may pass even with incorrect expected values.

**Solution**: Test the observable effect of the field:

```cue
// GOOD: Test the observable effect
_testInfraDir: {
    _steps:   [for step in _pipeline.steps if step.key == "plan-fuel-infra-dev" {step}]
    actual:   _steps[0].directory  // Observable in step output
    expected: "fuel/infra"
    assert:   actual & expected
}
```

## Test Organization

Group tests by functionality:

```cue
// Input defaults
_testDefaults: {
    usesDefaultPort: { /* ... */ }
    usesDefaultHost: { /* ... */ }
}

// Conditional logic
_testDebugMode: {
    setsVerboseWhenDebug: { /* ... */ }
    setsLogLevelDebug: { /* ... */ }
}

// Step generation
_testStepGeneration: {
    createsDeployStep: { /* ... */ }
    createsPlanStep: { /* ... */ }
}

// Dependencies
_testDependencies: {
    planDependsOnInit: { /* ... */ }
    deployDependsOnPlan: { /* ... */ }
}
```

## Testing Error Cases

Test that invalid inputs are properly rejected:

```cue
// This should fail validation
_testInvalidConfig: {
    #InvalidConfig: #Config & {
        port: -1  // Invalid: port must be positive
    }
}
```

Run `cue vet` - if it fails, the validation is working correctly.

## Parametric Tests

Test multiple inputs with list comprehensions:

```cue
_testEnvNames: {
    for env in ["dev", "staging", "prod"] {
        "\(env)HasCorrectKey": {
            _pipeline: lib.#Pipeline & {#env: env}
            actual:   _pipeline.steps[0].key
            expected: "deploy-\(env)"
            assert:   actual & expected
        }
    }
}
```

## Best Practices

1. **Name tests descriptively** - `usesDefaultPort` not `test1`
2. **One assertion per test** - Easier to diagnose failures
3. **Always verify tests can fail** - Break code temporarily to confirm
4. **Test observable outputs** - Not internal fields with defaults
5. **Use list comprehensions** - Avoid brittle array indices
6. **Use `json.Marshal`** - Clearer errors for complex types
7. **Organize by functionality** - Group related tests together
8. **Create fixtures** - Reuse configurations across tests
