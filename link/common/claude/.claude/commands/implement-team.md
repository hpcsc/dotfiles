Implement a feature with quality-assured testing using an agent team: $ARGUMENTS

## Overview

This command orchestrates a rigorous implementation workflow using Claude Teams with built-in test quality review. The team consists of:
- **Team Lead (You)**: Coordinates work, manages tasks, synthesizes results (delegate mode - coordination only)
- **Implementer Agent**: Writes production code
- **Test Writer Agent**: Writes tests following TDD principles
- **Test Reviewer Agent**: Reviews test quality against best practices

Each implementation cycle includes:
1. Detailed planning with baby steps (by lead)
2. Contract agreement between implementer and test writer
3. Parallel implementation (code by implementer, tests by test writer)
4. Integration and validation (implementer + test writer collaborate)
5. Test quality review (delegated to test reviewer agent)
6. Human approval and commit (coordinated by lead)

**Display Mode**: tmux split panes for real-time visibility of all agents

**Permission Mode**: Delegate mode - lead focuses on coordination, teammates do implementation

---

## Setup: Enable Agent Teams

Before using this command, ensure agent teams are enabled in your settings.json:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "tmux"
}
```

---

## Phase 1: PLANNING (Team Lead - Think Deeply)

Use extended thinking to deeply analyze the requirements and design an implementation plan.

### Analysis Steps:
1. **Understand the Feature** - What is the user asking for? What is the expected behavior?
2. **Identify Components** - What modules, functions, types need to be created or modified?
3. **Break Down into Baby Steps** - Decompose into the smallest possible increments
4. **Consider Test Strategy** - How will each step be tested through public API?

### Step Requirements:
Each step in the plan MUST:
- Be small enough to complete in ONE implementation cycle
- Focus on a single behavior or business rule
- **Include BOTH implementation AND its corresponding tests in the SAME step** (unless tests are not needed)
- Be testable through public/exported API only
- Contribute toward feature completion
- Leave the codebase in a working, committable state
- Not break existing functionality
- Build on previous steps

### Test Decision:
The team lead must decide for each step whether tests are needed:
- **Write tests** for: business logic, algorithms, complex behavior, edge cases, error handling
- **Skip tests** for: trivial logic, getters/setters, simple data structures, configuration, obvious delegation

**CRITICAL**: Each commitable step must include both the code changes and the tests that verify those changes (when tests are applicable). This ensures each commit is self-contained and verifiable.

### Output the Plan:
```markdown
## Implementation Plan: [Feature Name]

### Overview
[Brief description of the feature]

### Steps
1. [First baby step - implementation + tests]
   - Needs Tests: YES/NO
   - Implementation: [What code/behavior will be added]
   - Tests: [What tests will be written to verify through public API] (if applicable)
   - Commit: [Brief description of what this commit will contain]

2. [Second baby step - implementation + tests]
   - Needs Tests: YES/NO
   - Implementation: [What code/behavior will be added]
   - Tests: [What tests will be written to verify through public API] (if applicable)
   - Commit: [Brief description of what this commit will contain]

3. ...

### Dependencies/Considerations
[Any important notes about order, existing code, test strategy]
```

**NOTE**: Each numbered step represents ONE commit that includes both implementation and tests (when tests are needed).

**GATE**: Get user approval before proceeding to team setup.

---

## Phase 2: TEAM SETUP

After plan approval, create the agent team and enter delegate mode.

### Create Team

```markdown
Create an agent team called "implement-[feature-name]" with the following teammates:

1. **Implementer** (general-purpose agent, model: sonnet):
   - Role: Implement production code, collaborate on public contracts
   - Tools: Full access (Bash, Read, Edit, Write, Grep, Glob)
   - Instructions: Focus on implementation logic, collaborate with test-writer on contracts

2. **Test Writer** (general-purpose agent, model: sonnet):
   - Role: Write tests following TDD principles, collaborate on public contracts
   - Tools: Full access (Bash, Read, Edit, Write, Grep, Glob)
   - Instructions: Follow test-go guidelines, test through public API, write descriptive tests, work with implementer to ensure tests pass

3. **Test Reviewer** (test-go-reviewer agent, model: sonnet):
   - Role: Review test quality against best practices
   - Tools: Read, Grep, Glob, Bash (for running tests)
   - Instructions: Check all test-go guidelines, provide detailed feedback with file:line references

