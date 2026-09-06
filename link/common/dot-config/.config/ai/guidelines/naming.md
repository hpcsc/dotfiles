# Naming

Names are the primary documentation. A reader who knows the name should not need the
definition, and a reader who knows two names should not have to work out whether they
mean the same thing.

This governs identifiers: types, functions, variables, fields, constants, files,
packages, and the keys of a config or wire format you own. For Go package and interface
structure, follow `go/naming-patterns.md`.

## 1. One word, one concept, across the whole codebase

Pick a word for a concept and use it for nothing else. The scope is the repository, not
the file: a reader meets both uses with no boundary between them to say they differ.

A word another package already owns is taken. Choose a different one rather than qualify
yours.

- Bad: a test corpus of scenarios called `corpus`, in a repository where
  `rulebook.Corpus` is a corpus of rules. Both are correct English. A reader now checks
  which one every time, and a search for either returns both.
- Bad: `baseline` naming both a measured rate and the file the rates are measured over.
- Good: one of them changes. The scenarios are `scenarios`, the rates are `baselines`.

The same applies to a concept that has two names. If the code says `expectation` in one
file and `criterion` in the next, a reader assumes there are two things until they prove
otherwise.

## 2. Use the plain word

Prefer the word someone would use to explain the code out loud. A formal synonym does not
buy precision.

| Instead of | Write |
| --- | --- |
| `withheld`, `suppressed` | `notInPrompt`, `excluded` |
| `governs`, `presides` | `applies` |
| `utilize` | `use` |
| `terminate` | `stop`, `end` |
| `initiate` | `start` |
| `verify` | `check` |

The formal word makes the reader translate before they can read.

## 3. No metaphors

A name must not need an analogy explained before it can be read. The reader has to know
the domain; they should not also have to know your figure of speech.

- Bad: `dilutes` for a rule that must not affect a neighbouring case; `pin` for a
  statistical assertion; `park` for deferring; `the case next door`.
- Good: `staysOut`; `baseline`; `defer`; `another linked case`.

The tell is that the name works only after someone tells you the picture. `dilutes` reads
backwards once you know it — a scenario does not dilute anything, the rule is the thing
that must not spread.

## 4. Modals state the obligation

Use `must` for an obligation and `can` for a possibility. Do not use `should`, `may`, or
`might`, which leave the reader guessing whether the code enforces the thing or hopes for
it.

- Bad: `shouldShow`, `mayRetry`
- Good: `mustShow`, `canRetry`

## 5. A name that needs a paragraph is the wrong concept

When a name cannot be explained in a phrase, the usual fault is not the name. It is that
the concept does not exist, or does not earn its place.

Rename it twice. If both attempts trade one confusion for another, stop renaming and ask
what the concept does. Delete it if the answer is "nothing that another field does not
already say".

- A rule scenario could be marked `applies`, `stays_out` or `unchecked`. The header spent
  fifteen lines on the three. `stays_out` was read by no code at all, `unchecked` meant
  "nobody looked", and what a scenario asserted was already stated by the lists it filled
  in. All three went; nothing was lost.

The symptom to watch for: documentation that grows every time someone asks what a name
means. Each added paragraph is evidence against the concept, not for the explanation.

## Review

Check names for:

- A word used for two concepts, or two words used for one
- A word another package in the repository already owns
- A formal synonym where a plain word exists
- A metaphor, an idiom, or a name that needs its picture explained
- `should` or `may` where the code enforces or permits
- A concept whose explanation is longer than its definition
