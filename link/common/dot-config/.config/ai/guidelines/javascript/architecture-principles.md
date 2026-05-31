# JavaScript Architecture Principles

## Core Principles

### 1. Module Separation by Responsibility
Every module owns one concern. If you need to import more than 3–4 modules to understand a single module's job, it's doing too much.

```
viewer/
├── config.js      — constants, thresholds, style maps (zero deps)
├── store.js       — state factory (zero deps)
├── bus.js         — event pub/sub (zero deps)
├── layout.js      — pure geometry, no DOM (zero deps on DOM)
├── renderer.js    — SVG element creation, no event logic
├── interaction.js — pointer events, drag, pan, zoom
├── ui.js          — tooltip, detail panel, minimap, keyboard, delegation
├── model.js       — data operations, network calls
└── viewer.js      — entry point, wiring, orchestration
```

### 2. Stateless Pure Functions Over Objects for Logic
Pure functions (no DOM, no side effects, no `this`) are unit-testable and refactorable. Extract them before they grow inside a component.

```
✅  layout.js   — computeArrowD, isCrossBoundary, buildTree — all pure
✅  renderer.js — svgRect, svgText — create and return elements, no side effects
❌  DON'T put coordinate math inside a click handler
```

### 3. Namespace Pattern, Not Classes
Group related functions under a `const Namespace = { fn1, fn2 }` export. Avoid `class` — JavaScript classes encourage mutable shared state and `this` confusion.

```js
// ✅ Good — plain functions, no `this`, easy to test
export const Layout = {
  buildTree,
  computeLayout,
  isCrossBoundary,
};

// ❌ Avoid — introduces `this`, makes destructuring awkward
export class Layout { ... }
```

### 4. Centralized State via Factory
Keep all mutable state in a single store object created by a factory function. Pass the store explicitly to functions — no singletons, no module-level globals.

```js
export function createStore() {
  return {
    nodes: [],
    edges: [],
    viewport: { offsetX: 0, offsetY: 0, zoomScale: 1 },
    interaction: { drag: null, pan: null, ... },
    dom: { svg: null, tooltip: null, ... },
  };
}
```

### 5. Event Bus for Cross-Cutting Concerns
Use a lightweight pub/sub bus to decouple modules that need to react to the same event without direct imports.

```js
bus.emit('viewport:changed', { store });
bus.emit('data:changed', { store });
bus.emit('diagram:rendered', { store, dims });
```

**When to use the bus:**
- One module triggers something another module owns (viewport → minimap)
- Multiple subscribers need the same event (model sets data → stats update + re-render)

**When NOT to use the bus:**
- Direct function call is simpler (a helper → a DOM query)
- The two modules are already coupled by design

### 6. Explicit Store Passing, No Imports
Modules receive the store as a parameter, not via import. This makes dependencies visible and modules testable.

```js
// ✅ Good — store is a parameter
function applyViewport(store) { ... }

// ❌ Avoid — implicit global
function applyViewport() { doSomethingWith(window.store); }
```

### 7. Orchestration Layer in the Entry Point
The entry point (e.g., `viewer.js`) wires everything together — creates the store, subscribes to events, and calls init functions. Individual modules don't know about each other's existence.

```js
// viewer.js — the only file that imports all modules
bus.on('diagram:rendered', ({ store: s }) => {
  Interaction.applyViewport(s);
  UI.renderActorAnnotations(s);
});
```
