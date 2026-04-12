# Business Capabilities vs Business Processes

How to distinguish capabilities from processes during event modeling.

---

## Definitions

### Business Capability (the WHAT)

A business capability describes **what** an organization can do. Capabilities are stable over long periods — they rarely change even as the organization evolves.

Examples:
- Group Management
- Member Recruitment
- Task Management
- Access Control

### Business Process (the HOW)

A business process describes **how** an organization realizes a capability. Processes are organization-specific and evolve over time.

A business process has:
- A **trigger** (what starts it)
- A **sequence of steps** (what happens, in order)
- A **business outcome** (the result that matters to stakeholders)

Examples:
- Member Onboarding: member generates invite code → shares out-of-band → invitee redeems code → invitee becomes member
- Group Formation: user creates group → system auto-creates default list → workspace is ready

---

## Why This Matters for Event Modeling

Event models are organized around business processes — timelines of events that achieve an outcome. If you model capabilities instead of processes, you end up with:

- Flat lists of commands/events with no narrative flow
- No clear sequence or trigger-to-outcome arc
- Difficulty identifying automations (reactors, process managers) that bridge steps

**Capabilities** help you identify bounded contexts and organize the model.
**Processes** give you the timelines to model.

---

## Common Mistakes

### Listing capabilities as processes

| Looks Like a Process | Actually a Capability | Real Process Underneath |
|---|---|---|
| "Item Workflow" | Task Management | Collaborative Task Completion: member adds item → assigns → completes |
| "List Management" | List Organization | (may be a single command, not a multi-step process) |
| "Group Lifecycle" | Group Management | Group Formation: user creates group → default list auto-created |

**Detection**: If your "process" has no clear sequence of steps — just a collection of things the system can do — it's a capability.

### Listing infrastructure as processes

| Looks Like a Process | Actually Is | Where It Belongs |
|---|---|---|
| "Real-time Notification" | Event handler (infrastructure) | Appears as a reactor in the event model |
| "Activity Feed" | Read model (projection) | Appears as a view in the event model |
| "Group Setup Automation" | Process manager | Appears as an automation within the Group Formation process |

**Detection**: If no human actor triggers it and it has no standalone business outcome, it's infrastructure that belongs inside another process's model.

---

## The Relationship

```
Capability (WHAT)
  └── Process 1 (HOW — one way to realize the capability)
  └── Process 2 (HOW — another way, or a variant)
```

A single capability may have multiple processes. A process may span multiple capabilities.

Example:
```
Capability: Member Recruitment
  └── Process: Member Onboarding via Invite Code
  └── Process: Member Onboarding via Direct Add (future)

Capability: Group Management
  └── Process: Group Formation (spans into Task Management via auto-created list)
  └── Process: Group Renaming
```

---

## Checklist

When identifying processes for event modeling:

1. ✅ Does it have a clear trigger?
2. ✅ Does it have a sequence of steps (not just one command)?
3. ✅ Does it produce a business outcome a stakeholder cares about?
4. ✅ Could you walk a stakeholder through it as a story?
5. ❌ Is it just "things the system can do"? → That's a capability
6. ❌ Is it triggered only by other events with no human actor? → That's an automation, model it inside the process it supports
