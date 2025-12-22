---
description: Commit staged changes with proper formatting and optional additional context
subtask: true
---

Follow below steps to create a git commit for staged changes:

- Run `git status` to verify changes are staged. If no staged changes are found, stop and show error to users
- Run `git diff --staged` and analyze ALL staged changes, identify what is being changed and why
- Use $ARGUMENTS as additional context if provided to enhance the commit description.
This should be incorporated into the description naturally without mentioning it came from user input
- Create commit message based on above analysis and following rules:
    - Separate subject from bondy with a blank line
    - Limit the subject line to 50 characters
    - Captalize the subject line
    - Do not end the subject line with a period
    - Use the imperative mood in the subject line
    - Wrap the body at 72 characters
    - Use the body to explain what and why (only if needed)
    - **Critical**: Must NEVER mention AI-generated content in the commit message

