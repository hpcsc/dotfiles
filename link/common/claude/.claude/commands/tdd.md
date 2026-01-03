Implement a feature using Test-Driven Development: $ARGUMENTS

## Phase 0: PLANNING (Think Deeply)

Use extended thinking to deeply analyze the requirements and design a TDD implementation plan.

### Analysis Steps:
1. **Understand the Feature** - What is the user asking for? What is the expected behavior?
2. **Identify Components** - What modules, functions, types need to be created or modified?
3. **Break Down into Baby Steps** - Decompose into the smallest possible increments

### TDD Step Requirements:
Each step in the plan MUST:
- Be small enough to complete in ONE TDD cycle (one test, one implementation)
- Contribute toward feature completion
- Leave the codebase in a working, committable state
- Not break existing functionality
- Build on previous steps

### Output the Plan:
```markdown
## TDD Implementation Plan: [Feature Name]

### Overview
[Brief description of the feature]

### Steps
1. [First baby step] - [What test will verify this]
2. [Second baby step] - [What test will verify this]
3. ...

### Dependencies/Considerations
[Any important notes about order, existing code, etc.]
```

Get user approval before proceeding.

---

## Phase 1-3: TDD CYCLES

For each step in the approved plan, execute a complete Red-Green-Refactor cycle:

### RED Phase
Delegate to the `tdd-test-writer` agent for this step.
- **GATE**: Do NOT proceed until the test FAILS with the expected error
- If test passes unexpectedly, clarify whether behavior already exists

### GREEN Phase
Delegate to the `tdd-implementer` agent for this step.
- **GATE**: Do NOT proceed until the test PASSES
- Implement ONLY what's needed to pass the current test

### REFACTOR Phase
Delegate to the `tdd-refactorer` agent for this step.
- **GATE**: All tests must still PASS after refactoring
- Skip if no refactoring is needed

### COMMIT Phase
Delegate to the `commit` agent to commit the completed step.
- Stage all changes from this TDD cycle
- Agent will draft commit message and request user approval
- **GATE**: Do NOT proceed to next step until commit is complete

### After Each Cycle:
- Update progress on the plan
- Move to the next step

---

## Completion

After all steps are done:
1. Run the full test suite to confirm everything passes
2. Summarize what was implemented
3. List all commits created during this TDD session
4. Confirm feature is complete