Use tmux split panes for display.
Team lead uses model: opus.
```

### Enter Delegate Mode

After team is created, the lead should switch to **delegate mode**:

Press **Shift+Tab** to cycle into delegate mode. This restricts the lead to coordination-only tools.

**GATE**: Verify team is created and delegate mode is active before proceeding.

---

## Phase 3: IMPLEMENTATION CYCLES

For each step in the approved plan, execute a complete implementation and review cycle using the team.

### Create Tasks

Create tasks for each step in the plan. Task structure differs based on whether tests are needed:

#### For Steps WITH Tests:

```markdown
Task 1: Define public contract for step 1
- Description: Implementer and Test Writer agree on public API/contract for [step description]
- Owner: (unassigned)

Task 2: Implement step 1 - production code
- Description: [Implementation details]
- Owner: (unassigned - for Implementer)
- Blocked by: Task 1

Task 3: Implement step 1 - tests
- Description: [Test requirements]
- Owner: (unassigned - for Test Writer)
- Blocked by: Task 1

Task 4: Integrate and validate step 1
- Description: Implementer and Test Writer collaborate to ensure tests pass with implementation
- Owner: (unassigned)
- Blocked by: Task 2, Task 3

Task 5: Review tests for step 1
- Description: Review test quality for step 1
- Owner: (unassigned - for Test Reviewer)
- Blocked by: Task 4
```

#### For Steps WITHOUT Tests:

```markdown
Task 6: Implement step 2 - [step description] (no tests needed)
- Description: [Implementation details] - Tests skipped for trivial logic
- Owner: (unassigned - for Implementer)
- Blocked by: Task 5

Task 7: Validate step 2 (no test review needed)
- Description: Quick validation that code compiles and doesn't break existing tests
- Owner: (unassigned - for Implementer)
- Blocked by: Task 6
```

**IMPORTANT**: Structure tasks so that:
- Contract definition happens first (for tested steps)
- Implementation and test writing happen in parallel (both blocked by contract)
- Integration happens after both complete
- Review happens after integration
- Sequential flow: contract → [impl + tests in parallel] → integration → review

### Cycle Workflow

The workflow differs based on whether the step needs tests.

---

### Workflow A: Steps WITH Tests

#### Step 1: Contract Definition

Assign contract definition to both Implementer and Test Writer:

```markdown
Broadcast to Implementer and Test Writer:

Define the public contract for step [N]: [step description]

Implementer:
- Propose function/method signatures
- Define input/output types
- Define error conditions
- Read existing code to understand patterns

Test Writer:
- Review proposed contract
- Identify test scenarios needed
- Confirm contract is testable through public API
- Suggest any needed clarifications

Collaborate via direct messages to reach agreement.

When both agree:
1. Implementer: Document the agreed contract in a comment or interface
2. Both: Mark task as completed
3. Both: Notify lead that contract is agreed
```

**GATE**: Wait for both to confirm contract agreement.

---

#### Step 2: Parallel Implementation and Test Writing

Assign implementation and test tasks simultaneously:

```markdown
Assign Task [N+1] to Implementer:

Implement the production code for step [N] based on agreed contract: [step description]

Requirements:
- Follow the agreed public contract exactly
- Read existing code to understand patterns
- Implement ONLY what's needed for this step
- Do NOT run tests yet (Test Writer may not be done)

When complete:
1. Mark task as completed
2. Notify lead with summary of implementation
3. List implementation files created/modified
```

```markdown
Assign Task [N+2] to Test Writer:

Write tests for step [N] based on agreed contract: [step description]

Requirements:
- Follow the global test-go skill guidelines
- Test behavior through public/exported API only (the agreed contract)
- Write descriptive test names that describe scenarios
- Use nested subtests with t.Run()
- Include only relevant details in tests (avoid noise and over-abstraction)
- Assert strictly with require.Equal, not require.Contains
- Test both success and error cases
- Do NOT run tests yet (Implementer may not be done)

When complete:
1. Mark task as completed
2. Notify lead with summary of tests written
3. List test files created/modified
```

**GATE**: Wait for BOTH Implementer and Test Writer to complete.

---

#### Step 3: Integration and Validation

Assign integration task to both:

```markdown
Broadcast to Implementer and Test Writer:

Integrate and validate step [N]: Ensure tests pass with implementation

Implementer:
- Review the tests written by Test Writer
- Run the tests to see if they pass
- If tests fail due to implementation issues, fix the implementation
- Collaborate with Test Writer on any issues

Test Writer:
- Review the implementation by Implementer
- Run the tests to verify they pass
- If tests fail due to test issues, fix the tests
- Collaborate with Implementer on any issues

