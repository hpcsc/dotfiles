# OO Design Heuristics by Language

Companion to `oo-design-heuristics.md`: how Riel's heuristics map onto the languages actually in use, and which of them are **void** in each.

Riel wrote for C++ and Smalltalk in 1996: implementation inheritance, `protected` data, multiple inheritance, class variables. Applying that vocabulary literally to Go or Elixir produces confident nonsense.

## Core Principle

**Fix the paradigm mapping before applying any heuristic.** Establish which chapters are void for the language in front of you, and say so in the review.

**A void heuristic is never a finding.** Say "void for this language" and move on — do not translate it into something Riel didn't say and then flag that.

---

## Go

No inheritance. No `protected`. No classes. Embedding is **containment**, and privacy is per **package**, not per type.

| Riel concept | Go reality |
|---|---|
| Class | `struct` (or named type) plus its method set |
| Private data | lowercase field — but visible to *everything in the package* |
| Public interface | exported methods, plus promoted methods from embedded types |
| Inheritance | **absent**. Embedding is containment with method promotion |
| Abstract base class | interface — idiomatically defined by the *consumer*, not the provider |
| Protected data | **void** |
| Multiple inheritance | multiple embedded structs with overlapping method sets |
| Class variables | package-level `var` — treat as global (8.1) |

### Re-targeting Chapter 5

Most of Chapter 5 is void. What survives, and where it lands:

- **5.1** — embedding to reuse code is *containment*, and correct. It only becomes a finding when the embedded type is presented as an is-a: an exported embedded field whose whole surface is promoted into the public interface. Then it isn't 5.1, it's **2.3 / 2.5 / 2.6** — you published someone else's protocol as your own. Check what the promotion actually exports.

  But 5.1's **substitution test survives in full**, retargeted from subclasses to *interface implementations*. For each type satisfying an interface, compare its contract to what callers of the interface assume: an implementation that panics on inputs its siblings accept, requires extra setup before its methods are legal, returns an error where the interface implies success, or ignores the `context` others honour has narrowed a precondition or widened a postcondition. Go's compiler checks the method set and nothing about the contract, so this is review-only — exactly Riel's "design-level problem, no compiler error".
- **5.2** — parent knowing child appears as a type switch inside the "base" over its own implementations, or an interface in the provider package enumerating its implementers.
- **5.3** — void. Nearest analogue: exported fields on a type designed for embedding. File under **2.1**.
- **5.4 / 5.5** — depth means embedding depth. Rare and usually shallow; a real finding when a method's real implementation is several promotions away.
- **5.6 / 5.7** — an interface with one implementation and no second in sight is a finding *against* the code. Go's rule beats Riel's here: accept interfaces, return structs, and let the consumer declare the interface it needs.
- **5.12** — `switch v.(type)`. A single exhaustive switch at a boundary is idiomatic Go, not a defect. The finding is the *same* switch duplicated across several files.
- **5.13** — `switch order.Status` repeated across methods.
- **5.17** — a method satisfying an interface with `return nil` / empty body because the type can't really do it.
- **6.1 / 6.3** — two embedded structs whose method sets collide (the compiler forces disambiguation), or two embedded types that themselves embed a common type.

### Go-specific checks worth running

- **2.7** is the sharpest heuristic in Go, because the compiler won't help: within one package, any type can touch any other type's unexported fields. Look for a second type mutating the first's fields directly instead of calling a method.
- **2.9 / 3.3** — the anemic-struct-plus-service-struct pair is the dominant Go shape. Ask whether the `Service` holds rules that belong on the domain type. Often the answer is legitimately no (it needs a repo, a client, a clock) — check before flagging.
- **4.13** — `parent *Foo` back-pointers.
- **8.1** — package-level `var` registries, counters, caches, `init()` side effects.
- **9.1** — structs shaped by `db` / `json` tags standing in as domain types.

Use gopls for identity, not `rg`: `mcp__gopls__go_symbol_references` for callers, `LSP hover` / `goToDefinition` for types. If those tools aren't registered for the repo, use the `gopls` CLI (`gopls references <file>:<line>:<col>`). `ast-grep -p '…' --lang=go` for shape.

---

## Elixir

Not object-oriented. No classes, no inheritance, no mutable state. Chapters 5, 6, and most of 2 are void **as written** — but the underlying design questions survive, relocated to modules, structs, behaviours, and processes.

| Riel concept | Elixir reality |
|---|---|
| Class | module + its struct |
| Encapsulation unit | the **module**, not the struct — struct fields are always readable |
| Public interface | public functions; `@doc false` / private functions are the boundary |
| Inheritance | **absent**. `use` + `__using__` is the closest, and it's code injection |
| Abstract base class | `@behaviour` / `@callback`, or a protocol |
| Polymorphism | protocols, and pattern matching on struct type |
| Class variables | Agent / ETS / `:persistent_term` — treat as global (8.1) |

### What still applies, and how

