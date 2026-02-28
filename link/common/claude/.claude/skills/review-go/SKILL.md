---
description: Review a Go package for adherence to project Go guidelines (naming, architecture, structure, workflow). Takes a package path and reports violations.
disable-model-invocation: true
---

# Go Package Guidelines Review

Review a Go package against project guidelines: $ARGUMENTS

## Required Reading

Before reviewing, read ALL guidelines:

```bash
cat ~/.config/ai/guidelines/go/naming-patterns.md
cat ~/.config/ai/guidelines/go/architecture-principles.md
cat ~/.config/ai/guidelines/go/development-workflow.md
```

## Identify the Package

Resolve `$ARGUMENTS` to a package path. If it's a relative path, resolve from the current directory. If it's a Go import path, find the corresponding directory.

Find all `.go` files in the package (including subpackages):

```bash
fd -e go . <package-path>
```

## Review Process

### 1. Map the Package Structure

Understand the layout:
- Which files are interfaces vs implementations?
- Where do test doubles live?
- Is there a subpackage structure?

### 2. Check Naming Patterns

For each file, type, interface, and function:

- **Package names**: Domain nouns (`command`, `event`), not technical names (`impl`, `manager`, `handler_manager`, `util`, `helper`)
- **Interface names**: Read naturally with package name (`command.Bus`, not `command.CommandBus`). No redundant package name in the type name.
- **File names**: Descriptive of what they contain (`inmemory.go`, `esdb.go`), not generic (`impl.go`, `default.go`, `implementation.go`)
- **Constructor names**: Follow Go conventions (`NewX`, `NewXWithY`)

### 3. Check Architecture Principles

- **Dependency Inversion**: Do high-level modules depend on interfaces, not concrete types?
- **Constructor injection**: Are dependencies injected through constructors, not created internally?
- **Interface size**: Are interfaces small and focused (Role Interface pattern)?
- **Interface ownership**: Consumer-defined for external deps, provider-defined for pluggable infrastructure?

### 4. Check Development Workflow Conventions

- **Constructor return types**: Real constructors return interface types, fake constructors return concrete types
- **Interface compliance checks**: `var _ Interface = (*impl)(nil)` present for each implementation
- **Test double co-location**: Fakes/broken/memory implementations live alongside real implementations
- **Package structure**: Interface in parent package, implementation in subpackage (when following Natural Language Interface pattern)

### 5. Check Package Organization

- **Feature-based**: Organized by domain concept, not technical layer
- **No mixed concerns**: Interface definitions and implementations separated appropriately
- **Subpackage convention**: `concept/interface.go` + `concept/subpackage/implementation.go`

## Output Format

```markdown
## Package Review: `<package-path>`

### Structure

[Brief description of the package layout]

### Findings

#### 1. [Category] — [file:line]

**Issue**: [What violates the guidelines]
**Guideline**: [Which guideline and specific rule]
**Fix**: [Concrete action to resolve]

[Repeat for each finding]

### Summary

- **Files reviewed**: [count]
- **Violations found**: [count]
- **Verdict**: [PASS / NEEDS WORK]

[If NEEDS WORK, list the top 3 most impactful fixes in priority order]
```

## What NOT to Flag

- Logic bugs or test quality (use `/review-go-tests` for that)
- Security, performance, or concurrency issues
- Code in files outside the target package
- Conventions in third-party dependencies
- Style preferences not covered by the guidelines (e.g., line length, brace placement)
