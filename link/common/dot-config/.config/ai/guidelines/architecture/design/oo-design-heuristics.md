# Object-Oriented Design Heuristics

This document is the working catalogue of Arthur J. Riel's 61 design heuristics (*Object-Oriented Design Heuristics*, Addison-Wesley 1996) — each with what triggers a look, how to check it, what the fix is, and, most importantly, when it is **not** a finding.

Use it when grading *abstractions*: whether each type captures one key abstraction, whether data sits with the behaviour that uses it, how intelligence is distributed across peers, and whether a relationship should be containment, association, or inheritance.

**Companion documents**

- `oo-heuristics-by-language.md` — how these heuristics map onto Go, Elixir, TypeScript, and Python, and which chapters are void in each. Read it first.
- `domain-modeling.md` — aggregate boundaries and bounded contexts. That operates a level above this one: it decides which contexts exist, this decides the abstractions inside them.

The `review-oo-design` skill drives this catalogue as a review workflow.

## Core Principle

**A heuristic is a warning mechanism, not a rule.** Riel: they "are not written as hard and fast rules; they are meant to serve as warning mechanisms which allow the flexibility of ignoring the heuristic as necessary."

A triggered heuristic is a prompt to read the code. The finding is what you find when you read it.

## How to use this

Riel: the heuristics "are not written as hard and fast rules; they are meant to serve as warning mechanisms which allow the flexibility of ignoring the heuristic as necessary."

So:

1. A triggered heuristic is a **prompt to read the code**. The finding is what you find.
2. Work the **Not a finding when** line before writing anything down. Most candidates die there.
3. Check `oo-heuristics-by-language.md` first — a heuristic that is void for the language is never a finding.
4. When two heuristics point opposite ways, see **Conflicts and their resolution** at the end. Never quote one side of a known tension as if it were settled.
5. A heuristic with no demonstrable cost is not a finding, however clearly it is violated.

---

## The cohesion matrix

The central analytical technique behind this catalogue. It operationalises heuristics 2.8, 2.9, 2.10, 3.3, 3.4, and 4.6 at once, and turns "this class feels like it does too much" into evidence you can put in front of someone.

Build it for any type with more than about four fields. Rows are methods, columns are fields, and a cell is marked when the method reads or writes that field. Tools gather the method list; you read the bodies.

```
              cfg  conn  cache  retries  logger
Fetch(...)     ●    ●      ●       ●        ●
Invalidate()   ·    ·      ●       ·        ·
Purge()        ·    ·      ●       ·        ·
Reconnect()    ●    ●      ·       ●        ●
Name()         ●    ·      ·       ·        ·
```

Read it for four things:

- **Disjoint blocks** — two groups of methods over two non-overlapping field sets is one type wearing two names (2.8, 2.10, 3.4). Above, `{Invalidate, Purge}` × `{cache}` never meets the connection cluster.
- **All-zero rows** — a method touching no field is not a method; it is a function that ended up here (2.9, 3.9).
- **Single-method columns** — a field only one method touches wants to move with that method.
- **Accessor rows** — a row touching exactly one field with no logic is a getter or setter. If accessors exceed roughly half the public surface, behaviour belonging to this type is living in its callers (3.3, 2.9).

Two cautions. The matrix measures *structural* cohesion only — methods can touch the same fields for unrelated reasons, so confirm a split candidate against change drivers (who or what makes each part change) before acting on it. And it says nothing useful about types whose job is to carry data: DTOs, wire formats, and config structs are supposed to look incohesive.

The matrix is evidence, not a working note. Put it in the review.

---

## Chapter 2 — Classes and Objects: the building blocks

### 2.1 — "All data should be hidden within its class."

- **Smell**: exported/public fields; direct field access from outside the type.
- **Check**: read the struct/class declaration for public fields, then find external writes. In Go, note that privacy is per *package*, so the real question is who outside the package can reach it — and, separately, who inside the package reaches past the type's methods.
- **Fix**: make the field private and expose an operation that expresses the *intent*, not the field. If every field needs a setter, the behaviour belongs on this type, not its callers (see 2.9).
- **Not a finding when**: the type is a DTO, wire format, config struct, or event payload — its whole job is to be public data. Also void where the language has no field privacy (Elixir structs); there the unit of encapsulation is the module (see `oo-heuristics-by-language.md`).

### 2.2 — "Users of a class must be dependent on its public interface, but a class should not be dependent on its users."

