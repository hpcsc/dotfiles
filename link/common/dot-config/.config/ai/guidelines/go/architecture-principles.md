# Go Architecture Principles

## Core Principles

### 1. Natural Language Readability
- Package names combined with interface names create English phrases
- Code reads like documentation
- Domain terminology drives naming

### 2. Dependency Inversion Principle (DIP)
- High-level modules depend on abstractions (interfaces)
- Interfaces are defined by consuming layers
- Low-level implementations implement interfaces

### 3. Single Responsibility Principle (SRP)
- Each package has one well-defined responsibility
- Interfaces are small and focused
- Clear separation between concerns

### 4. Role Interface Pattern
- Define interfaces based on what consumers need, not what implementers provide
- Interfaces represent the role an object plays in a specific collaboration
- Expose only the methods required for that interaction
- Different consumers may define different interfaces for the same concrete type

**Two Approaches:**
- **Provider-Defined**: Package defines interface for pluggable implementations (e.g., `event.Stream`, `command.Bus`)
- **Consumer-Defined**: Consumer defines interface for only what they need (e.g., wrapping Stripe SDK, testing seams)

**Key Concepts:**
- **Consumer-Driven Design**: Interfaces belong to the package that uses them
- **Interface Segregation**: Avoid large, monolithic interfaces; prefer multiple small interfaces
- **Minimal Surface Area**: Include only methods actually used by the consumer

**Rule of Thumb:**
- Building reusable infrastructure → Provider-defined interface
- Consuming external dependencies → Consumer-defined (role) interface
- In doubt → Start with consumer-defined (easier to refactor later)

### 5. Testability by Design
- All components are testable through dependency injection
- Test doubles are first-class citizens
- Clear separation between unit and integration tests

### 6. Dependency Injection
- Dependencies injected through constructors
- Interface-based dependencies for testability
- Clear separation of concerns

### 7. A Type and Its Methods Live in One File
- The file that declares a type declares every method on it. Reading the type's file is reading everything it can do.
- **A new file means a new type.** When the declaring file grows too large, extract a collaborator with its own name, its own dependencies and its own constructor — never move some of the methods sideways into a second file that keeps the same receiver.
- A second file with the same receiver is the symptom, not the problem: a file named for one capability adding methods to a type named for another has already named the type it should have declared.
- **And the converse: a file whose declarations do not refer to each other is already two files.** Treat the file's declarations as a graph — one declaration mentioning another is an edge. Two components with no edge between them are two files that happen to share a name. This is worth checking mechanically; it finds strandings the eye skips, such as a helper sitting in the file of a type that never calls it.

**Order within the file:**
- Declare the type, then its constructors, then its methods. A reader scrolling the type's behaviour should never pass through a different type to reach the rest of it.
- Free functions go last, together. A helper dropped between two methods reads as a third method until you check the receiver.
- A second type in the file is a part of the named one, and where it goes depends on which part. A small value type the named type's fields are written in — an enum, a pair — goes before it, because you need it to read the struct. A collection of it, or a satellite it owns, goes after, with its own methods following it.
- Keep a blank line between every top-level declaration. `gofmt` does not insert them, so a mechanical reorder can run four declarations together and still format clean.

**Extracting the collaborator:**
- Give it only the dependencies its own methods use, construct it in the owner's constructor, and have the owner delegate.
- That is what makes the split testable on its own, which moving methods between files never does. If the extracted type would need every field the original had, it was not a second responsibility — put the methods back and leave the file long.
- Generated code and build-tagged variants are exempt; they cannot live in the declaring file.

This is stricter than the standard library, which does spread large types across files. The strictness is deliberate: a receiver is not a namespace, and "which file does this method go in" should have exactly one answer.

## Application

These principles work together to create:
- **Highly maintainable code** - Easy to understand and modify
- **Testable components** - Every dependency can be mocked
- **Readable business logic** - Code expresses domain concepts naturally
- **Flexible architecture** - Easy to swap implementations
