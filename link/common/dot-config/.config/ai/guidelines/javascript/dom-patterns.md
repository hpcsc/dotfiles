# JavaScript DOM Patterns

## SVG Element Creation

Use `document.createElementNS` with `setAttribute`. Build a tree with `appendChild`.

```js
var NS = "http://www.w3.org/2000/svg";

function svgRect(x, y, w, h, fill, stroke, attrs) {
  var el = document.createElementNS(NS, "rect");
  el.setAttribute("x", x);
  el.setAttribute("y", y);
  el.setAttribute("width", w);
  el.setAttribute("height", h);
  el.setAttribute("fill", fill);
  el.setAttribute("stroke", stroke);
  setAttrs(el, attrs);
  return el;
}
```

**Why:** DOM API avoids XSS via innerHTML, preserves attached event listeners, and is faster at scale. String concatenation is acceptable only for complex diagnostic UIs (tooltips, panels) where content is explicitly escaped.

## Event Delegation

Attach ONE listener to an ancestor element. Use `closest()` to find the target.

```js
// ✅ Good — one listener, always works
svgEl.addEventListener("click", function(evt) {
  var block = evt.target.closest(".diagram-node");
  if (!block) return;
  var nodeId = block.dataset.nodeId;
  // handle click
});

// ❌ Avoid — re-attached after every render
blocks.forEach(function(block) {
  block.addEventListener("click", handler);
});
```

**Exception:** `mouseenter`/`mouseleave` don't bubble. Use `pointerover`/`pointerout` with `closest()` instead:

```js
var hoveredBlock = null;

svgEl.addEventListener("pointerover", function(evt) {
  var block = evt.target.closest(".diagram-node");
  if (block === hoveredBlock) return;
  hoveredBlock = block;
  if (!block) return;
  // show tooltip
});

svgEl.addEventListener("pointerout", function(evt) {
  var block = evt.target.closest(".diagram-node");
  if (block && (!evt.relatedTarget || !evt.relatedTarget.closest(".diagram-node"))) {
    hoveredBlock = null;
    // hide tooltip
  }
});
```

## SVG Injection Pattern

Replace the SVG contents atomically. Preserve the `<defs>` element (which contains arrow markers, gradients, etc.).

```js
function inject(svgEl, viewportGroup) {
  var defsEl = svgEl.querySelector("defs");
  while (svgEl.firstChild) {
    svgEl.removeChild(svgEl.firstChild);
  }
  if (defsEl) svgEl.appendChild(defsEl);
  svgEl.appendChild(viewportGroup);
}
```

## CSS Classes: Type-Specific + Shared

For elements with type-specific appearance and shared behavior, use BOTH classes:

```html
<g class="cmd-block diagram-node" data-node-id="...">
```

- **Type-specific** class (`cmd-block`) — for per-type hover/highlight colors in CSS
- **Shared** class (`diagram-node`) — for JS selectors and shared behavior (cursor, dragging)

```js
// JS queries use the shared class only
var block = target.closest(".diagram-node");

// CSS hover colors still use type-specific classes
#diagram-canvas .cmd-block:hover rect { fill: #b8cce8; }
#diagram-canvas .evt-block:hover rect { fill: #f5d0b0; }
```
