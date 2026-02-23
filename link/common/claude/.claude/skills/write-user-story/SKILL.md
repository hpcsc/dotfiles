---
name: write-user-story
description: "Generate user stories for a new feature. Use when planning a feature, starting a new project, or when asked to write user stories. Triggers on: write user story, user stories for, plan this feature, spec out, break down feature."
user-invocable: true
---

# User Story Writer

Create detailed, actionable user stories suitable for implementation by a developer or AI agent.

---

## The Job

1. Receive a feature description from the user
2. Ask clarifying questions if the description is ambiguous (with lettered options)
3. Generate structured user stories based on answers
4. Save to `user-stories/[feature-name].md`
5. Ask if any stories need splitting, merging, reprioritizing, or if new stories are needed

**Important:** Do NOT start implementing. Just create the user stories.

---

## Important Restrictions

- NEVER include implementation details or technical solutions
- NEVER suggest code examples or programming approaches
- NEVER write test cases or mention testing frameworks
- NEVER provide technical architecture or design guidance
- Focus on user needs, business value, and acceptance criteria
- When the domain is inherently technical (APIs, infrastructure, developer tools), use precise domain terminology in acceptance criteria — this is not the same as prescribing implementation
- If asked about implementation, redirect to user story refinement

---

## Step 1: Clarifying Questions

Ask only critical questions where the initial prompt is ambiguous. If the user's description is sufficiently detailed, reduce to 1-2 targeted questions or proceed directly and note assumptions in the Open Questions section.

Tailor every question to the specific feature described. Never ask generic questions like "What is the scope?" — instead ask something derived from the feature, like "Should the rate limiter apply per-endpoint or per-tenant?"

Focus on:

- **Problem/Goal:** What problem does this solve?
- **Core Functionality:** What are the key actions?
- **Scope/Boundaries:** What should it NOT do?
- **Success Criteria:** How do we know it's done?
- **User Personas:** Who are the different types of users?

### Format Questions Like This:

Given a feature request like "Add rate limiting to our API":

```
1. Which consumers should rate limiting apply to?
   A. External/public API consumers only
   B. All consumers including internal services
   C. Specific tenant tiers (e.g., free vs. paid)
   D. Other: [please specify]

2. What should happen when a consumer exceeds their limit?
   A. Reject with an error and retry guidance
   B. Queue excess requests and process them later
   C. Throttle (slow down) rather than reject
   D. Other: [please specify]

3. Should limits be the same for everyone or configurable?
   A. Single global limit for all consumers
   B. Configurable per tenant/consumer
   C. Tiered limits based on plan level
   D. Other: [please specify]
```

This lets users respond with "1A, 2A, 3B" for quick iteration. Remember to indent the options.

---

## Step 2: Decompose into User Stories

Apply the **Elephant Carpaccio** technique: break the problem into the thinnest possible vertical slices that still deliver end-to-end value. Each slice should be a complete, working feature that a user can interact with.

Every user story must follow the **INVEST** criteria:

- **Independent:** Can be developed without dependencies on other stories
- **Negotiable:** Details can be discussed and refined
- **Valuable:** Delivers clear value to the end user
- **Estimable:** Clear enough scope to understand complexity
- **Small:** Can be completed in a single focused session
- **Testable:** Has clear acceptance criteria

### Story Sizing

A well-sized story should have 3-7 acceptance criteria. If you have more than 7, the story likely needs splitting. If fewer than 2, it may be too granular to stand alone.

### Prioritize and Sequence Stories By:

1. Risk reduction (tackle unknowns early)
2. User value delivery
3. Dependencies between stories
4. Learning opportunities

List stories in recommended implementation order. When a story depends on another, note the dependency explicitly.

---

## Step 3: Document Structure

Generate the document with these sections:

### 1. Overview
Brief description of the feature and the problem it solves.

### 2. Goals
Specific, measurable objectives (bullet list).

### 3. User Stories

Each story needs:
- **Title:** Short descriptive name
- **Description:** "As a [user], I want [feature] so that [benefit]"
- **Acceptance Criteria:** Verifiable checklist of what "done" means — how we verify this story works
- **Context** *(optional)*: Background information helpful for the implementer — domain knowledge, related behavior elsewhere in the system, or why this story exists. Do not prescribe solutions.
- **Depends on** *(optional)*: References to stories that must be completed first

**Format:**
```markdown
### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Specific verifiable criterion
- [ ] Another criterion

**Context:** [Optional background for the implementer]

**Depends on:** [Optional, e.g., US-001]
```

**Important:**
- Acceptance criteria must be verifiable, not vague. "Works correctly" is bad. "Consumer receives a 429 response with retry timing when their request rate exceeds the configured limit" is good.
- Acceptance criteria describe observable behavior — what the user sees, what the system responds with, what state changes. They are not implementation instructions.

### 4. Non-Goals (Out of Scope)
What this feature will NOT include. Critical for managing scope.

