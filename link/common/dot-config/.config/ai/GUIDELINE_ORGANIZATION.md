# Guideline Organization

This document describes how to organize development guidelines so they can be shared across multiple AI coding tools (Claude Code, OpenCode, etc.) and their agents/skills, avoiding duplication while maintaining usability.

## Core Principle: Single Source of Truth

**Guidelines are the source of truth. Agents and skills reference them.**

```
Guidelines (Detailed)
    ↓
    ├── Agents (Read full guidelines dynamically)
    │   ├── Claude Code (~/.claude/agents/)
    │   └── OpenCode (~/.config/opencode/agent/)
    └── Skills (Contain checklist/summary version)
        └── Claude Code (~/.claude/skills/)
```

## Directory Structure

```
~/.config/ai/
└── guidelines/
    └── <domain>/           # e.g., go, python, security, api-design
        ├── <topic-1>.md    # e.g., naming-patterns.md
        ├── <topic-2>.md    # e.g., testing-patterns.md
        └── <topic-3>.md    # e.g., architecture-principles.md

# Claude Code
~/.claude/
├── agents/
│   └── <agent-name>.md     # e.g., go-expert.md, api-designer.md
└── skills/
    └── <skill-name>        # e.g., test-go, review-api, refactor-python

# OpenCode
~/.config/opencode/
└── agent/
    └── <agent-name>.md     # e.g., go-expert.md, api-designer.md
```

## Three-Layer Pattern

### Layer 1: Guidelines (Full Documentation)

**Location**: `~/.config/ai/guidelines/<domain>/<topic>.md`

**Purpose**: Comprehensive, detailed documentation of patterns and practices.

**Content Structure**:
- Core principles with detailed explanations
- Step-by-step implementation guidelines
- Multiple examples (✅ Good vs ❌ Bad)
- Reasoning and trade-offs
- Edge cases and anti-patterns
- Extended examples and scenarios

**Length**: As long as needed (hundreds to thousands of lines)

**What to include**:
- Comprehensive explanations
- Multiple detailed examples
- "Why" behind each pattern
- Edge cases and trade-offs
- Anti-patterns with detailed analysis
- Extended scenarios
- Background and reasoning

### Layer 2: Agents (References Full Guidelines)

**Location**:
- Claude Code: `~/.claude/agents/<agent-name>.md`
- OpenCode: `~/.config/opencode/agent/<agent-name>.md`

**Purpose**: Instruct the agent to read and apply full guidelines.

**Content Structure**:
```markdown
---
description: <Role description>
---

<Agent persona and expertise description>

When working on <relevant tasks>, **read and apply patterns from the
following guidelines**:

## Core Guidelines

1. **<Guideline Name>** (`~/.config/ai/guidelines/<domain>/<file>.md`)
   - Brief bullet points of what's in the guideline (signposts)
   - NOT a duplication of the content

2. **<Another Guideline>** (`~/.config/ai/guidelines/<domain>/<file>.md`)
   - Brief bullet points (signposts)

## Application Strategy

- **Always read relevant guidelines** before implementing
- **Reference specific guidelines** when explaining decisions
- **Apply patterns consistently**
```

**Length**: Short (50-100 lines)

**What to include**:
- List of guideline file paths
- Brief description of what's in each guideline (1-3 bullets)
- Application strategy (when to read guidelines)
- Role or persona description

**What to exclude**:
- Pattern details (those are in guidelines)
- Examples (those are in guidelines)
- Checklists (those are in skills)

**Key Points**:
- Agent prompt **lists guideline file paths**
- Agent prompt **does NOT duplicate guideline content**
- Agent **reads guidelines dynamically** when working on relevant tasks
- Bullet points are **signposts**, not **content**

### Layer 3: Skills (Summary/Checklist Version)

**Location**: `~/.claude/skills/<skill-name>` (shared by Claude Code and OpenCode)

**Purpose**: Quick-reference summary for the skill's specific task.

**Content Structure**:
```markdown
---
description: <Brief task description>
---

## Quick Reference

[High-level summary in 3-5 bullet points]

## Checklist

Before <task>, verify:
- [ ] Item 1
- [ ] Item 2
- [ ] Item 3

## Key Patterns

Pattern 1: Brief description
Pattern 2: Brief description

## Common Pitfalls

- ❌ Pitfall 1
- ❌ Pitfall 2

## For Full Details

See: ~/.config/ai/guidelines/<domain>/<file>.md
```