When ALL tests pass:
1. Both: Mark task as completed
2. Both: Notify lead with passing test output
3. List all files (implementation + tests)
```

**GATE**: Wait for both to confirm all tests pass.

---

#### Step 4: Test Quality Review

Assign review task to Test Reviewer:

```markdown
Assign Task [N+3] to Test Reviewer:

Review the tests written for step [N]: [step description]

Test files to review:
[List test files from Test Writer]

Provide detailed feedback with:
- Specific violations with file:line references
- Explanation of why each violation matters
- Suggestions for how to fix
- Final verdict: APPROVED or NEEDS REVISION

If revisions needed, address feedback to Test Writer AND Implementer (if public contract needs changing).

Mark task as completed when review is done.
```

**GATE**: Wait for Test Reviewer to complete and send verdict.

---

#### Step 5: Revision Loop (If Needed)

If Test Reviewer verdict is "NEEDS REVISION":

1. Determine who needs to revise:
   - Test issues only → Test Writer revises
   - Contract issues → Both revise (Implementer changes code, Test Writer updates tests)

2. Create revision task(s):
   ```markdown
   Create Task [N.4]: Revise tests for step [N]
   - Description: Address test review feedback: [paste reviewer feedback]
   - Owner: Test Writer (and Implementer if needed)
   - Blocked by: None (priority task)
   ```

3. Create re-integration task:
   ```markdown
   Create Task [N.5]: Re-validate step [N] after revisions
   - Owner: Both Implementer and Test Writer
   - Blocked by: Task [N.4]
   ```

4. Create re-review task:
   ```markdown
   Create Task [N.6]: Re-review tests for step [N]
   - Owner: Test Reviewer
   - Blocked by: Task [N.5]
   ```

5. Repeat until reviewer approves

**GATE**: Do NOT proceed until Test Reviewer approves.

---

### Workflow B: Steps WITHOUT Tests

#### Step 1: Simple Implementation

Assign implementation to Implementer:

```markdown
Assign Task [N] to Implementer:

Implement step [N]: [step description] (tests not needed - trivial logic)

Requirements:
- Read existing code to understand patterns
- Implement ONLY what's needed for this step
- Run existing test suite to ensure nothing breaks

When complete:
1. Mark task as completed
2. Notify lead with summary
3. List implementation files created/modified
4. Show output of existing test suite (if applicable)
```

**GATE**: Wait for Implementer to complete.

---

#### Step 2: Quick Validation

Review the implementation yourself or assign quick validation:

```markdown
Assign Task [N+1] to Implementer:

Quick validation of step [N]: Verify code compiles and doesn't break existing tests

Run: make test.all.fast (or appropriate test command)

Report results.
```

**GATE**: Wait for validation to pass.

---

### Step 6: Human Review (Both Workflows)

Present the implementation and test quality review to the user:

#### For Steps WITH Tests:

```markdown
## Step [N] Complete: [step description]

### Agreed Contract
[Contract agreed upon by Implementer and Test Writer]

### Implementation Summary
[Summary from Implementer]

### Test Summary
[Summary from Test Writer]

### Files Modified
- Implementation files: [list]
- Test files: [list]