### 5. Open Questions
Remaining questions, areas needing clarification, and any assumptions made if clarifying questions were skipped.

---

## Quality Standards

- Each story should be small enough for a single focused session (3-7 acceptance criteria)
- Stories should build incrementally toward the full solution
- Avoid technical tasks disguised as user stories — every story should deliver value a user or operator can observe
- Include edge cases and error scenarios as separate stories when significant
- Consider different user personas and their unique needs
- The complete set of stories must address the original problem without gaps or overlaps

---

## Writing for Implementers

The reader may be a junior developer or AI agent. Therefore:

- Be explicit and unambiguous in descriptions and acceptance criteria
- Avoid jargon or explain it
- Use concrete examples where helpful
- Use the optional **Context** field to provide domain background that helps the implementer understand *why* without prescribing *how*

---

## Output

- **Format:** Markdown (`.md`)
- **Location:** `user-stories/`
- **Filename:** `[feature-name].md` (kebab-case)

---

## Iteration

After generating the initial set of stories, ask the user:

- Do any stories need splitting or merging?
- Should any stories be reprioritized?
- Are there missing stories or edge cases to add?

Update the file in place based on feedback.

---

## Example

```markdown
# API Rate Limiting

## Overview

Add rate limiting to the public API to prevent abuse and ensure fair usage across tenants. Requests exceeding the configured threshold are rejected with a standard error response, and usage is tracked for observability.

## Goals

- Protect the API from excessive traffic by a single tenant
- Return clear, standards-compliant responses when limits are hit
- Make rate limits configurable per tenant without redeployment
- Provide visibility into rate limit events via monitoring

## User Stories

### US-001: Enforce per-tenant request limits
**Description:** As an API operator, I want incoming requests counted against a per-tenant limit so that no single tenant can monopolize capacity.

**Acceptance Criteria:**
- [ ] Each tenant's requests are tracked against a per-minute limit
- [ ] Default limit is 100 requests per minute
- [ ] Requests within the limit proceed with no noticeable delay

### US-002: Reject over-limit requests with clear feedback
**Description:** As an API consumer, I want a clear error response when I exceed my rate limit so that I know to back off and when to retry.

**Acceptance Criteria:**
- [ ] Over-limit requests receive a 429 status code
- [ ] Response body includes a human-readable error message
- [ ] Response includes how many seconds until the consumer can retry
- [ ] No information about other tenants' limits or usage is leaked

**Depends on:** US-001

### US-003: Allow per-tenant limit overrides
**Description:** As an API operator, I want to set custom rate limits for specific tenants so that premium tenants get higher throughput without affecting others.

**Acceptance Criteria:**
- [ ] Operators can set a custom limit for any tenant
- [ ] Custom limits take effect without restarting the service
- [ ] Tenants without a custom limit use the default
- [ ] Operators can remove a custom limit to revert to the default

**Context:** Premium tenants are identified by their API key tier. The current tenant configuration already supports per-tenant settings for other features.

**Depends on:** US-001

### US-004: Monitor rate limit events
**Description:** As an API operator, I want to see when tenants hit their rate limits so that I can identify abuse patterns and adjust limits proactively.

**Acceptance Criteria:**
- [ ] Each 429 response is recorded as a rate limit event with the tenant identifier
- [ ] Operators can view rate limit events per tenant over time
- [ ] Operators can set up alerts when a tenant exceeds a threshold of 429s

**Depends on:** US-002

### US-005: Handle burst traffic gracefully
**Description:** As an API consumer, I want short bursts above my limit to be tolerated so that legitimate traffic spikes don't immediately trigger errors.

**Acceptance Criteria:**
- [ ] A small burst allowance above the per-minute limit is permitted
- [ ] Sustained traffic above the limit is still rejected
- [ ] Burst allowance is documented so consumers know what to expect

**Context:** Many API consumers send requests in batches rather than at a steady rate. Without burst tolerance, legitimate batch operations would be rejected even if average usage is well within limits.

**Depends on:** US-001

## Non-Goals

- No user-facing dashboard for consumers to view their own usage
- No automatic banning or escalation on repeated violations
- No per-endpoint rate limits (tenant-level only for now)

## Open Questions

- Should rate limit usage headers be included on every response, not just 429s?
- What is the right burst allowance — a fixed number of extra requests or a percentage of the limit?
```

---

## Checklist

Before saving:

- [ ] Asked clarifying questions tailored to the feature (or noted assumptions if skipped)
- [ ] Incorporated user's answers
- [ ] User stories are small (3-7 acceptance criteria) and follow INVEST criteria
- [ ] Acceptance criteria are verifiable and describe observable behavior
- [ ] No implementation details or technical solutions included
- [ ] Non-goals section defines clear boundaries
- [ ] Stories are listed in recommended implementation order with dependencies noted
- [ ] Saved to `user-stories/[feature-name].md`
- [ ] Asked user if stories need splitting, merging, or reprioritizing
