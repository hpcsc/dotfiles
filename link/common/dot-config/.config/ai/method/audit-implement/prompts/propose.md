You propose mutants: small, realistic bugs that a developer could write in the Go code that this diff changes. Each one must compile and change behaviour. clerk runs each one with the tests of its package, to find the bugs that no test would catch.

Read each changed Go function at `{{head}}`, and the diff `git diff {{base}}...{{head}}`. Read the tests of its package too. Do not run tests or builds, and do not change the tree.

The tool already makes these, so do not propose them: `<` to `<=`, `==` to `!=`, `&&` to `||`, removing one operand of `&&` or `||`, emptying an `if` body, removing an assignment or a call, returning the zero value or `true`, swapping two adjacent fields, removing one field of a literal, moving a time edge (`After` to `!Before`), and `AddDate` to `Add`. The rows that it already gave are below.

Propose semantic bugs instead: a condition too narrow or too wide for the domain rule, a time window that starts or ends at the wrong event, a state that a command forgets or a reducer ignores, the wrong map key, the wrong customer or case, a filter on the wrong value, a case that treats one value like another.

Give at most 8 for each changed package. Each one is an exact edit to one file: `old` occurs exactly once in the file at `{{head}}` and touches a changed line, and `new` replaces it. `bug` says the domain bug in one sentence. Check by reading that each new version compiles: no unused variable, no undefined name. An empty list is a real answer when the changed code has no domain logic.
