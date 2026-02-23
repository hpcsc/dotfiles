---
name: decompose-to-tasks
description: "Decompose a user story into ordered implementation tasks with codebase references. Use when breaking down a story, planning tasks, or preparing work for implementation. Triggers on: decompose story, break down story, plan tasks, task breakdown, decompose to tasks."
user-invocable: true
argument-hint: <user-story-file-or-description>
---

# Task Decomposition

Break a user story into an ordered list of implementation tasks with codebase references, ready for `/implement` or `/tdd`.

**Important:** Do NOT start implementing. Just create the task list.

---

## Workflow

### 1. Receive Input

Accept the user story from `$ARGUMENTS` — this can be a file path, inline text, or pasted block.

### 2. Clarifying Questions

Ask only if the input is ambiguous or lacks enough detail to decompose. If the user story is already well-specified (has clear acceptance criteria), skip or limit to 1-2 questions.

Focus on:
- **Scope boundaries:** What should the first iteration include vs. defer?
- **Dependencies:** Are there prerequisites or existing work in progress?
- **Testing strategy:** Are there integration points that need special consideration?
- **Ordering preferences:** Does the user want risk-first, value-first, or dependency-first ordering?

Format questions for quick response:

```
1. Which acceptance criteria should be tackled first?
   A. Start with the core happy path (US-001, US-002)
   B. Start with the riskiest unknown (US-003)
   C. Follow the dependency order as written
   D. Other: [please specify]

2. Are there any existing patterns in the codebase we should align with?
   A. Yes — I'll point you to the relevant code
   B. No — this is a new area
   C. Not sure — please explore and recommend
   D. Other: [please specify]
```

This lets users respond with "1A, 2C" for quick iteration. Indent the options.

### 3. Delegate to Agent

Delegate the core decomposition work to the `decompose-to-tasks` agent using the Task tool:

```
Decompose the following user story into implementation tasks:

[user story content here]

[Include any clarified scope, ordering preferences, or constraints from the user's answers]
```

The agent will:
- Explore the codebase to identify affected files, patterns, and domain types
- Decompose into baby-step tasks ordered by dependency
- Save to `tasks/[story-name].md`
- Return a summary of the tasks created

### 4. Present Results

Show the user the task summary returned by the agent, including:
- File path where the task list was saved
- Ordered list of task titles
- Key codebase findings

### 5. Iterate

After presenting the task list, ask the user:

- Are any tasks too large and need splitting?
- Should any tasks be merged?
- Should the ordering change?
- Are there missing tasks or edge cases?

If the user requests changes, delegate back to the agent with the specific feedback to update the file in place.
