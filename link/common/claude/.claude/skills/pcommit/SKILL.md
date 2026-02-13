---
disable-model-invocation: true
---

Create a git commit for staged changes with a well-crafted commit message: $ARGUMENTS

## Process

### Step 1: Verify Staged Changes

Run `git status` to check for staged changes.

**If no staged changes found**: Stop immediately and report:
```
Error: No staged changes found. Stage your changes with `git add` before committing.
```

### Step 2: Analyze Changes

Run `git diff --staged` and analyze ALL staged changes:
- What files are modified/added/deleted
- What is the nature of the change (new feature, bug fix, refactor, test, etc.)
- Why this change was made (infer from code context)

### Step 3: Incorporate Context

If additional context was provided via $ARGUMENTS:
- Use it to enhance the commit description
- Incorporate it naturally into the message

### Step 4: Draft Commit Message

**Subject Line:**
- Separate from body with a blank line
- Limit to 50 characters
- Capitalize the first word
- No period at the end
- Use imperative mood ("Add" not "Added", "Fix" not "Fixed")

**Body (only if needed):**
- Wrap at 72 characters
- Explain WHAT changed and WHY
- Skip if the subject is self-explanatory

**Critical Rules:**
- NEVER mention AI, Claude, or generated content
- NEVER add signatures like "Co-Authored-By: Claude"
- NEVER add "Generated with..." or similar
- NEVER include generic file lists in commit messages
- Include file paths only when they provide essential context
- Write as a human developer would

### Step 5: Request User Approval

Present the drafted commit message and ask for approval:
- Approve
- Edit message (let user provide changes)
- Cancel

**NEVER commit without explicit user approval.**

### Step 6: Execute Commit (Only After Approval)

Use HEREDOC format:
```bash
git commit -m "$(cat <<'EOF'
Subject line here

Body text here if needed,
wrapped at 72 characters.
EOF
)"
```

### Step 7: Confirm

After successful commit, show:
- The commit message used
- The commit hash
- Files included in the commit
