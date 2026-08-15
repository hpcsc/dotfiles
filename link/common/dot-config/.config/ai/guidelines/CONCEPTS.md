# Concepts

A **concept** is a stable name for a section, so a consumer can ask for guidance without
knowing what the section is called. It is declared by the guideline, in an HTML comment
directly under the heading:

```markdown
## Assertion Strictness: Match to What You're Testing
<!-- concept: assertions -->
```

`clerk guidelines --concept assertions` finds that marker and returns the section it sits
in. The heading above it is prose: reword it, requalify it, renumber it — nothing that
depends on the section notices.

The vocabulary is shared across guidelines on purpose. Go, JavaScript, Elixir and the
language-agnostic set each carry an `assertions` concept, and each says something
different about it; a consumer asks for `assertions` and gets whichever applies to the
language in hand. That is why the name is a concept rather than an id: the same one
appears in four documents deliberately.

This sits below `topic` in the existing vocabulary, where a topic is a whole guideline
file — `guidelines/<domain>/<topic>.md`, as described in `GUIDELINE_ORGANIZATION.md`. So:
domain, then topic, then concept.

## Where concepts apply

Only guidelines that are read in parts carry them — today the five below. Everything else
is delivered whole, so there is nothing to address and no marker to write.

| Guideline | Concepts |
|---|---:|
| `testing/caller-patterns.md` | 8 |
| `testing/patterns.md` | 17 |
| `go/testing-patterns.md` | 19 |
| `javascript/testing-patterns.md` | 12 |
| `elixir/testing-patterns.md` | 13 |

Every heading in those files carries one, including the ones nothing currently reads. A
file where some headings are addressable and others silently are not is a file where the
absence of a marker means two different things.

## The vocabulary

| Concept | What the section covers | Carried by |
|---|---|---|
| `public-api-only` | Testing behaviour through the public API rather than internals | all 4 |
| `what-to-test` | Which behaviours are worth a test at all | all 4 |
| `unit-of-behavior` | What counts as one unit of behaviour, and what does not | all 4 |
| `assertions` | How strict an assertion should be, matched to what is under test | all 4 |
| `independent-verification` | Whether an expected value is reasoned from the domain or copied from the implementation | all 4 |
| `test-structure` | How a test is arranged and named | all 4 |
| `anti-patterns` | Test shapes to avoid, with examples | all 4 |
| `checklist` | The run-through for spotting the above in a diff | all 4 |
| `test-doubles` | Fakes, stubs and spies, and which boundary each belongs at | go, js, elixir |
| `test-qualities` | Fidelity, resilience and precision — the three axes a test is judged on | go, testing |
| `implementation-detail-tests` | Recognising a test coupled to how the code works | go, testing |
| `coupling-levels` | Contract, model, functional and intrusive integration strength | go, testing |
| `http-handler-scope` | Why the endpoint, not the function, is the component under test | go, testing |
| `no-test-only-exposure` | Never widening visibility just to let a test reach something | go, testing |
| `test-clarity` | Including only the details the test's own failure depends on | go, testing |
| `negative-paths` | Error paths and the invariants that must hold on them | go, elixir |
| `summary` | The closing table of practices — titled "Summary" in two guidelines and "Quick Reference" in the others | all 4 |
| `contract-tests` | One suite run against every implementation of an interface | go |
| `test-helpers` | Helpers that build fixtures without hiding the assertion | go |
| `observable-behavior-examples` | Worked examples of asserting on outcomes | testing |
| `benefits` | What the approach buys | testing |
| `dom-testing` | Asserting on rendered output rather than DOM structure | js |
| `async-testing` | Waiting on outcomes rather than timers | js |
| `concurrency-testing` | Processes, messages and supervision under test | elixir |
| `database-testing` | Transactions, sandboxes and fixtures against a real store | elixir |
| `identify-caller` | Working out whose expectations define correctness | caller-patterns |
| `caller-ui` | User → page: assert on visible content, not markup | caller-patterns |
| `caller-inbound` | External system → handler: assert on acceptance and side effects | caller-patterns |
| `caller-outbound` | Our system → external service: assert on what was delivered | caller-patterns |
| `caller-async` | Trigger → side effects: assert on output events and idempotency | caller-patterns |
| `caller-exported` | Other code → this interface: assert on the contract | caller-patterns |
| `no-caller-cases` | Config guards and parity checks, which have no runtime caller | caller-patterns |
| `caller-quick-reference` | The five patterns as one lookup table | caller-patterns |