**Length**: Very short (30-50 lines)

**What to include**:
- Task-specific summary (3-5 bullets)
- Actionable checklist
- Key patterns (one-line each)
- Common pitfalls (brief)
- Link to full guideline

**What to exclude**:
- Detailed explanations (those are in guidelines)
- Multiple examples (those are in guidelines)
- Implementation details (those are in guidelines)

## How It Works Together

### Example Workflow

#### 1. Full Guideline (`~/.config/ai/guidelines/<domain>/<topic>.md`)

```markdown
# <Topic> Title

## Core Principle

[Main principle explained in detail]

[Hundreds or thousands of lines of detailed content]
- Comprehensive explanations
- Multiple examples for each concept
- Anti-patterns with detailed explanations
- Edge cases and trade-offs
- etc.
```

#### 2. Agent Reference

**Claude Code** (`~/.claude/agents/<agent-name>.md`):
```markdown
---
description: <Agent role and expertise>
---

<Agent persona description>

## Core Guidelines

1. **<Topic>** (`~/.config/ai/guidelines/<domain>/<topic>.md`)
   - Signpost bullet 1 (brief, not detailed)
   - Signpost bullet 2 (brief, not detailed)

## Application Strategy

- **Always read relevant guidelines** before implementing
```

**OpenCode** (`~/.config/opencode/agent/<agent-name>.md`):
```markdown
---
description: <Agent role and expertise>
mode: all
---

<Agent persona description>

When working on <relevant tasks>, **read and apply patterns from the
following guidelines**:

## Core Guidelines

1. **<Topic>** (`~/.config/ai/guidelines/<domain>/<topic>.md`)
   - Signpost bullet 1 (brief, not detailed)
   - Signpost bullet 2 (brief, not detailed)

## Application Strategy

- **Always read relevant guidelines** before implementing
```

#### 3. Skill Summary (`~/.claude/skills/<skill-name>`)

```markdown
---
description: <Task description>
---

## Core Principle

[Main principle in 1-2 sentences]

## Quick Checklist

- [ ] Key item 1
- [ ] Key item 2

## Key Patterns

- Pattern 1: One-line description
- Pattern 2: One-line description

## For Full Details

See: ~/.config/ai/guidelines/<domain>/<topic>.md
```

### When User Invokes Skill (Both Claude Code and OpenCode)

