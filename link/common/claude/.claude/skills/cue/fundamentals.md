# CUE Fundamentals

This document covers core CUE concepts, syntax, and language features.

## Definitions (Schemas)

Definitions start with `#` and define reusable schemas:

```cue
// Basic definition
#Person: {
    name:    string
    age:     int & >0
    email?:  string  // optional field
}

// Closed definition - rejects unknown fields
#Config: {
    host: string
    port: int | *8080  // default value
}
```

## Constraints

CUE's type system includes powerful constraints:

```cue
// Type constraints
name: string
count: int & >=0 & <=100

// Enum constraints
status: "pending" | "active" | "completed"

// Pattern constraints (regex)
email: =~"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"

// Struct constraints
config: {
    host: string
    port: int & >0 & <65536
}
```

## Unification

CUE uses **unification**, not assignment. Values must be compatible to merge:

```cue
// Unification merges compatible values
a: {x: 1}
a: {y: 2}
// Result: a: {x: 1, y: 2}

// Assertions via unification
expected: "foo"
actual:   "foo"
assert:   expected & actual  // passes if equal

// Incompatible values cause errors
x: 1
x: 2  // ERROR: conflicting values
```

## List Comprehensions

Transform and filter lists with comprehensions:

```cue
// Basic transformation
items: ["a", "b", "c"]
upper: [for x in items {strings.ToUpper(x)}]
// Result: ["A", "B", "C"]

// Filter with conditions
evens: [for x in [1,2,3,4,5] if mod(x, 2) == 0 {x}]
// Result: [2, 4]

// Nested iteration
pairs: [for x in [1,2] for y in ["a","b"] {"\(x)\(y)"}]
// Result: ["1a", "1b", "2a", "2b"]
```

## Imports

Use built-in packages for common operations:

```cue
import (
    "encoding/json"
    "strings"
    "list"
    "math"
)

data: json.Marshal({x: 1})
upper: strings.ToUpper("hello")
count: list.Len([1, 2, 3])
```

## Conditional Fields

Add fields conditionally:

```cue
#Config: {
    #debug: bool | *false

    logLevel: *"info" | string
    if #debug {
        logLevel: "debug"
        verbose:  true
    }
}
```

## Default Values

Use `|` with `*` to specify defaults:

```cue
#Server: {
    host: string | *"localhost"
    port: int | *8080
    tls:  bool | *false
}

// Instantiate with defaults
server: #Server & {}
// Result: {host: "localhost", port: 8080, tls: false}
```

## String Interpolation

Embed expressions in strings:

```cue
#Step: {
    #name: string
    #env:  string

    key:   "\(#name)-\(#env)"
    label: "Deploy \(#name) to \(#env)"
}
```

## Embedding

Compose definitions through embedding:

```cue
#Base: {
    name: string
    version: string
}

#Extended: {
    #Base  // embed all fields from #Base
    extra: string
}

// Result: #Extended has name, version, and extra
```

## Hidden Fields

Fields starting with `_` are excluded from output:

```cue
_internal: "not in output"
visible: "in output"

_helper: {
    x: 1
    y: 2
}

result: _helper.x + _helper.y  // Use hidden values
```

## Struct Literals vs Definitions

```cue
// Struct literal - concrete value
config: {
    host: "localhost"
    port: 8080
}

// Definition - reusable schema
#Config: {
    host: string
    port: int
}

// Use definition
myConfig: #Config & {
    host: "example.com"
    port: 9000
}
```

## Disjunctions (OR)

Multiple valid alternatives:

```cue
// Type disjunction
value: int | string

// Value disjunction (enum)
status: "active" | "inactive" | "pending"

// Default with disjunction
level: "info" | "warn" | "error" | *"info"
```

## Conjunctions (AND)

Multiple constraints that must all hold:

```cue
// Must be int AND positive AND less than 100
count: int & >0 & <100

// Multiple struct constraints
config: {host: string} & {port: int} & {tls: bool}
```
