# One Event or Multiple Events?

Guidance on when a command should emit one event vs multiple events.

## Default: Prefer Single Events

**Safe default**: Record a single event per business operation.

**Why single events are usually better**:
- Clearer business narrative
- Less coupling for handlers
- Simpler projections
- Better documentation

## The "Reusability" Trap

Don't split events for code reuse.

**Bad - Splitting for reuse**:
```
Command: ReserveRoom
Events: RoomReserved + GuestsInformationUpdated  // Two events
```

Reading the stream, you'd think:
1. `RoomReserved` — user reserved a room
2. `GuestsInformationUpdated` — user later changed guest info

But actually both happened in the same operation! The stream lies.

**Good - Single cohesive event**:
```
Command: ReserveRoom
Event: RoomReserved { RoomId, Number, GuestsCount, MainGuest }
```

## When Multiple Events ARE Appropriate

### 1. Different Parts of a Process (Especially Optional)

When completing one step may trigger completion of a larger process:

```
Events:
  GuestCheckoutCompletionRecorded  // Individual checkout
  GroupCheckoutCompleted           // Last one triggered group completion
```

These are two distinct business facts.

### 2. Different Input Sources

Different entry points may warrant different event types:

```
RoomReserved              // Direct booking
RoomReservedTentatively   // Pending confirmation
RoomReservedFromBookingComImported  // External import
GroupRoomReservationMade  // Bulk booking
```

Each carries different business meaning.

## Warning Signs You're Over-Splitting

- Multiple events always appear together
- You need correlation IDs to understand which events belong together
- Projections must wait for "companion" events before processing
- Event names feel artificially granular

## Code Reuse vs Business Clarity

| Optimize For | Result |
|--------------|--------|
| Code size (sharing handlers) | Unclear business narrative |
| Business process clarity | Slightly more code, but cohesive |

**"Events should be as small as possible, but not smaller."**

A little healthy copy/paste in projections is better than forcing artificial event sharing.

## Internal vs External Events

- **Internal**: Fine-grained, optimized for your aggregate/process
- **External**: Enriched with context external consumers need

Event transformations let you maintain this separation.
