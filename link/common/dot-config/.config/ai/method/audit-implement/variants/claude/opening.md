This is the **review half** of construct-directly-then-audit. You implement, committing as you go; this audits what you built, from the outside, with lenses that never saw you write it.

**clerk drives it, not you.** `clerk audit run` holds the phase order, decides which lenses this diff earns, spawns each agent, validates the reply against its schema and asks again when it does not fit. Your part is the launch, and the findings when they come back.
