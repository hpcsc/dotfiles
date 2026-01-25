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

## Application

These principles work together to create:
- **Highly maintainable code** - Easy to understand and modify
- **Testable components** - Every dependency can be mocked
- **Readable business logic** - Code expresses domain concepts naturally
- **Flexible architecture** - Easy to swap implementations