## Which role reads what

A role is a job, not an agent. Several agents share one — `go-implementer`,
`js-implementer` and `elixir-implementer` are all the implementer role, and each gets its
own language's treatment of the same concepts.

| Role | Concepts |
|---|---|
| **implementer** | `public-api-only` `what-to-test` `unit-of-behavior` `assertions` `independent-verification` `test-structure` `test-doubles` `negative-paths` `test-clarity` `no-test-only-exposure` `identify-caller` `caller-quick-reference` |
| **refactorer** | `public-api-only` `unit-of-behavior` `test-structure` `no-test-only-exposure` `implementation-detail-tests` `test-clarity` |
| **test designer** | `identify-caller` `caller-quick-reference` `no-caller-cases` `what-to-test` `unit-of-behavior` `independent-verification` `coupling-levels` `test-qualities` `assertions` `observable-behavior-examples` `http-handler-scope` |
| **semantic reviewer** | `public-api-only` `what-to-test` `unit-of-behavior` `assertions` `independent-verification` `test-qualities` `implementation-detail-tests` `negative-paths` `no-caller-cases` `identify-caller` `caller-quick-reference` |
| **test reviewer** | everything the semantic reviewer reads, plus `anti-patterns` `checklist` `test-clarity` `test-doubles` `test-helpers` `contract-tests` `http-handler-scope` `no-test-only-exposure` `summary` |
| **concurrency reviewer** | `concurrency-testing`, alongside its language's concurrency guideline |

Two additions are conditional rather than role-wide: `dom-testing` and `async-testing`
come with `--dom`, and `database-testing` with Elixir work that touches a store.

The five caller patterns are not listed per role because no role reads all of them. A
consumer identifies its caller first, then asks for that one with `--caller`.

### Unclaimed

`benefits` is read by no role. It is a closing recap of material the concepts above
already deliver, so nothing is missing — but it is the first place to look if a guideline
starts feeling like it is being ignored.

### Where a role wants more than its guideline carries

The guidelines are not uniform, so a role's list is the concepts it reads **that its own
guidelines declare**. `testing/patterns.md` backs up whatever a language guideline lacks,
and a concept comes from the first guideline in the plan that declares it, so a language's
own treatment always wins. What that still leaves:

| Concept | Carried by | Absent from |
|---|---|---|
| `negative-paths` | go, elixir | javascript, the shared set — error-path testing is not language-specific, so both are real gaps |
| `test-doubles` | go, javascript, elixir | the shared set |
| `contract-tests` · `test-helpers` | go | the others — both are Go idioms (interface contract suites, table-driven helpers), so not gaps |

Filling the first two rows would let every role read its full list. Until then a role
simply does not ask for what its guidelines do not have, which keeps "Not loaded" meaning
drift rather than a standing complaint.

## Adding to a guideline

- **A new section**: give it a concept. Reuse an existing name if another guideline
  already teaches the same thing, so a consumer asking for it gets your language's
  treatment too. Invent a name only for genuinely new ground.
- **A reworded, requalified, renumbered or moved heading**: nothing to do. The concept
  travels with the section.
- **A deleted section**: the guard test fails, naming the concept and every role that
  asked for it. Either restore the concept on whatever replaced it, or drop it from the
  roles that wanted it — deliberately, which is the point of it failing.
