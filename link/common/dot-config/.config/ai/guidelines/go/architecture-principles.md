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
- Free functions go last, together. A helper dropped between two methods reads as a third method until you check the receiver. After §8, the only free functions left are the ones that §8 keeps.
- A second type in the file is a part of the named one, and where it goes depends on which part. A small value type the named type's fields are written in — an enum, a pair — goes before it, because you need it to read the struct. A collection of it, or a satellite it owns, goes after, with its own methods following it.
- Keep a blank line between every top-level declaration. `gofmt` does not insert them, so a mechanical reorder can run four declarations together and still format clean.

**Extracting the collaborator:**
- Give it only the dependencies its own methods use, construct it in the owner's constructor, and have the owner delegate.
- That is what makes the split testable on its own, which moving methods between files never does. If the extracted type would need every field the original had, it was not a second responsibility — put the methods back and leave the file long.
- Generated code and build-tagged variants are exempt; they cannot live in the declaring file.

This is stricter than the standard library, which does spread large types across files. The strictness is deliberate: a receiver is not a namespace, and "which file does this method go in" should have exactly one answer.

### 8. A Helper That One Type Uses Is a Method of That Type
- A private function that only one type's methods call is a method of that type. A package-level function adds a name that every file in the package can see, and it hides which type the behaviour belongs to.
- This is also true when the helper is pure, reads no field, or sits in its own file. A method that does not use its receiver is fine. Name the receiver as the type's other methods do.
- Keep a free function in three cases only:
  - Code passes it as a function value, and a method would need two-step construction.
  - It is the logic of a file that owns package-level data, such as a lookup table and the function that reads the table.
  - The package holds its rules in free functions over plain data. There, the function sits where every rule sits.
- Test files are exempt. A test helper is not part of the package that production code sees.

```go
// ❌ Only *Drafter calls it, but every file in the package can see it
func renderText(draft Draft) string { ... }

// ✅
func (d *Drafter) renderText(draft Draft) string { ... }
```

**A private function that two types call holds a rule that no type owns.** The function gives the rule one text. It does not give the rule one owner: each caller decides again, and a new case that goes into one caller does not reach the other. Ask these questions in order. The first answer that fits gives the place for the rule.

| Question | Answer | Where the rule goes |
|---|---|---|
| Do both callers need it for the same reason? | No | One private method on each type, with a name that says why that type needs it. This includes glue: the same few lines over one dependency, in two services that can change apart. |
| Does it hold a rule of the domain? | No | A type that names the value the callers pass: `QuantityLimit.Apply()`, `Money.String()`. A function that fits no concept of the domain goes in a package of functions. Name that package after what its functions do, not `util`. |
| Does one type already make the decision? | Yes | That type returns the decision, or its event carries the decision. The other type reads the decision and holds no copy of the rule. |
| Is every input a field of one type? | Yes | A method on that type: `Customer.IsLoyal()`, `Rules.WithLLMText()`. |
| Does the rule change for reasons that no caller owns? | Yes | A new type that owns the rule, named after the concept: `ContactHours.Allow()`. Both callers receive it in their constructors. |

- Two copies of one text are correct when they are two pieces of knowledge. A shared function couples the two types, and the first change that makes them differ must take the coupling apart again.
- When one type starts to read the decision of the other, behaviour can change. Where the two copies of the rule disagreed, the second type now follows the first. Find those cases, and check each one with the person who owns the result.

### 9. An Aggregate Takes Commands, Not Questions
- Every exported method on an aggregate takes a command, checks the invariants and returns the events. No exported method answers a question about the aggregate's state: no `HasX()`, no `IsX()`, no `View()`.
- A caller that needs the state to decide something holds a rule that belongs in the command. A caller that needs the state to show or report something reads a projection.
- A private method that the commands share is fine.
- The full rule, with where each kind of question goes: `architecture/design/domain-modeling.md`, "An Aggregate Takes Commands, Not Questions".

## Application

These principles work together to create:
- **Highly maintainable code** - Easy to understand and modify
- **Testable components** - Every dependency can be mocked
- **Readable business logic** - Code expresses domain concepts naturally
- **Flexible architecture** - Easy to swap implementations
