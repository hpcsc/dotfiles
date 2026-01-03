---
description: Commit staged changes with proper formatting and optional additional context
subtask: true
---

Run the commit agent to create a git commit for staged changes with a well-crafted commit message following conventional commit guidelines.

The agent will:
- Verify staged changes exist
- Analyze all staged changes to understand what and why
- Incorporate any additional context from $ARGUMENTS
- Draft a proper commit message following formatting rules
- Request user approval before committing
- Execute the commit with user approval

Trigger: @commit

