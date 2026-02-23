---
disable-model-invocation: true
---

Implement a feature with quality-assured testing: $ARGUMENTS

## Overview

This command orchestrates a rigorous implementation workflow with built-in test quality review. Each implementation cycle includes:
1. Detailed planning with baby steps
2. Implementation with tests (delegated to sub-agent)
3. Test quality review against best practices
4. Human approval and commit

## Phase 1: PLANNING (Codebase-Aware Decomposition)

### Check for Existing Task File

If `$ARGUMENTS` points to an existing file in `tasks/` (e.g., `tasks/rate-limiting.md`):
1. Read the task file
2. Present the task list to the user
3. Skip decomposition and proceed directly to the approval gate below

### Decompose via Agent

If the input is NOT an existing task file, delegate to the `decompose-to-tasks` agent using the Task tool:

```
Decompose the following user story into implementation tasks:

[user story / feature description from $ARGUMENTS]
```

The agent will:
- Explore the codebase to identify affected files, patterns, and domain types
- Decompose into baby-step tasks ordered by dependency
- Save to `tasks/[story-name].md`
- Return a summary with file path, task titles, and key codebase findings

### Present the Plan

Show the user the task list from the agent output (or from the existing task file). Each task maps to one implementation cycle in Phase 2:
- The task's **Behavior** + **Acceptance Criteria** define what to implement and test
- The task's **Verification** defines how to confirm it works
- The task's **Affected Files/Modules** + **Patterns to Follow** inform implementation approach

**CRITICAL**: Each task represents ONE commit that includes both implementation and tests. Never separate implementation and tests into different steps.

**GATE**: Get user approval before proceeding to implementation. If the user requests changes to the task list, delegate back to the agent with the feedback.

---

## Phase 2: IMPLEMENTATION CYCLES

For each step in the approved plan, execute a complete implementation and review cycle.

### Cycle Workflow

#### Step 1: Implementation with Tests

Delegate to a general-purpose sub-agent to implement the step with tests.

**Agent Instructions:**
```
Implement step [N] from the plan: [step description]

Requirements:
- Write tests following the global test-go skill guidelines
- Test behavior through public/exported API only
- Write descriptive test names that describe scenarios
- Use nested subtests with t.Run()
- Include only relevant details in tests (avoid noise and over-abstraction)
- Assert strictly with require.Equal, not require.Contains
- Test both success and error cases

Implementation:
- Read existing code to understand patterns
- Implement ONLY what's needed for this step
- Run tests to verify they pass
- Do NOT commit yet

When complete, provide:
1. Summary of what was implemented
2. Test files created/modified
3. Implementation files created/modified
4. Test output showing all tests pass
```

**GATE**: Do NOT proceed until implementation agent completes and all tests pass.

---

#### Step 2: Test Quality Review

Delegate to the `test-go-reviewer` agent to analyze test quality.

**Agent Task:**
```
Review the tests written for step [N]: [step description]

Test files to review:
[List test files created/modified in Step 1]

Provide detailed feedback with specific violations and suggestions.
```

The `test-go-reviewer` agent will:
- Check all test-go guidelines (public API, clarity, anti-patterns, mocking)
- Provide file:line references for violations
- Explain why violations matter and how to fix them
- Give verdict: APPROVED or NEEDS REVISION

**GATE**: Do NOT proceed until reviewer provides feedback.

---

#### Step 3: Revision Loop (If Needed)

If reviewer verdict is "NEEDS REVISION":

1. Delegate back to implementation agent with reviewer feedback:
   ```
   Revise tests for step [N] based on reviewer feedback:

   [Paste reviewer feedback]

   Address all violations and suggestions.
   Re-run tests to ensure they still pass.
   ```

2. After revision, delegate back to `test-go-reviewer` agent for re-review

3. Repeat until reviewer verdict is "APPROVED"

**GATE**: Do NOT proceed until reviewer approves.

---

#### Step 4: Human Review

Present the implementation and test quality review to the user:

```markdown
## Step [N] Complete: [step description]

### Implementation Summary
[What was implemented]

### Files Modified
- Test files: [list]
- Implementation files: [list]

### Test Quality Review
[Reviewer's final assessment]

### Test Output
[Show passing tests]

---

**Ready to commit this step?**
- Yes - Proceed to commit
- No - Explain what needs revision
```

**GATE**: Wait for user approval before committing.

---

#### Step 5: Commit

Delegate to the `commit` skill to create a commit for this step.

**GATE**: Wait for commit completion before proceeding to next step.

---

### After Each Cycle:
- Update progress on the plan (mark step complete)
- Show remaining steps
- Proceed to next step

---

## Phase 3: COMPLETION

After all steps are done:

1. **Run Full Test Suite**
   ```bash
   make test.all.fast
   # or appropriate test command for the project
   ```

2. **Summarize Implementation**
   ```markdown
   ## Feature Complete: [Feature Name]

   ### Steps Completed
   1. ✅ [Step 1]
   2. ✅ [Step 2]
   3. ✅ [Step 3]
   ...

   ### Commits Created
   - [commit hash] [commit message]
   - [commit hash] [commit message]
   ...

   ### Test Coverage
   - Tests written: [count]
   - Test files: [list]
   - All tests passing: ✅

   ### Quality Assurance
   - All tests reviewed against test-go guidelines
   - All steps approved by human reviewer
   ```

3. **Ask user if they want to create a pull request**

---

## Key Principles

1. **Baby Steps** - Each cycle should be small and focused
2. **Public API Testing** - Behavior verified through exported interfaces only
3. **Quality Gates** - Multiple checkpoints before proceeding
4. **Human in the Loop** - User approves each step before commit
5. **Best Practices** - All tests follow test-go guidelines

---

## Error Handling

If at any point:
- Tests fail: Fix before proceeding
- Reviewer finds violations: Revise before proceeding
- User rejects step: Understand concern and revise
- Build fails: Fix before proceeding

Never skip quality gates. Never proceed without approval.
