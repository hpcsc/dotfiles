## Error handling

| Scenario | Action |
|---|---|
| Base resolves to HEAD (empty diff) | Stop. Ask for the ref the work started from — the branch was probably already landed. |
| A lens returns malformed output | Re-spawn once with the schema restated. If it fails again, record it as a coverage gap rather than dropping it silently. |
| A lens returns nothing at all (it errored, not "found nothing") | Re-spawn it. If it still returns nothing, name it in the coverage gaps. A lens that vanished and a lens that looked and found nothing produce the same empty result and mean opposite things. |
| Every lens returns nothing | Say the audit did not run. Do not report a clean audit — nothing was reviewed. |
| A verifier cannot run the test command | Treat the finding as `plausible`, not refuted, and say the verification could not be executed. |
| Verifier left scratch files behind | Remove them and note it. Never commit them. |
| Every lens returns empty | Report that plainly, with the lens list and the coverage gaps. That is a result. |
