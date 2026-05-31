# JavaScript Development Workflow

## When Creating a New Module

### 1. Identify the Responsibility
Ask: "What one thing does this module own?" If the answer needs "and," split it.

```
✅  "Creates SVG elements from layout positions"        → renderer.js
✅  "Handles pointer events for drag, pan, and zoom"    → interaction.js
✅  "Manages tooltip, detail panel, minimap, keyboard"   → ui.js
❌  "Renders the diagram AND handles click events"       → split into renderer + interaction
```

### 2. Define the Public API
List the functions the module exports. Keep the surface area small.

```js
// interaction.js — only 4 exported functions
export const Interaction = {
  initEventListeners,
  screenToDiagram,
  applyViewport,
  fitToView,
};
```

### 3. Decide What the Module Imports
A module should import only what it needs. Prefer passing `store` as a parameter over importing the store module.

```js
// ✅ Good — imports config constants only
import { L, DRAG_THRESHOLD } from './config.js';

// ✅ Good — imports bus for emitting events
import { bus } from './bus.js';
```

### 4. Write the Functions
- Keep functions small (20–40 lines max)
- Pure functions first, DOM side effects last
- One level of abstraction per function

### 5. Export and Integrate
Add the export to the entry point and wire any event subscriptions there.

## When Adding a Feature

### 1. Check if It Changes State
If yes, update the store factory to include the new state field.

### 2. Check if It Needs to React to Events
If yes, subscribe in the entry point (`viewer.js`), not inside the module.

### 3. Check if It Emits Events
If yes, emit via the bus so other modules can react without importing your module.

### 4. Check if It Queries the DOM
If yes, store the reference in `store.dom` at init time, not at render time.

## When Refactoring

### 1. Extract pure functions first
Move coordinate/string/arithmetic logic into pure functions before touching event handlers.

### 2. Replace innerHTML with DOM API
Use `createElementNS`/`appendChild` for SVG and trusted content. Reserve `innerHTML` for complex UIs (tooltip, detail panel) where the content is escaped via `esc()`.

### 3. Replace per-element listeners with delegation
Use `closest()` on delegated SVG listeners instead of re-attaching handlers after every render.
