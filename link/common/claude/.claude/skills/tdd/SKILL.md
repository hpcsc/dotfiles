---
disable-model-invocation: true
---

Implement a feature using Test-Driven Development: $ARGUMENTS

## Phase 1: MODE SELECTION

Ask the user which TDD mode they want to use:

### Hands-Off Mode (Default)
Claude autonomously executes all TDD phases (Red-Green-Refactor) for each step, only pausing for plan approval and commit confirmations.

**Best for:**
- Feature implementation with clear requirements
- When you want to move quickly
- Learning TDD by observation

### Ping-Pong Mode (Interactive)
Human and Claude take turns in the TDD cycle.

**Ask the user to choose their role:**

1. **Human writes tests, Claude implements**
   - Human: Write failing test (Red)
   - Claude: Make it pass (Green) + Refactor

2. **Claude writes tests, human implements**
   - Claude: Write failing test (Red)
   - Human: Make it pass (Green) + Refactor

3. **Swap roles each cycle**
   - Cycle 1: Human writes test → Claude implements
   - Cycle 2: Claude writes test → Human implements
   - Cycle 3: Human writes test → Claude implements
   - ...and so on

**Best for:**
- Learning TDD hands-on
- Pair programming with Claude
- Complex features needing human judgment
- Building muscle memory

---

## Phase 2: PLANNING (Codebase-Aware Decomposition)

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

Show the user the task list from the agent output (or from the existing task file). Each task maps to one TDD cycle in Phase 3:
- The task's **Behavior** + **Acceptance Criteria** define what the failing test should assert
- The task's **Verification** defines how to confirm it works
- The task's **Affected Files/Modules** + **Patterns to Follow** inform where to write tests and implementation

Each task MUST be small enough to complete in ONE TDD cycle (one test, one implementation).

**GATE**: Get user approval before proceeding. If the user requests changes to the task list, delegate back to the agent with the feedback.

---

## Phase 3: TDD CYCLES

For each step in the approved plan, execute a complete Red-Green-Refactor cycle.

**The workflow varies based on the mode selected:**

---

### HANDS-OFF MODE WORKFLOW

For each step, execute all phases autonomously:

#### RED Phase
Delegate to the `tdd-test-writer` agent for this step.
- **GATE**: Do NOT proceed until the test FAILS with the expected error
- If test passes unexpectedly, clarify whether behavior already exists

#### GREEN Phase
Delegate to the `tdd-implementer` agent for this step.
- **GATE**: Do NOT proceed until the test PASSES
- Implement ONLY what's needed to pass the current test

#### REFACTOR Phase
Delegate to the `tdd-refactorer` agent for this step.
- **GATE**: All tests must still PASS after refactoring
- Skip if no refactoring is needed

#### COMMIT Phase
Delegate to the `commit` agent to commit the completed step.
- Stage all changes from this TDD cycle
- Agent will draft commit message and request user approval
- **GATE**: Do NOT proceed to next step until commit is complete

---

### PING-PONG MODE WORKFLOWS

The workflow changes based on who writes tests vs implements:

#### Workflow A: Human Writes Tests, Claude Implements

**For each step:**

1. **Human's Turn (RED)**:
   - Inform user it's their turn to write a failing test
   - Tell them which step from the plan they're implementing
   - Wait for user to write the test and confirm it fails
   - User should paste the test failure output

2. **Claude's Turn (GREEN + REFACTOR)**:
   - Delegate to `tdd-implementer` agent to make test pass
   - **GATE**: Test must PASS
   - Delegate to `tdd-refactorer` agent for improvements
   - **GATE**: Tests must still PASS after refactoring

3. **COMMIT Phase**:
   - Delegate to `commit` agent
   - **GATE**: Wait for commit completion

#### Workflow B: Claude Writes Tests, Human Implements

**For each step:**

1. **Claude's Turn (RED)**:
   - Delegate to `tdd-test-writer` agent to write failing test
   - **GATE**: Test must FAIL with expected error
   - Present test to user and wait for confirmation

2. **Human's Turn (GREEN + REFACTOR)**:
   - Inform user it's their turn to implement
   - Tell them what needs to be done to pass the test
   - Wait for user to implement and run tests
   - User should confirm tests pass
   - Prompt user to refactor if needed

3. **COMMIT Phase**:
   - Delegate to `commit` agent
   - **GATE**: Wait for commit completion

#### Workflow C: Swap Roles Each Cycle

**Track whose turn it is using a counter:**

- **Odd cycles (1, 3, 5...)**: Human writes test → Claude implements
- **Even cycles (2, 4, 6...)**: Claude writes test → Human implements

Follow Workflow A for odd cycles, Workflow B for even cycles.

At the start of each cycle, clearly state: "Cycle N: [Human/Claude] writes test, [Claude/Human] implements"

---

### After Each Cycle (All Modes):
- Update progress on the plan
- Move to the next step
- In Ping-Pong mode, announce whose turn it is for the next cycle

---

## Completion

After all steps are done:
1. Run the full test suite to confirm everything passes
2. Summarize what was implemented
3. List all commits created during this TDD session
4. Confirm feature is complete
