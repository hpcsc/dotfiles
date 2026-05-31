# JavaScript Naming Patterns

## Module Naming

Use lowercase nouns describing the module's responsibility.

```
✅  store.js, config.js, bus.js, layout.js, renderer.js, interaction.js, ui.js, model.js
❌  StoreFactory.js, EventBusClass.js, layout-utils-and-helpers.js
```

## Export Naming

Export a single `const Namespace = { ... }` object per module. The name matches the module's responsibility.

```js
// file: layout.js
export const Layout = { buildTree, computeLayout, ... };

// file: renderer.js
export const Renderer = { buildSVG, inject, clearSVG, ... };
```

## Function Naming

### Verb-noun for operations
```js
function applyViewport(store) { ... }
function commitDrag(store, nodeId, dx, dy) { ... }
function hideDetailPanel(store) { ... }
```

### Return types for factories
```js
function createStore() { ... }       // returns a store object
function buildSVG(store) { ... }     // returns an SVG element
function generateNodeId(prefix) { ... }  // returns a string
```

### Private helpers are internal, not prefixed
Don't use `_` prefixes. Just leave unexported functions as-is.

```js
// ✅ Good — unexported function, visible only inside the module
function setAttrs(el, attrs) { ... }

// ❌ Unnecessary — the underscore adds nothing
function _setAttrs(el, attrs) { ... }
```

## Variable Naming

### Store properties are nouns describing state
```js
store.nodes, store.edges, store.viewport, store.layoutPositions
store.interaction.drag, store.interaction.pan
store.dom.svg, store.dom.tooltip
```

### DOM references live in `store.dom`
```js
store.dom.svg = document.getElementById('diagram-canvas');
store.dom.renderBtn = document.getElementById('render-btn');
```
