# JavaScript State Management

## The Store Pattern

All mutable state lives in a single object created by a factory function.

```js
export function createStore() {
  return {
    nodes: [],
    edges: [],
    modelName: "",
    layoutPositions: {},
    nodeOffsets: {},
    hiddenContexts: {},
    nodeById: new Map(),
    viewport: { offsetX: 0, offsetY: 0, zoomScale: 1 },
    interaction: {
      drag: null,
      pan: null,
      touch: null,
      highlighted: {},
      selectedNodeId: null,
      inlineEdit: null,
      ctxMenu: null,
      suppressDetailClick: false,
    },
    dom: {
      svg: null,
      tooltip: null,
      // ... all DOM references
    },
  };
}
```

### Rules

1. **Never mutate store outside a module** — the entry point wire-up can only read and subscribe, not write directly
2. **Never store DOM references at module level** — they live in `store.dom`, populated once at init
3. **Never create module-level mutable state** — use `store.interaction` for transient state like drag/pan

## The Map Index Pattern

Replace `O(n)` linear searches with a `Map` that is rebuilt on data changes.

```js
function rebuildNodeIndex(store) {
  store.nodeById = new Map(store.nodes.map(function(n) { return [n.id, n]; }));
}

// Before: loop every call
function findNodeById(store, id) {
  for (var i = 0; i < store.nodes.length; i++) {
    if (store.nodes[i].id === id) return store.nodes[i];
  }
  return null;
}

// After: O(1) lookup
var node = store.nodeById.get(id);
```

**When to rebuild:** at the start of `renderDiagram` (which runs after every data change) and directly after mutations that skip the render cycle.

## Event Bus for Reactivity

A lightweight pub/sub decouples state producers from state consumers.

```js
var listeners = {};

export var bus = {
  on(event, fn) { (listeners[event] ||= []).push(fn); },
  off(event, fn) {
    var fns = listeners[event];
    if (fns) listeners[event] = fns.filter(function(f) { return f !== fn; });
  },
  emit(event, data) { (listeners[event] || []).forEach(function(fn) { fn(data); }); },
};
```

### Common Event Categories

| Event | Emitter | Subscribers |
|---|---|---|
| `model:updated` | `model.js` | Stats, title, context list |
| `data:changed` | `model.js`, `ui.js` | Triggers re-render |
| `diagram:before-render` | `viewer.js` | Clear selection, clear SVG |
| `diagram:rendered` | `viewer.js` | Apply viewport, render annotations |
| `viewport:changed` | `interaction.js` | Update minimap |
| `node:delete` | `ui.js` | Remove node, re-render |
