## Close out and land

```
clerk land                    # archive the breakdown; integrate if the repo says so
clerk land --integrate        # …and put it on the default branch regardless
clerk land --no-integrate     # …and leave the branch standing regardless
```

`land` asks `clerk step` first and refuses unless the run has reached this step — the audit's acceptance, the request re-read and the verify pass are all read from the ledger at this code tree, never re-asserted. Then it checks what the table does not look at, and refuses on any of them: every task checked off, the tree clean, a passing receipt **at the current code tree**. Only a branch landed without a run ledger needs `--audit-accepted`, because there the acceptance has nowhere else to live.

It archives the breakdown to `tasks/completed/` **on the feature branch, before any integration**, so the archive commit rides with the work it belongs to rather than landing on the default branch behind it. That order is also the only one that works: `git mv` leaves a dirty tree and a dirty tree blocks the rebase.

**Integration is opt-in, and `land` resolves that itself** — bare `clerk land` reads the repo's `integrate` setting, so pass a flag only to overrule it. With integration off the work stays on its branch and you hand it over, naming the branch and the one command that lands it. That default is not timidity: landing is the one irreversible step here and its inputs are all things you assessed about your own work. A branch left standing costs one `merge --ff-only` later; a bad fast-forward costs a history rewrite.

A repo that sets `integrate: true` has decided that trade for itself, and `land` reports `integrate_source` either way so the decision is never anonymous. **The stronger your doubt about the work, the more that setting is the wrong one to inherit silently** — `--no-integrate` overrules it for one run, and a branch handed over is the cheap outcome to be wrong about.

With `--integrate` it rebases onto the default branch, and **stops if the rebase actually replayed commits onto a moved base** — green-before-rebase is not green-after, so it returns exit 3 and asks for a fresh suite run and receipt before it will fast-forward. On conflict it aborts the rebase and leaves the branch exactly as it was; do not resolve someone else's merge for them. It never pushes.

{{variant:worktree-teardown}}

