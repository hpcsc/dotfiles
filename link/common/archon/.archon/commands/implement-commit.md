# implement — commit

Commit the changes produced by the task that was just approved. The subject context
arrives under `=== RUNTIME INPUT ===` as `SUBJECT_CONTEXT`.

- Stage and commit the working-tree changes for this task only.
- Follow the project commit guidelines: imperative subject ≤ 50 chars, capitalized,
  no trailing period, no AI/Claude attribution, no `Co-Authored-By` trailer.
- Use `SUBJECT_CONTEXT` as the basis for the message; refine it to read as a clean
  imperative summary of the change.
- If a Linear initiative or ticket trailer applies to this branch, include it.

Print the resulting commit hash and subject as your final output. Do nothing else —
no pushing, no PR.
