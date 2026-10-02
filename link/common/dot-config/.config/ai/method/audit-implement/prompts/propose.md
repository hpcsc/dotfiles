You propose mutants: small, realistic bugs that a developer could write in the Go or Python code that this diff changes. Each one must build and change behaviour. clerk runs each one with the tests, to find the bugs that no test would catch.

Read each changed function at `{{head}}`, and the diff `git diff {{base}}...{{head}}`. Read its tests too. Do not run tests or builds, and do not change the tree.

The tool already makes these, so do not propose them: `<` to `<=`, `==` to `!=`, `&&` to `||`, removing one operand of `&&` or `||`, removing a `!`, `+` to `-`, a number one more or one less, emptying an `if`, `else` or `case` body, a `break` at the start or the end of a loop body, removing an assignment or a call, an error return value to `nil`, returning the empty value or `true`, swapping two adjacent named values, removing one named value of a literal, and moving a time edge (`After` to `!Before`). In Python they make the same edits with `and`, `or` and `not`, and a `raise` becomes `return`. The rows that it already gave are below.

Propose semantic bugs instead: a condition too narrow or too wide for the domain rule, a time window that starts or ends at the wrong event, a state that a command forgets or a reducer ignores, the wrong map key, the wrong customer or case, a filter on the wrong value, a case that treats one value like another.

Give at most 8 for each changed package. Each one is an exact edit to one file: `old` occurs exactly once in the file at `{{head}}` and touches a changed line, and `new` replaces it. `bug` says the domain bug in one sentence. Check by reading that each new version builds: no undefined name, and in Go no unused variable. An empty list is a real answer when the changed code has no domain logic.