- **Smell**: a back-reference — the callee imports the caller, holds a pointer to it, or calls back into it by concrete type.
- **Check**: for each type, list its outbound dependencies and ask whether any of them is a consumer of this type. Import cycles and near-cycles are the loud version; a `parent *Owner` field is the quiet one.
- **Fix**: invert with a callback, an event, or an interface *defined by this type* describing only what it needs.
- **Not a finding when**: the "user" is a framework the type is deliberately written against (an HTTP handler depending on the router's types). Depending on a stable published contract is not depending on a user.

### 2.3 — "Minimize the number of messages in the protocol of a class."

- **Smell**: a public method count well above sibling types in the same codebase.
- **Check**: count public methods; then check how many are used by *any* external caller.
- **Check — the facade that hides nothing.** A container whose public interface republishes every primitive operation of its contained objects (`open_netcard`, `query_netcard`, `reset_netcard`, `open_file_fs`, `close_file_fs`, …) has added a level without adding an abstraction. A real facade **raises the level of abstraction**: `init_netcard`, `check_status_fs`, `net_sync_clock` — the operations the outside world actually wants, with the primitives hidden. Republishing everything is a god class forming, not a facade.
- **Fix**: collapse variants into one method with an option; delete unused exports; move methods that belong to another abstraction (the cohesion matrix shows which); replace forwarded primitives with the higher-level operations callers really need.
- **Not a finding when**: the type is a genuine facade over a large domain and each method is used, at a level of abstraction above what it contains. Compare to siblings, never to an absolute.

### 2.4 — "Implement a minimal public interface which all classes understand (e.g. copy (deep versus shallow), equality testing, pretty printing, parsing from an ASCII description)."

- **Smell**: a domain type with no equality, no string form, no clone, so callers hand-roll comparison and formatting — usually inconsistently.
- **Check**: search for external code comparing the type field-by-field, or formatting it inline. Duplicated comparison logic is the tell.
- **Fix**: implement the language's universal protocol — `String()`/`Equal()` in Go, `toString`/`equals` in TS, `Inspect`/`String.Chars` in Elixir, `__eq__`/`__repr__` in Python.
- **Not a finding when**: the language already derives it (Elixir structs compare structurally; Go comparable structs use `==`), or the type is deliberately non-comparable because equality is ambiguous.
- **Tension**: adds messages that 2.3 and 2.6 want removed. See the resolution table.

### 2.5 — "Do not put implementation details such as common-code private functions into the public interface of a class."

- **Smell**: exported helpers whose names describe *how* rather than *what* — `BuildQuery`, `NormalizeInternal`, `Step2`.
- **Check**: for each exported method, find external callers. No external caller, or callers who only use it as part of a fixed sequence, means it isn't interface.
- **Fix**: unexport it, or fold the sequence into one operation the caller actually wants.
- **Not a finding when**: it is genuinely a second entry point for a real second use case — verify by finding that caller.

### 2.6 — "Do not clutter the public interface of a class with things that users of that class are not able to use or are not interested in using."

- **Smell**: exported symbols requiring setup callers can't perform, or exposing lifecycle the owner controls (`Reset`, `SetState`, `Internal*`).
- **Check**: the dead-export scan; then read the surviving callers.
- **Fix**: remove or unexport. If tests are the only caller, that's a test-design problem, not a reason to export.
- **Not a finding when**: it is a documented extension point with a real second implementer.

### 2.7 — "Classes should only exhibit nil or export coupling with other classes, i.e. a class should only use operations in the public interface of another class or have nothing to do with that class."

- **Smell**: reaching past another type's interface — touching its private fields, depending on its storage shape, scraping its output, reading its table.
- **Check**: in Go, same-package access to another type's unexported fields is the main case and the compiler won't stop you. In TS/Python, look for `_`-prefixed access from outside. Elsewhere, look for a second type that mutates the first's fields directly.
- **Fix**: add the operation to the owning type and call it. If the caller needs a value the owner can compute, ask the owner.
- **Not a finding when**: the two types are one abstraction split across files for size — in which case the finding is that they should be one type (2.8), not that the coupling is wrong.

### 2.8 — "A class should capture one and only one key abstraction."

The most load-bearing heuristic in the catalogue.

- **Smell**: a responsibility sentence that needs "and"; disjoint blocks in the cohesion matrix; a type that changes for two unrelated reasons.
- **Check**: build the method×field matrix. Two method groups over non-overlapping field sets is the proof. Corroborate with change drivers: who or what makes each part change?
- **Fix**: split along the matrix blocks. Name each new type after the abstraction, not after the layer.
- **Not a finding when**: the blocks share a genuine invariant that would have to be maintained across the split — splitting would move a rule out of the object that enforces it (see 4.10). Say so and leave it.

### 2.9 — "Keep related data and behavior in one place."

- **Smell**: an anemic type (fields, accessors, no decisions) plus a separate type full of functions that operate on it.
- **Check**: for each type with a high accessor ratio, find who consumes the accessors. If a caller reads three fields and computes something the type could have computed, the behaviour is displaced.
- **Fix**: move the computation onto the type that owns the data. This usually deletes accessors — the strongest signal that it was right.
- **Not a finding when**: the type is a DTO/wire/config shape, or the behaviour genuinely needs collaborators the data type shouldn't know about (a persistence concern, an external service). Then the behaviour belongs to a separate abstraction by design.

### 2.10 — "Spin off non-related information into another class (i.e. non-communicating behavior)."

The remedy half of 2.8/3.4 — same evidence, same matrix. Record it as the fix, not a separate finding.

### 2.11 — "Be sure the abstractions you model are classes and not simply the roles objects play."

- **Smell**: `Sender`/`Recipient`, `Buyer`/`Seller`, `Mother`/`Father` as distinct types whose fields and methods are near-identical.
- **Check**: diff the two types' fields and methods. If they differ only in name, they are one class in two roles. If they carry genuinely different *behaviour*, they are distinct classes.
- **Fix**: one type, with the role expressed by position in a relationship (a `Transfer` has a `from Party` and a `to Party`) or by a role value.
- **Not a finding when**: the domain gives the roles distinct rules — a `Buyer` that can bid and a `Seller` that can set reserve are two abstractions. Riel: "No magic answer: depends on the domain."

---

## Chapter 3 — Topologies of action-oriented vs object-oriented applications

### The chapter's real subject: superficially object-oriented code

A codebase can be composed entirely of classes and still have the topology of an action-oriented program. Being made of objects is not the same as being object-oriented, and this chapter's heuristics exist to catch the difference. Check for the action-oriented signature before grading 3.1–3.4 individually:

- **Centralized control** — one procedure or type is "in command" of the flow, and every significant event passes through it.
- **A single main sequence** — adding a capability means editing that one place, because it owns the ordering.
- **Uncontrolled data sharing** — lower-level code reads and writes shared structures with no owner enforcing anything.

Translated into a class diagram, this looks like a `MainSystem` object containing a `Database`, a `UserScreen`, and a couple of `Connector` objects, where the contained types have two or three primitive operations each and `MainSystem.processRequest()` is still enormous. Every box is a class; nothing has been distributed.

The cost is **accidental complexity** — complexity coming from the structure of the implementation rather than the structure of the problem. It compounds: each new feature is added to the central place, which makes the central place harder to add the next feature to. That compounding *is* the concrete cost to cite in a finding.

### 3.1 — "Distribute system intelligence horizontally as uniformly as possible, i.e. the top level classes in a design should share the work uniformly."

- **Smell**: one top-level type holding the whole plot while its peers are data bags.
- **Check**: compare method counts and, better, *decision* counts (branches, rules) across peer types at the same level.
- **Fix**: push each decision to the type that owns the data it decides on.
- **Not a finding when**: the type is a deliberate orchestrator with one job — sequencing — and holds no rules of its own. Coordination is a legitimate single responsibility.

### 3.2 — "Do not create god classes/objects in your system. Be very suspicious of an abstraction whose name contains Driver, Manager, System, or Subsystem."

- **Smell**: the name — plus size, breadth of collaborators, and a scattered matrix.
- **Check**: the name is only the prompt. The evidence is the cohesion matrix (3.4), the accessor ratio around it (3.3), and how many other types it reaches into.
- **Fix**: redistribute behaviour to the types owning the data; what remains is usually a thin coordinator or nothing.
- **Not a finding when**: the type is cohesive despite the name. Then the most you have is a naming note, and only if the repo's conventions support renaming.

### 3.3 — "Beware of classes that have many accessor methods defined in their public interface, many of them imply that related data and behavior are not being kept in one place."

- **Smell**: accessor ratio over roughly half the public surface. Sharper still: one caller pulling *several* getters off the same object in a row, then computing something from them.
- **Check — the diagnostic question.** When class A calls several get/set functions on class B, ask: **"What am I doing with the information I am getting from B, and why doesn't B do it for me?"** If A is making a decision that only needs B's own data, the decision belongs on B. In Riel's home-heating example, `HeatFlowRegulator` calls `getDesiredTemp()`, `getActualTemp()`, and `getOccupancy()` and then decides — replacing all three with `Room.needsHeat()` moves the decision to the data, shrinks the caller, and stops it depending on how `Room` stores anything.
- **Fix**: move the deciding logic onto the type; delete the accessors it made redundant. Deleted accessors are the proof it was right.
- **Not a finding when**: the type is a read model, query result, or view model whose purpose is to be read; or when the decision genuinely needs data from several objects, none of which can own it alone.

### 3.4 — "Beware of classes which have too much non-communicating behavior, i.e. methods which operate on a proper subset of the data members of a class. God classes often exhibit lots of non-communicating behavior."

The matrix heuristic. Evidence: disjoint blocks. Fix: split (2.10). Not a finding when a small number of methods sit outside the main block and moving them would be churn — note it and move on.

### 3.5 — "In applications which consist of an object-oriented model interacting with a user interface, the model should never be dependent on the interface. The interface should be dependent on the model."

- **Smell**: domain types importing UI, HTTP, CLI, template, or presentation packages; domain types carrying display concerns (`DisplayName`, `CSSClass`, `Column`).
- **Check**: read the domain package's imports. Generalise beyond UI: the model must not depend on *any* delivery or infrastructure mechanism.
- **Fix**: invert. Presentation reads the model; the model knows nothing about it. Riel's test: could you add a second UI without touching the model?
- **Not a finding when**: the "model" is explicitly a view model — a type built for one interface.

### 3.6 — "Model the real world whenever possible. (Often violated for reasons of system intelligence distribution, avoidance of god classes, and keeping related data and behavior in one place.)"

- **Smell**: types with no counterpart in how domain experts talk — `DataHolder`, `InfoObject`, `Item2`.
- **Check**: read the names against the domain's own vocabulary. Would a domain expert recognise this diagram?
- **Fix**: rename to domain language, or restructure so a domain concept becomes a type.
- **Not a finding when**: fidelity was deliberately traded away to avoid a god class or to keep data with behaviour. Riel builds this exception into the heuristic — cite it rather than pushing back.

### 3.7 — "Eliminate irrelevant classes from your design."
### 3.8 — "Eliminate classes that are outside the system."

- **Smell**: a type nothing constructs, or one representing an actor the system never asks to do anything (a `Customer` type in a system that only ever stores a customer ID).
- **Check**: find constructions and external references. Zero live callers → dead abstraction.
- **Fix**: delete. In design mode, cut before writing.
- **Not a finding when**: it's a published API surface, a planned near-term extension point with a named consumer, or a test fixture.

### 3.9 — "Do not turn an operation into a class. Be suspicious of any class whose name is a verb or derived from a verb. Especially those which have only one piece of meaningful behavior (do not count sets, gets, and prints). Ask if that behavior needs to be migrated to some existing or undiscovered class."

- **Smell**: `OrderValidator`, `PriceCalculator`, `ReportGenerator` with one real method and no state, or state that is just its arguments held as fields.
- **Check**: count meaningful methods excluding accessors. One, with fields that are only the arguments, means it's a function.
- **Fix**: migrate the behaviour to the type that owns the data it operates on — usually the one it takes as an argument. If it genuinely belongs to no existing type, Riel's "undiscovered class" is the interesting answer: the missing abstraction.
- **Not a finding when**: it is a deliberate strategy/policy object with multiple implementations selected polymorphically (that's 5.11 satisfied), or it holds real configuration reused across calls.

### 3.10 — "Agent classes are often placed in the analysis model of an application. During design time, many agents are found to be irrelevant and should be removed."

- **Smell**: a type whose every method forwards to another, adding no decision, rule, or translation.
- **Check**: read each method body. Pure delegation with no transformation.
- **Fix**: delete it; let callers talk to the real collaborator.
- **Not a finding when**: it is an anti-corruption layer, an interface adapter, or a stable seam deliberately isolating a volatile dependency. Translation is not forwarding.

---

## Chapter 4 — Relationships between classes and objects

### 4.1 — "Minimize the number of classes with which another class collaborates."
### 4.2 — "Minimize the number of message sends between a class and its collaborator."
### 4.3 — "Minimize the amount of collaboration between a class and its collaborator, i.e. the number of different messages sent."
### 4.4 — "Minimize fanout in a class, i.e. the product of the number of messages defined by the class and the messages they send."

One family. Measure per type: distinct collaborators, total sends, distinct messages per collaborator, and their product.

**4.1 is the most important of the four** — Riel's point is that the main driver of a class's complexity is *the number of other classes it needs to use*. Rank findings accordingly. Riel also warns it is "silly to set absolute limits for each of these metrics"; these are judgment aids, not thresholds.

- **Check**: use call-site tooling (`gopls references`, `ast-grep` for `$RECV.$METHOD($$$)`), then read the widest edge.
- **Fix**: raise the abstraction level of the conversation — one method saying what you want instead of six saying how. Or move the caller's logic to the collaborator, so the conversation becomes one message. Or aggregate several collaborators into one contained object (see 4.5 and the facade note under 2.3), turning three `uses` edges into one.
- **These heuristics are violated in three different directions**, and the fix differs:
  1. **Mega-classes** with many unrelated responsibilities → split (2.8).
  2. **A behavioural god class** that makes other classes abdicate their decisions → redistribute (3.1, 3.3).
  3. **A class broken up too far**, so its algorithms continually request information back from other objects → **merge**. This is the over-decomposition failure; see "The balance check" below.
- **Not a finding when**: the chattiness stays inside one package where coordinating a change is cheap. Riel's counter-example is the Visitor pattern, which deliberately maximises distinct messages to buy extensibility; deliberate patterns are exempt. Chatty interaction becomes a finding when it crosses an expensive boundary — a process, a service, a team.

### 4.5 — "If a class contains objects of another class then the containing class should be sending messages to the contained objects, i.e. the containment relationship should always imply a uses relationship."

- **Smell**: a field the owning type never sends a message to — it only stores and hands out.
- **Check**: in the matrix, a field column touched only by a getter.
- **Fix**: either the owner should be doing something with it (move that behaviour in), or it isn't containment — it's data passing through, and belongs in the signature that needs it.
- **Not a finding when**: the type is a composition root or a container by design.

### 4.6 — "Most of the methods defined on a class should be using most of the data members most of the time."

The cohesion criterion behind the matrix. Same evidence and fix as 2.8/3.4. Report through those; don't file it twice.

### 4.7 — "Classes should not contain more objects than a developer can fit in his or her short term memory. A favorite value for this number is six."

- **Smell**: more than ~6 fields.
- **Check**: count, then look at the matrix — the count only matters if the fields don't cohere.
- **Fix — add a level to the containment hierarchy.** Group related fields into contained value types rather than splitting the owning class. A `LogMsg` holding `Time, Date, Port, Link, Dest, Code, Text, Prio` (eight) becomes a `LogMsg` holding `MsgTime{Time, Date}`, `MsgLocation{Port, Link, Dest}`, `MsgReason{Code, Text, Prio}` (three). The owner is still one abstraction; it now converses with three coherent parts instead of eight loose fields. This is 4.8's "narrow and deep" in practice.
- **Not a finding when**: the type is a config or DTO, or the fields are genuinely one cohesive block. The number is a prompt, never the finding.

### 4.8 — "Distribute system intelligence vertically down narrow and deep containment hierarchies."

- **Smell**: one type owning fifteen things directly, each of which owns nothing — a flat, wide tree.
- **Check**: sketch the containment tree. Wide-and-shallow means intelligence pooled at the top (see 3.1).
- **Fix**: introduce intermediate abstractions that own a coherent subset and answer questions about it, so the parent asks one question instead of ten.
- **Not a finding when**: depth would add pass-through layers that make no decisions. Narrow *and* deep — depth without decisions is worse than width.

### 4.9 — "When implementing semantic constraints, it is best to implement them in terms of the class definition. Often this will lead to a proliferation of classes in which case the constraint must be implemented in the behavior of the class, usually, but not necessarily, in the constructor."

- **Smell**: a rule enforced by convention, by callers, or by a validation pass that runs "later".
- **Check**: can an invalid instance exist? Find a construction path that produces one.
- **Fix**: first choice — make the illegal state unrepresentable in the type. When that would explode into a class per combination, enforce in the constructor and make it the only way in.
- **Not a finding when**: the invalid state is legitimately representable at a boundary (parsing untrusted input) and is refused at the point it becomes a domain object.

### 4.10 — "When implementing semantic constraints in the constructor of a class, place the constraint test in the constructor as far down a containment hierarchy as the domain allows."

- **Smell**: an aggregate validating its parts' internals; the same check repeated at several levels.
- **Check**: find the type that *owns* the data the rule constrains. Is the check there, or above it?
- **Fix**: push the check down to the owner, so it cannot be constructed wrong and nobody above needs to check.
- **Not a finding when**: the rule is genuinely about a *combination* the lower type can't see. Then it belongs at the level that can see all of it — that is "as far down as the domain allows".

### 4.11 — "The semantic information on which a constraint is based is best placed in a central third-party object when that information is volatile."
### 4.12 — "…best decentralized among the classes involved in the constraint when that information is stable."

A pair. Decide by volatility, judged from the business domain, not from commit history.

- **Check**: how often does the *rule's data* change, and does changing it require a code change in many places? Volatile-and-scattered is the finding; volatile-and-central and stable-and-scattered are both correct.
- **Fix**: volatile → one table/policy object everyone consults. Stable → let each class own its own part; a central table for a rule that never changes is indirection with no payoff.
- **Not a finding when**: you're guessing about volatility. If it changes the verdict and you can't tell, ask the user one grounded, multiple-choice question.

### 4.13 — "A class must know what it contains, but it should never know who contains it."

- **Smell**: a `parent`/`owner` back-pointer; a child calling up into its container.
- **Check**: scan for parent fields; then check whether the child calls back or only stores it.
- **Fix**: pass what the child needs as an argument, return a result and let the parent act, or raise an event.
- **Not a finding when**: the structure is intrinsically bidirectional (a doubly-linked node, a tree needing upward traversal as its purpose). Then the back-reference *is* the abstraction.

### 4.14 — "Objects which share lexical scope — those contained in the same containing class — should not have uses relationships between them."

- **Smell**: sibling fields of the same owner calling each other directly.
- **Check**: within a type, look for one field being passed to, or invoked by, another.
- **Fix**: let the owner mediate — it is the only one that knows both. Or admit the two are one abstraction and merge them.
- **Not a finding when**: the owner is a composition root wiring collaborators, which is precisely its job.

---

## Chapter 5 — The inheritance relationship

Read `oo-heuristics-by-language.md` first. Most of this chapter is **void in Go** (no inheritance) and **void in Elixir** (no classes); the mapping file says what replaces it.

### 5.1 — "Inheritance should only be used to model a specialization hierarchy."

The most important heuristic in the chapter. **5.1 is the Liskov Substitution Principle**: wherever the base type is expected, an instance of the derived type must work without the caller knowing. Derived types may add behaviour, but must deliver the *full set* of base behaviours.

- **Smell**: inheriting to reuse code, to share a helper, or to get fields.
- **Check — the substitution test.** For every method the subtype redefines, compare the contract:

  | | Allowed direction | Meaning |
  |---|---|---|
  | **Preconditions** | only **weaker** (wider, more permissive) | the subtype must accept everything the base accepted |
  | **Postconditions** | only **stronger** (narrower, more restrictive) | the subtype must promise everything the base promised |

  Riel's compression: each subtype method **"expects no more, delivers no less."** A subtype that narrows a precondition (a `SkateboardDeliveryPerson` that only accepts packages under 5 lb and destinations within 3 miles) breaks callers written against the base. A subtype that widens a postcondition (an `alert()` that leaves the volume raised when the base promised to restore it) breaks them more quietly.

  Preconditions and postconditions unchanged is also fine — that's the common case for a legitimate subtype.

- **Check — has-a wearing is-a.** The most common violation: `CustomerOrder extends Customer` because an order *has* a customer. Apply 6.2's two questions. Note there is **no compiler error** for this; it is purely a design-level defect, so nothing but review will catch it.
- **Fix**: containment. Inheritance is white-box (the subclass sees the parent's decisions); containment is black-box. Reuse is a containment reason, not an inheritance reason.
- **Not a finding when** the inheritance is one of the four legitimate uses:
  1. **A design pattern** that uses inheritance as its mechanism (Strategy, Observer, Template Method, Visitor).
  2. **A framework's extension contract** — the framework calls back into your subclass (`Thread`/`Runnable`, a lifecycle hook, an abstract handler).
  3. **Commonality analysis** — an abstract interface factored out of several genuinely related classes.
  4. **Extending a concrete class** with real added behaviour, where substitution still holds.

  In all four, still run the substitution test. A legitimate *reason* to inherit does not excuse a broken is-a.

### 5.2 — "Derived classes must have knowledge of their base class by definition, but base classes should not know anything about their derived classes."

- **Smell**: a base that switches on which subclass it is, enumerates its subclasses, or documents "override this if you are a Foo".
- **Check**: search the base for references to derived type names.
- **Fix**: replace the base's knowledge with an abstract operation each derived type answers for itself.
- **Not a finding when**: the hierarchy is a deliberately sealed sum type where the base *is* the closed enumeration. Say so explicitly.

### 5.3 — "All data in a base class should be private, i.e. do not use protected data."

- **Smell**: `protected` fields.
- **Check**: read the base's field declarations.
- **Fix**: private fields plus protected *operations*. Protected data makes every subclass a co-owner of the base's representation, so the base can never change it.
- **Not a finding when**: void — the language has no `protected` (Go, Elixir). The nearest Go analogue is exported fields on a type designed for embedding; flag that under 2.1.

### 5.4 — "Theoretically, inheritance hierarchies should be deep, i.e. the deeper the better."
### 5.5 — "Pragmatically, inheritance hierarchies should be no deeper than an average person can keep in their short term memory. A popular value for this depth is six."

Riel states both. **5.5 governs in practice.** 5.4 means "don't flatten a genuine specialization hierarchy just to reduce depth" — never "add levels". Depth over ~6, or any depth where reading a method means visiting several files to find the real implementation, is the finding.

Riel's reasoning (p. 84): "Developers get lost in the levels if the hierarchy is too deep." Two things make deep hierarchies expensive — the semantic distance between objects at the top and bottom of the tree grows large, and lower subclasses accumulate special internal states and rules that the base's interface doesn't hint at. Tooling that shows a class's *complete* interface including inherited operations partly offsets this, so weigh the finding lower where such tooling is in normal use and higher where readers work from the source alone.

### 5.6 — "All abstract classes must be base classes."

- **Smell**: an abstract class or interface nothing implements.
- **Check**: find implementers. Zero → delete or make it concrete.
- **Not a finding when**: it's a published extension point with an external implementer.

### 5.7 — "All base classes should be abstract classes."

Riel himself flags this as **controversial**, and the deck rebuts it: base classes can legitimately provide default behaviour. Treat a concrete class with subclasses as a prompt only. The real question: is the base ever instantiated *as itself*, and does that instance mean anything in the domain? If yes, it's fine. If no, make it abstract.

### 5.8 — "Factor the commonality of data, behavior, and/or interface as high as possible in the inheritance hierarchy."

- **Smell**: the same field or method repeated across siblings.
- **Check**: diff sibling types.
- **Fix**: lift into the common ancestor — but only what *all* descendants need. Lifting something two of five need creates a base that lies about its descendants.
- **Not a finding when**: the duplication is coincidental — same shape, different reason to change. Lifting those couples things that should move independently.

### Choosing the relationship — 5.9 / 5.10 / 5.11

Not three separate checks; one decision table. Use it in review to see whether the existing choice was right, and in design mode to make it.

| What the types share | Choose | Heuristic |
|---|---|---|
| Data only, no common behaviour | A class holding that data, **contained** by each sharer | 5.9 |
| Data **and** behaviour | A common **base class** capturing both | 5.10 |
| Interface only (messages, not methods), **and** used polymorphically | A common **base class / interface** | 5.11 |
| Interface only, **not** used polymorphically | **Nothing.** Coincidence, not commonality | 5.11 |
| Given a free choice between containment and association | **Containment** | 7.1 |

Then apply Riel's two questions (6.2) before committing to inheritance:
1. *Am I a special type of the thing I'm inheriting from?* — no ⇒ not inheritance.
2. *Is the thing I'm inheriting from part of me?* — yes ⇒ containment, not inheritance.

### 5.12 — "Explicit case analysis on the type of an object is usually an error; the designer should use polymorphism in most of these cases."

- **Smell**: `switch v.(type)`, `instanceof` chains, `isinstance` chains, checking a `kind`/`type` field.
- **Check**: how many places switch on the *same* set? One switch is a boundary; the same switch in five places is a missing polymorphic method — adding a case means editing all five, and one will be forgotten.
- **Fix**: move each branch's body onto the corresponding type behind a common operation.
- **Not a finding when**: a single, exhaustive switch at a boundary (deserialization, an error taxonomy, a visitor) where the compiler or a test enforces exhaustiveness. That's the idiom, especially in Go.

### 5.13 — "Explicit case analysis on the value of an attribute is often an error. The class should be decomposed into an inheritance hierarchy where each value of the attribute is transformed into a derived class."

- **Smell**: methods that all begin `if status == "pending" { … } else if status == "shipped" { … }`.
- **Check**: count methods switching on the same attribute. Several is the signal.
- **Fix**: make each value a type with its own behaviour (a state type, a strategy, a variant).
- **Not a finding when**: one method switches once, or the values are genuinely just data (a currency code). Also weigh 5.14 — if the value *changes over an object's lifetime*, do not model it with inheritance; use a contained state object.

### 5.14 — "Do not model the dynamic semantics of a class through the use of the inheritance relationship. An attempt to model dynamic semantics with a static semantic relationship will lead to a toggling of types at runtime."

- **Smell**: an object needing to "become" another type — code constructing a new instance of a sibling type to represent a state change. The canonical case is `Stack` with `EmptyStack` and `NonEmptyStack` subclasses: the object is created empty, and after the first `push` it is supposed to *be* a different class.
- **Rule of thumb**: in most designs, **an object should never change its class**. If it has to, the distinction wasn't a subtype.
- **Check**: does anything a subclass distinguishes change during the object's life? Employee → Manager on promotion is the classic domain version.
- **Fix**: collapse the hierarchy into one class carrying an explicit **state model** — a state field plus the transitions, so the class itself says which operations are legal in which state. Alternatively contain a state/role object and swap *it*. Inheritance is fixed at construction; states and roles are not.
- **Not a finding when**: the distinction genuinely is fixed for the object's lifetime. Riel also allows the **virtual constructor / factory** idiom — a factory reading from a file may build an object with an interim type and transform it once the data section is complete.

### 5.15 — "Do not turn objects of a class into derived classes of the class. Be very suspicious of any derived class for which there is only one instance."

- **Smell**: `UsdCurrency`, `GbpCurrency`, `EurCurrency` as types; a subclass per configuration value; `CarManufacturer` with `GeneralMotors`, `Ford`, `Toyota` subclasses.
- **Check — kind or instance?** Instance count is the prompt; the question is whether the subclass names a *kind of thing* or *one particular thing*. `GradStudent` under `Student` is a kind — fine. `BillGates` under `Student` is an instance wearing a class — not fine. `SelfPacedCourse` under `Course` is a kind; `DesignHeuristicsIntroCourse` is an instance. A subclass named after a specific real-world individual, company, or record is almost always an object.
- **Fix**: one class, instances differing by data. Where the subclasses differed by *behaviour* rather than constants, don't just collapse to data — extract that behaviour into its own hierarchy the class collaborates with. `CarManufacturer` keeps one class and holds an `AccountingMethod`, which is where `GMAccounting` / `FordAccounting` / `ToyotaAccounting` live. That is the Strategy pattern, and it makes both sides reusable.
- **Not a finding when**: each carries genuinely different *behaviour*, not just different constants — or when a framework legitimately needs a singleton subclass.

### 5.16 — "If you think you need to create new classes at runtime, take a step back and realize that what you are trying to create are objects. Now generalize these objects into a class."

- **Smell**: dynamic class generation, metaprogramming that fabricates types, a registry mapping strings to generated types.
- **Fix**: one class, parameterised by data.
- **Not a finding when**: the language's idiom genuinely requires it (an ORM's generated models, a codegen step). Generated code is out of scope.

### 5.17 — "It should be illegal for a derived class to override a base class method with a NOP method, i.e. a method which does nothing."

- **Smell**: an override with an empty body, `pass`, `return nil`, or "not supported here".
- **Check**: read every override for an empty or throwing body.
- **Fix**: the base promised something this type can't deliver — the hierarchy is wrong (5.1). Split the base so the promise only exists where it can be kept. A no-op override is the loudest evidence of a broken is-a.
- **Not a finding when**: the base defines an optional lifecycle hook whose default is deliberately empty *in the base* — that's a default, not an override.

### 5.18 — "Do not confuse optional containment with the need for inheritance; modelling optional containment with inheritance will lead to a proliferation of classes."

- **Smell**: `OrderWithDiscount`, `OrderWithGift`, `OrderWithDiscountAndGift` — a type per combination of optional parts.
- **Check**: do the subclass names read as combinations of features?
- **Fix**: one class with optional contained parts (nullable field, collection, option type).
- **Not a finding when**: the variants have genuinely different behaviour rather than just extra data.

### 5.19 — "When building an inheritance hierarchy try to construct reusable frameworks rather than reusable components."

Design-mode guidance, rarely a review finding. In review, the useful form: does the hierarchy define a *shape of collaboration* extenders plug into, or just a bag of shared code? The latter is 5.1.

---

## Chapter 6 — Multiple inheritance

Void where the language has no MI. In Go, the analogue is multiple embedded structs; in Python and TS, mixins.

### 6.1 — "If you have an example of multiple inheritance in your design, assume you have made a mistake and prove otherwise."

- **Check**: for each base, apply 6.2's two questions independently. Any base failing question 1 should have been containment.
- **Fix**: keep at most one true is-a; convert the rest to contained parts.
- **Not a finding when**: the extra bases are pure interfaces with no state and no implementation — that's interface composition, which Riel's caution isn't aimed at.

### 6.2 — "Whenever there is inheritance ask: 1) Am I a special type of the thing I'm inheriting from? 2) Is the thing I'm inheriting from part of me?"

The universal inheritance test. Apply to *every* inheritance edge, not just multiple ones. A "yes" to question 2 means containment.

### 6.3 — "Whenever you have found a multiple inheritance relationship be sure that no base class is actually a derived class of another base class, i.e. accidental multiple inheritance."

- **Check**: walk each base's own ancestry looking for overlap. In Go, check whether two embedded structs themselves embed a common type.
- **Fix**: inherit from the most derived one only.
- **Cost when real**: duplicated state, ambiguous method resolution, and a diamond whose behaviour depends on MRO rules nobody remembers.

---

## Chapter 7 — The association relationship

### 7.1 — "When given a choice between a containment relationship and an association relationship, choose the containment relationship."

- **Rationale**: containment gives a single owner and a clear lifetime; association leaves both open.
- **Check**: for each association, ask whether the referenced object has an independent lifetime and other owners. If not, it should be contained.
- **Not a finding when**: the collaborator genuinely is shared (a connection pool, a clock, a logger) or must be substitutable for testing. Then association — injected, ideally behind an interface the consumer defines — is right. This heuristic is about *modelling* choice, not a mandate against dependency injection.

---

## Chapter 8 — Class-specific data and behaviour

### 8.1 — "Do not use global data or functions to perform bookkeeping information on the objects of a class; class variables or methods should be used instead."

- **Smell**: package-level counters, registries, caches, or ID sequences tracking instances of a type.
- **Check**: find global mutable state; determine which type it is really about.
- **Fix**: move it onto the type itself (a class variable, a static, a registry object owned by the type). Where the language has no class variables (Go), the fix is an explicit owner object rather than a package-level `var` — which also removes the hidden global that makes the code untestable and racy.
- **Not a finding when**: it's genuine process-wide configuration, or an immutable lookup table.

---

## Chapter 9 — Physical object-oriented design

### 9.1 — "Object-oriented designers should never allow physical design criteria to corrupt their logical designs. However, very often physical design criteria is used in the decision making process at logical design time."

- **Smell**: abstractions shaped by the database schema, the wire format, the file layout, or the framework's folder conventions rather than the domain — `UserRow`, `OrdersTable`, one class per table, fields ordered for serialization.
- **Check**: would this design survive changing the storage or transport? If a schema change forces domain changes, the physical shape has leaked in.
- **Fix**: model the domain, then map to storage at the boundary.
- **Not a finding when**: the physical constraint is real and was traded deliberately (a hot path where an extra allocation matters). Riel expects such trades — the finding is when they were made silently and the domain type still claims to be a domain type.

### 9.2 — "Do not change the state of an object without going through its public interface."

- **Smell**: mutating another object's fields directly; a caller performing a multi-step state change the object should own atomically.
- **Check**: find external writes to fields; find call sequences that must run in order to leave the object valid.
- **Fix**: one operation on the owner expressing the intent and preserving the invariant.
- **Not a finding when**: the object is a value/DTO with no invariant to preserve.

---

## The balance check — god class vs class proliferation

Almost every heuristic in this catalogue pushes in one direction: **split, distribute, move behaviour out**. Applied without a counterweight they produce the opposite defect, and Riel's heuristics name it far less loudly than the god class. There are **two** failure modes, and a design should be checked against both:

| | **God class** | **Class proliferation** |
|---|---|---|
| Shape | one class controls everything | functionality smeared over many tiny classes |
| Signature | scattered cohesion matrix, high accessor ratio, peers reduced to data bags | algorithms that continually request information back from other objects to do their work |
| Reading it | one file explains the feature, and it's 900 lines | no file explains the feature; you follow six hops and still can't see the rule |
| Fix direction | redistribute (3.1, 3.3, 2.10) | **merge** (2.9, 4.1) |

Signals that a design has been cut too far:

- A class whose methods spend most of their lines fetching state from collaborators before they can decide anything — the decision and the data have been separated (2.9 again, pointing the other way).
- A "class" with one meaningful method, no state of its own, and a verb for a name (3.9).
- A containment level that only forwards, adding no decision, rule, or translation (3.10).
- A rule you cannot state without naming four types.

Riel's own qualifier on the non-communicating-behaviour heuristics applies to this whole catalogue: some classes simply have many attributes with no logical class to split off; many small classes carry their own runtime and cognitive costs; and a deliberate wrapper or facade presenting one interface to a subsystem is *supposed* to look like this.

**In the report, say which of the two failure modes you're claiming.** A finding that doesn't distinguish them is asking for churn in an unspecified direction. And when a design sits reasonably between them, say so — "balanced" is a verdict.

## Using the heuristics in a design discussion

The heuristics identify *where* a design might change; they do not decide *whether* it should. Where a heuristic points at a deliberate trade-off, present both alternatives with the argument for each rather than issuing a verdict.

Riel's door-control example: a `Door` that owns its public interface and asks a `DoorController` only for policy, versus a `DoorController` that owns everything and drives the doors as hardware. The second is a god class by 3.2. It may still be the right design — shorter call paths, fewer places to enforce a security rule, parts implementable in hardware. The first is more flexible and easier to extend with new door types. There is no correct answer independent of what the system needs to optimise.

So: name the heuristic, name what it costs, name what the current design buys instead, and let the reader decide. Reserve a flat recommendation for cases where the trade-off is not real — where the heuristic-conforming design is also the simpler one.

## Conflicts and their resolution

Riel's heuristics genuinely disagree with each other. Cite both sides; never present one as settled.

| Tension | Resolution |
|---|---|
| **5.4** (deeper the better) vs **5.5** (no deeper than six) | 5.5 governs. 5.4 only forbids *flattening* a genuine specialization hierarchy; it never licenses adding levels. |
| **3.6** (model the real world) vs **3.1 / 3.2 / 2.9** | Riel's own exception clause: fidelity yields when it produces a god class or separates data from behaviour. Name the trade in the report. |
| **2.4** (universal minimal interface) vs **2.3 / 2.6** (minimize the protocol) | 2.4's set is small, fixed, and buys substitutability; 2.3/2.6 govern the *domain-specific* protocol. Copy/equals/print are not clutter. |
| **4.9** (constraints in the class definition) vs class proliferation | Built into 4.9: prefer the type system until it would explode into a class per combination, then the constructor. |
| **5.7** (all base classes abstract) vs useful default behaviour | Contested; the deck rebuts 5.7. Prompt only. Decide on whether an instance of the base means anything in the domain. |
| **5.13** (case on attribute → subclass per value) vs **5.14** (don't model dynamic semantics with inheritance) | If the attribute changes during the object's lifetime, 5.14 wins: contain a state object, don't subclass. |
| **7.1** (prefer containment) vs testability / substitution | Containment is the default for *modelling*. A collaborator that must be substituted or is genuinely shared is an association by design, not a violation. |
| **4.8** (deep containment) vs **3.10** (drop pass-through agents) | Depth must carry decisions. A level that only forwards is an agent to delete, not depth to keep. |
| **5.8** (factor commonality up) vs coincidental duplication | Lift only what every descendant needs *for the same reason*. Same shape with different reasons to change stays separate. |
| **2.8 / 2.10 / 3.4** (split it) vs class proliferation | The catalogue's built-in bias. Before proposing a split, check the merge direction too — see "The balance check". |
| **5.1** (specialization only) vs framework and pattern inheritance | The four legitimate uses under 5.1 are reasons to inherit; none of them excuses a failed substitution test. Run the test regardless. |

---

## Sources

- Arthur J. Riel, *Object-Oriented Design Heuristics*, Addison-Wesley 1996 — the 61 heuristics and their canonical wording.
- Harald Gall (University of Zurich), *Object-Oriented Design Heuristics* — the "warning mechanisms, not hard and fast rules" framing; the rebuttal of 5.7.
- Dennis Mancl, *Object Oriented Design Heuristics* (CC BY 4.0, 2021) — 5.1 as the Liskov Substitution Principle and the precondition/postcondition test; the class-proliferation counterweight; the 3.3 diagnostic question; superficially-object-oriented topology; the facade abstraction-level check; worked remedies for 4.7, 5.14, and 5.15.
- Elisa Banniassad, "Making the Liskov Substitution Principle Happy and Sad" (SPLASH 2017) — the wider-precondition / narrower-postcondition check.
