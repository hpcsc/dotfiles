Invoke the `audit-implement` skill. There is no workflow engine here, so it orchestrates the lenses itself via the `task` tool — the findings are the same shape, but their structure rests on the lenses following the output contract rather than on schema validation.

Record each round from the findings it returns: write them to a file, or pipe them, `clerk audit round --report -` reads stdin. The counts it records are whatever `findings`, `refuted` and `coverage_gaps` arrays the report carries.
