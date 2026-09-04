## Why this exists, and when it beats `implement-flow`

`implement-flow` runs construction *and* review through agents. Measured over a real multi-task feature, construction — implement, refactor, audit, and the retries they cause — was **64% of wall clock**, while review produced nearly all of the value. Construction is serial, judgment-dense and context-heavy: the work a main agent is fastest at and fan-out helps least with. Review is embarrassingly parallel and *benefits* from independence, because a lens with no attachment to the code is exactly what you want.

**Use `audit-implement`** when you (or a colleague) already built the thing and want it genuinely challenged: several specialist lenses at once, each claim reproduced before it reaches you.

**Use `implement-flow` instead** when the work is a large mechanical migration with genuinely disjoint files, when you want an unattended overnight run, or when you specifically want an independent implementer — e.g. to test whether a spec is unambiguous enough for a fresh agent to satisfy.

**Use `/code-review`** for a quick pass on a small diff. This skill is heavier: it spawns a scoping agent, one agent per lens, and one or more verifiers per candidate finding.