1. **Skill provides quick context**: Checklist and summary
2. **Skill invokes agent**: Launches appropriate agent (from respective tool's agent directory)
3. **Agent reads full guideline**: Reads relevant `.md` files from `~/.config/ai/guidelines/`
4. **Agent applies patterns**: Uses detailed knowledge from guidelines
5. **Agent cites guidelines**: References specific sections when explaining

### When Agent is Used Directly

1. **Agent is selected**: User selects agent for the task
2. **Agent reads full guideline**: Reads relevant `.md` files from `~/.config/ai/guidelines/`
3. **Agent applies patterns**: Uses detailed knowledge from guidelines
4. **Agent cites guidelines**: References specific sections when explaining

## Benefits

### 1. No Duplication

- Guidelines written **once** in `~/.config/ai/guidelines/`
- Agents **reference** guidelines (don't duplicate) across all tools
- Skills **summarize** guidelines (don't duplicate)

### 2. Easy Updates

- Update guideline → All agents (Claude Code, OpenCode, etc.) immediately see changes
- Update guideline → Skills may need checklist updates
- No need to sync multiple copies across different tools

### 3. Cross-Tool Consistency

- Same guidelines used by Claude Code and OpenCode
- Consistent patterns applied regardless of tool
- Share expertise across different AI coding assistants

### 4. Appropriate Detail Level

- **Guidelines**: Comprehensive for learning and reference
- **Agents**: Signposts pointing to guidelines (work across tools)
- **Skills**: Quick reference for immediate use (tool-specific)

### 5. Scalability

Adding a new guideline:

1. Write full guideline **once** in `~/.config/ai/guidelines/<domain>/`
2. Add reference to agent(s) in **both** Claude Code and OpenCode
3. Create skill summary for Claude Code if there's a common task
4. Done - guideline automatically works across all tools

## Adding New Guidelines

### Step 1: Create Full Guideline

```bash
~/.config/ai/guidelines/<domain>/<topic>.md
```

**Template Structure**:
```markdown
# <Topic> Title

## Core Principle

[Main idea in 1-2 sentences]

## Detailed Content

[Comprehensive explanation with examples]

## Implementation Guidelines

[Step-by-step instructions]

## Examples

### Example 1: <Scenario>

❌ **Bad:**
[Code/content example]

✅ **Good:**
[Code/content example]

### Example 2: <Another Scenario>

[More examples]

## Common Anti-Patterns

### Anti-Pattern 1: <Name>

**Problem:**
[Description of the problem]

**Why It's Wrong:**
[Detailed explanation]

**Fix:**
[How to do it correctly]

## Quick Checklist

- [ ] Item 1
- [ ] Item 2
- [ ] Item 3

## Summary

[Key takeaways]
```

### Step 2: Reference in Agent(s)

Edit or create agent files in **both** Claude Code and OpenCode:

**Claude Code** (`~/.claude/agents/<agent-name>.md`):
```markdown
---
description: <Agent role and expertise>
---

<Agent persona and expertise description>

When working on <relevant tasks>, **read and apply patterns from the
following guidelines**:

## Core Guidelines

1. **<Topic>** (`~/.config/ai/guidelines/<domain>/<topic>.md`)
   - Brief signpost 1 (what's in the guideline)
   - Brief signpost 2 (what's in the guideline)

[... other guidelines ...]

## Application Strategy

- **Always read relevant guidelines** before implementing
- **Reference specific guidelines** when explaining decisions
- **Apply patterns consistently** across all work
```

**OpenCode** (`~/.config/opencode/agent/<agent-name>.md`):
```markdown
---
description: <Agent role and expertise>
mode: all
---

<Agent persona and expertise description>

When working on <relevant tasks>, **read and apply patterns from the
following guidelines**:

## Core Guidelines

1. **<Topic>** (`~/.config/ai/guidelines/<domain>/<topic>.md`)
   - Brief signpost 1 (what's in the guideline)
   - Brief signpost 2 (what's in the guideline)

[... other guidelines ...]

## Application Strategy

- **Always read relevant guidelines** before implementing
- **Reference specific guidelines** when explaining decisions
- **Apply patterns consistently** across all work
```

**Note**: The content is nearly identical, but OpenCode agents include a `mode:` field in the frontmatter.

### Step 3: Create Skill Summary (Optional)

If there's a common task that users will repeatedly perform, create a skill:

```bash
~/.claude/skills/<skill-name>
```

**Template Structure**:
```markdown
---
description: <Brief task description (3-5 words)>
---

## Quick Reference

[Brief summary in 3-5 bullet points]

## Checklist

Before <performing task>:
- [ ] Key item 1
- [ ] Key item 2
- [ ] Key item 3

## Key Patterns

- Pattern 1: One-line description
- Pattern 2: One-line description

## Common Pitfalls

- ❌ Pitfall 1: Brief description
- ❌ Pitfall 2: Brief description

## For Full Details

See: ~/.config/ai/guidelines/<domain>/<topic>.md
```

## What Goes Where

### Guideline (Full Documentation)

**Purpose**: Comprehensive reference

**Include**:
- Detailed explanations
- Multiple examples
- Reasoning ("why")
- Edge cases
- Trade-offs
- Anti-patterns with analysis

**Exclude**:
- Quick checklists only (include comprehensive ones)
- Summaries only (include detailed content)

### Agent (Guideline Index)

**Purpose**: Point agent to guidelines

**Include**:
- Guideline file paths
- Brief signpost bullets (what's in each guideline)
- When to read guidelines
- Agent role/persona

**Exclude**:
- Pattern details
- Examples
- Checklists
- Duplication of guideline content

### Skill (Quick Reference)

**Purpose**: Immediate task guidance

**Include**:
- Brief summary
- Actionable checklist
- One-line key patterns
- Brief common pitfalls
- Link to full guideline

**Exclude**:
- Detailed explanations
- Multiple examples
- Implementation details
- Content that's already in guidelines

## Real-World Example

### Guideline: `testing-patterns.md` (1600+ lines)

Location: `~/.config/ai/guidelines/go/testing-patterns.md`

Contains:
- Detailed explanation of testing principles
- Fidelity, Resilience, Precision with comprehensive examples
- Multiple examples for each concept
- Decision trees
- Anti-patterns with detailed analysis
- Test helper patterns
- Table-driven test examples
- etc.

### Agents: `go-expert.md` (~40 lines each)

**Claude Code** (`~/.claude/agents/go-expert.md`):
```markdown
## Core Guidelines

2. **Testing Patterns** (`~/.config/ai/guidelines/go/testing-patterns.md`)
   - Test structure and organization
   - Test double co-location with real implementations
   - Testing observable behaviors (not implementation details)
```

**OpenCode** (`~/.config/opencode/agent/go-expert.md`):
```markdown
---
description: A senior Go engineer specializing in clean architecture...
mode: all
---

## Core Guidelines

2. **Testing Patterns** (`~/.config/ai/guidelines/go/testing-patterns.md`)
   - Test structure and organization
   - Test double co-location with real implementations
   - Testing observable behaviors (not implementation details)
```

Both agents reference the **same guideline file**.

### Skill: `test-go` (~40 lines)

Location: `~/.claude/skills/test-go` (shared by both Claude Code and OpenCode)

Contains:
- Core principle (1 sentence)
- Quick checklist (5 items)
- Three essential qualities (brief)
- Key anti-patterns (brief bullets)
- Link to full guideline

**Note**: Both Claude Code and OpenCode read skills from the same location.

## Guidelines for Different Domains

This structure works for any domain, not just programming languages:

### Programming Languages

```
~/.config/ai/guidelines/
├── go/
│   ├── naming-patterns.md
│   ├── testing-patterns.md
│   └── architecture-principles.md
├── python/
│   ├── type-hints.md
│   └── testing-patterns.md
└── typescript/
    ├── type-system.md
    └── react-patterns.md
```

### Cross-Cutting Concerns

```
~/.config/ai/guidelines/
├── security/
│   ├── authentication.md
│   ├── input-validation.md
│   └── secret-management.md
├── api-design/
│   ├── rest-apis.md
│   ├── graphql-apis.md
│   └── versioning.md
└── documentation/
    ├── code-comments.md
    ├── readme-structure.md
    └── api-documentation.md
```

### Domain-Specific

```
~/.config/ai/guidelines/
├── event-sourcing/
│   ├── aggregate-design.md
│   ├── event-modeling.md
│   └── projection-patterns.md
├── data-engineering/
│   ├── pipeline-design.md
│   ├── data-quality.md
│   └── schema-evolution.md
└── devops/
    ├── cicd-patterns.md
    ├── infrastructure-as-code.md
    └── observability.md
```

## Summary

**Key Principle**: Write it once, reference it everywhere.

1. **Guidelines** = Full documentation (comprehensive, shared across all tools)
2. **Agents** = Signposts to guidelines (brief references, tool-specific locations)
3. **Skills** = Quick reference checklists (actionable summaries, shared across tools)

### When Adding New Guidelines

1. Write comprehensive guideline **once** in `~/.config/ai/guidelines/<domain>/<topic>.md`
2. Add reference to agent(s) in:
   - Claude Code: `~/.claude/agents/<agent-name>.md`
   - OpenCode: `~/.config/opencode/agent/<agent-name>.md`
3. Create skill summary in `~/.claude/skills/<skill-name>` if there's a common task
4. All components across all tools point to the same source of truth

### Content Distribution

- **Comprehensive explanations** → Guidelines only (shared by all tools)
- **Examples and anti-patterns** → Guidelines only (shared by all tools)
- **Implementation details** → Guidelines only (shared by all tools)
- **Signposts to guidelines** → Agents only (tool-specific locations, but point to same guidelines)
- **Quick checklists** → Skills only (shared by all tools, with link to guidelines)
- **One-line summaries** → Skills only (shared by all tools)

### Cross-Tool Benefits

- **Single source of truth**: Guidelines in `~/.config/ai/guidelines/` work with both Claude Code and OpenCode
- **Consistent patterns**: Same guidelines ensure consistent code quality regardless of which tool is used
- **Easy maintenance**: Update guideline once, all tools immediately benefit
- **Flexibility**: Use the right tool for the job while maintaining consistent coding standards

This structure maintains a single source of truth while providing appropriate detail levels for different use cases, making it easy to add new guidelines that can be shared by multiple AI coding tools and their agents/skills.
