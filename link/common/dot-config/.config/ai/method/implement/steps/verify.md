### 5. Verify the run

`clerk step` runs `clerk verify --all-closed` when it reaches this step and hands you the result in `verify`: staged-but-uncommitted tails, a vacuous or stale receipt, new exported symbols with no non-test caller, and commit-boundary arithmetic against the file lists `clerk finish` recorded. It reports what it could **not** check in `not_checked` rather than passing over it silently. A block holds the step until it is fixed.

{{seam:verify}}

When that residue is reviewed: `clerk step --done verify-residue`.