### Test Quality Review
[Test Reviewer's final assessment - APPROVED]

### Test Output
[Passing test output from integration phase]

---

**Ready to commit this step?**
- Yes - Proceed to commit
- No - Explain what needs revision
```

#### For Steps WITHOUT Tests:

```markdown
## Step [N] Complete: [step description]

### Implementation Summary
[Summary from Implementer]

### Files Modified
- Implementation files: [list]

### Validation
[Existing test suite results]

---

**Ready to commit this step?**
- Yes - Proceed to commit
- No - Explain what needs revision
```

**GATE**: Wait for user approval before committing.

---

#### Step 7: Commit

Delegate to the `commit` skill to create a commit for this step:

```markdown
/pcommit
```

**GATE**: Wait for commit completion before proceeding to next step.

---

#### Step 8: After Each Cycle

- Update progress tracking
- Show completed vs remaining steps
- Proceed to next step (contract definition or simple implementation)

---

## Phase 4: COMPLETION

After all steps are done:

### 1. Run Full Test Suite

Ask the Implementer to run the full test suite:

```markdown
Message Implementer: Run the full test suite to verify everything passes:

make test.all.fast
# or appropriate test command for the project

Report the results.
```

### 2. Summarize Implementation

Synthesize the results from all teammates:

```markdown
## Feature Complete: [Feature Name]

### Steps Completed
1. ✅ [Step 1] - Implemented and reviewed
2. ✅ [Step 2] - Implemented and reviewed
3. ✅ [Step 3] - Implemented and reviewed
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
- All quality gates passed

### Team Performance
- Implementer: [number] implementations completed
- Test Writer: [number] test suites written
- Test Reviewer: [number] reviews completed
- Revision cycles: [number]
- Contracts agreed: [number]
```

### 3. Ask About Pull Request

```markdown
Would you like me to create a pull request for this feature?
```

### 4. Clean Up Team

After user confirms everything is complete:

```markdown
1. Shut down all teammates:
   - Send shutdown request to Implementer
   - Send shutdown request to Test Writer
   - Send shutdown request to Test Reviewer

2. Wait for teammates to acknowledge and exit

3. Clean up team resources:
   TeamDelete
```

**IMPORTANT**: Always shut down teammates before cleaning up the team.

---

## Phase 5: DELEGATE MODE REMINDERS

As team lead in delegate mode, you should:

### DO:
- ✅ Create and manage tasks in the shared task list
- ✅ Assign tasks to teammates
- ✅ Send messages to teammates with instructions
- ✅ Synthesize results from teammates
- ✅ Coordinate between teammates (especially Implementer and Test Writer during contract phase)
- ✅ Facilitate contract agreements between Implementer and Test Writer
- ✅ Make approval decisions for human review gates
- ✅ Decide which steps need tests and which don't
- ✅ Shut down teammates when done
- ✅ Clean up team resources

### DO NOT:
- ❌ Write or edit code yourself (delegate to Implementer)
- ❌ Write or edit tests yourself (delegate to Test Writer)
- ❌ Read code files to make implementation decisions (ask teammates)
- ❌ Run tests yourself (delegate to Implementer or Test Writer)
- ❌ Review tests yourself (delegate to Test Reviewer)
- ❌ Use Edit, Write, or other implementation tools directly

Your role is **coordination and orchestration only**.

---

## Key Principles

1. **Baby Steps** - Each cycle should be small and focused
2. **Test Decision** - Team lead decides if tests are needed for each step
3. **Contract First** - Implementer and Test Writer agree on public API before parallel work
4. **Parallel Work** - Implementation and test writing happen simultaneously after contract agreement
5. **Public API Testing** - Behavior verified through exported interfaces only
6. **Collaboration** - Implementer and Test Writer work together to ensure tests pass
7. **Quality Gates** - Multiple checkpoints before proceeding
8. **Human in the Loop** - User approves each step before commit
9. **Best Practices** - All tests follow test-go guidelines
10. **Delegate Mode** - Lead coordinates, teammates implement
11. **Parallel Visibility** - tmux split panes show all agent activity
12. **Clear Communication** - Teammates report progress and findings

---

## Error Handling

If at any point:
- Contract disagreement: Facilitate discussion between Implementer and Test Writer until agreement
- Tests fail during integration: Both Implementer and Test Writer work together to fix
- Implementation issues: Implementer fixes before marking task complete
- Test issues: Test Writer fixes before marking task complete
- Reviewer finds violations: Create revision task(s) for Test Writer and/or Implementer and loop back
- User rejects step: Create revision task with user feedback
- Build fails: Implementer should fix before marking task complete
- Teammate gets stuck: Message them directly with guidance or spawn replacement
- Teammate stops unexpectedly: Check their output, provide guidance, or spawn replacement

Never skip quality gates. Never proceed without approval.

---

## Troubleshooting

### Teammate Not Responding
- Check their pane in tmux to see current status
- Press Enter to view their full session
- Press Escape to interrupt if needed
- Send direct message with clearer instructions

### Task Dependencies Not Working
- Verify task blocked_by relationships are set correctly
- Check if blocking task is actually marked complete
- Manually update task status if needed

### Lead Trying to Implement Instead of Delegate
- Remind yourself you're in delegate mode
- Refocus on task creation and assignment
- Message appropriate teammate with instructions

### Too Many Permission Prompts
- Pre-approve common operations in permission settings
- Consider using `--dangerously-skip-permissions` for teammates (use cautiously)

---

## Token Usage Considerations

Agent teams use significantly more tokens than single-session workflows:
- Each teammate has its own context window
- Message passing adds overhead
- Cost scales with team size and communication
- Three-agent team (Implementer + Test Writer + Test Reviewer) uses more tokens than two-agent

This is worthwhile for complex, multi-step implementations where:
- Parallel implementation and test writing saves wall-clock time
- Contract-first approach reduces rework
- Clear separation of implementation, test writing, and review roles improves quality
- Quality assurance from dedicated test reviewer provides value
- Human approval gates prevent wasted effort on wrong direction

For simple, single-step tasks, use the regular `implement` command instead.
For medium complexity where parallel work isn't needed, consider a simpler two-agent team.