- **2.1** — void as written. The real check: does code outside the owning module pattern-match on that module's struct internals, or reach into a nested field it shouldn't know about? That's the Elixir form of breaking encapsulation, and it's **2.7**.
- **2.8 / 2.9** — the strongest surviving heuristics. Does the module that defines `%Order{}` also own the functions that make decisions about orders, or do those live in a context module three directories away while `Order` is a bare `defstruct`? The cohesion matrix works fine: rows = public functions, columns = struct fields they match on or touch.
- **3.2** — a context module with 40 public functions is the Elixir god class. Same evidence: matrix blocks, unrelated change drivers.
- **3.5** — `Phoenix` controllers/views depending on contexts, never the reverse.
- **5.x** — re-target to `use`. `use Foo` injects code the caller doesn't see, which is white-box reuse — exactly what 5.1 warns about. Check: does `__using__` inject state or functions the user is expected to override? Does the macro's module know its users (**5.2**)? Prefer a behaviour (contract) or a plain function (containment) over a `use` macro whenever the macro exists only to share code.
- **5.1's substitution test** applies to `@behaviour` implementations and `defimpl` blocks: every implementation must accept what callers of the behaviour may pass and return what they may match on. An implementation that raises on a clause its siblings handle, or returns a bare value where callers match `{:ok, _}`, has failed it. Dialyzer catches some of this; the contract questions it can't see are the ones worth reviewing.
- **5.11 / 5.12** — protocols are the polymorphism. `case` on `%Struct{}` scattered across modules is the finding; one `defimpl` per type is the fix. As in Go, a single exhaustive `case` at a boundary is idiomatic.
- **4.11 / 4.12** — volatile constraint data in one config/policy module; stable rules inside the structs they constrain.
- **8.1** — Agent/ETS/`:persistent_term` used as bookkeeping over "instances". Ask whether it should be a process that *owns* the data instead of a global others read.
- **9.1** — Ecto schemas used directly as domain types, so a migration reshapes the domain.

**Void in Elixir**: 5.3, 5.4, 5.5, 5.6, 5.7, 5.15, 5.18, 6.1, 6.2, 6.3, 7.1.

---

## TypeScript / JavaScript

The closest living relative of Riel's model. Most heuristics apply literally.

| Riel concept | TS/JS reality |
|---|---|
| Private data | `#field` (real), `private` (compile-time only), `_field` (convention only) |
| Abstract base class | `abstract class`, or an `interface` / structural type |
| Multiple inheritance | mixins (`class X extends Mixin(Base)`) |
| Class variables | `static` members, or module-scope `let` (8.1) |

- **2.1** — `private` is erased at runtime and `_` is a naming convention; both are violated in practice. Check for external `obj._thing` access, and prefer `#` for anything that matters.
- **5.12** — `instanceof` chains and `switch (x.kind)` on discriminated unions. A single exhaustive switch with a `never` default is the idiom, not a defect; the same switch in five files is 5.12.
- **6.1 / 6.3** — mixin chains. Check whether two mixins bring the same base, and whether either really answers 6.2's first question.
- **5.15** — a subclass per config value; common in error hierarchies. One error class with a code is often right.
- **3.9** — a class with one method and a constructor that only stores its arguments is a function. This is the most common finding in TS codebases.
- **8.1** — module-scope mutable state used as a registry or cache.

**React and component frameworks**: map a component to a class — props are constructor arguments, state is private data, the render output is its public interface.
- **2.8** — a component doing data fetching, business rules, and layout is three abstractions.
- **3.5** — a component holding domain rules inverts the model/interface dependency; the rules belong outside the component tree.
- **2.9** — prop-drilling a value through four components that don't use it is data separated from its behaviour.
- **4.7** — a props object with fifteen fields.
- Do **not** flag hooks-vs-classes; that's framework style, not OO design.

---

## Python

Applies nearly literally; the conventions are weaker.

| Riel concept | Python reality |
|---|---|
| Private data | `_name` (convention), `__name` (name-mangled) |
| Protected data | `_name` — so **5.3 does apply**, by convention |
| Abstract base class | `abc.ABC` / `Protocol` |
| Multiple inheritance | real, with MRO — **Chapter 6 applies in full** |
| Class variables | class attributes; genuine support for 8.1's remedy |

- **3.3** — `@property` everywhere is the accessor signal.
- **2.9** — a `@dataclass` with no methods plus a `*Service` holding all the rules.
- **5.12** — `isinstance` chains.
- **6.1 / 6.3** — mixins and diamonds are common; MRO makes accidental multiple inheritance (6.3) a real and subtle defect.
- **9.1** — ORM models (Django/SQLAlchemy) doubling as domain types.

---

## When the paradigm doesn't apply at all

Say so and stop. Do not force the heuristics onto:

- **Pure functional modules** — data and transformations are separated *by design*. 2.9 does not apply.
- **DTOs, wire formats, event payloads, config structs** — public, behaviourless data is correct. 2.1, 2.9, 3.3, 4.6, 4.7, 9.2 do not apply.
- **Generated code** — protobuf, ORM models, OpenAPI clients, codegen output.
- **Vendored and third-party code.**
- **Test fixtures and builders** — deliberately anemic and deliberately wide.
- **Scripts and one-shot tooling** — the design cost never comes due.

If the target is mostly one of these, say that in the verdict rather than producing findings against code that is shaped correctly for its job.
