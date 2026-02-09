# Draw.io Diagram Templates

Templates and styles for generating Event Modeling diagrams.

## Base Template

```xml
<mxfile host="app.diagrams.net">
  <diagram name="Event Model - [Feature Name]" id="event-model">
    <mxGraphModel dx="1400" dy="900" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1600" pageHeight="600">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />

        <!-- SWIMLANE POOL -->
        <mxCell id="pool" value="[Feature Name]" style="swimlane;childLayout=stackLayout;resizeParent=1;resizeParentMax=0;horizontal=1;startSize=30;horizontalStack=0;html=1;fontFamily=Helvetica;fontSize=14;fontStyle=1;" vertex="1" parent="1">
          <mxGeometry x="20" y="20" width="1400" height="400" as="geometry" />
        </mxCell>

        <!-- Lane 1: UI / Triggers -->
        <mxCell id="lane1" value="UI / Triggers" style="swimlane;startSize=30;horizontal=0;html=1;fontFamily=Helvetica;" vertex="1" parent="pool">
          <mxGeometry y="30" width="1400" height="120" as="geometry" />
        </mxCell>

        <!-- Lane 2: Commands / Views -->
        <mxCell id="lane2" value="Commands / Views" style="swimlane;startSize=30;horizontal=0;html=1;fontFamily=Helvetica;" vertex="1" parent="pool">
          <mxGeometry y="150" width="1400" height="120" as="geometry" />
        </mxCell>

        <!-- Lane 3: Events -->
        <mxCell id="lane3" value="Events" style="swimlane;startSize=30;horizontal=0;html=1;fontFamily=Helvetica;" vertex="1" parent="pool">
          <mxGeometry y="270" width="1400" height="130" as="geometry" />
        </mxCell>

        <!-- ADD ELEMENTS HERE -->

      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

## Element Styles

### Event (Orange/Peach)
```
style="rounded=0;whiteSpace=wrap;html=1;fontFamily=Helvetica;fillColor=#ffe6cc;strokeColor=#d79b00;"
```

### Command (Light Blue)
```
style="rounded=0;whiteSpace=wrap;html=1;fontFamily=Helvetica;fillColor=#dae8fc;strokeColor=#6c8ebf;"
```

### View (Light Green)
```
style="rounded=0;whiteSpace=wrap;html=1;fontFamily=Helvetica;fillColor=#d5e8d4;strokeColor=#82b366;"
```

### UI/Wireframe (White)
```
style="rounded=0;whiteSpace=wrap;html=1;fontFamily=Helvetica;fillColor=#ffffff;strokeColor=#333333;"
```

### Automation/Reactor (Gear Icon)
```
style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;fillColor=#232F3D;strokeColor=none;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;fontStyle=0;aspect=fixed;pointerEvents=1;shape=mxgraph.aws4.gear;fontFamily=Helvetica;"
```

### External System (Gray Dashed)
```
style="rounded=0;whiteSpace=wrap;html=1;fontFamily=Helvetica;fillColor=#f5f5f5;strokeColor=#666666;dashed=1;fontColor=#333333;"
```

## Connection Styles

### Downward Flow (Standard Arrow)
Use for: UI → Command, Command → Event, Reactor → Command
```
style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;fontFamily=Helvetica;strokeColor=#333333;endArrow=classic;"
```

### Upward Flow - Event to Reactor (Purple Curved)
Use for: Event → Reactor/Automation triggers
```xml
<mxCell style="edgeStyle=orthogonalEdgeStyle;html=1;fontFamily=Helvetica;strokeColor=#9B59B6;fontSize=10;endArrow=classic;exitX=1;exitY=0.5;exitDx=0;exitDy=0;curved=1;" edge="1" source="evt1" target="auto1">
  <mxGeometry relative="1" as="geometry">
    <Array as="points">
      <mxPoint x="320" y="355" />
      <mxPoint x="320" y="110" />
    </Array>
  </mxGeometry>
</mxCell>
```

### Upward Flow - Event to View (Green Curved)
Use for: Event → View projections
```xml
<mxCell style="edgeStyle=orthogonalEdgeStyle;html=1;fontFamily=Helvetica;strokeColor=#82b366;fontSize=10;endArrow=classic;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=1;entryDx=0;entryDy=0;curved=1;" edge="1" source="evt2" target="view2">
  <mxGeometry relative="1" as="geometry">
    <Array as="points">
      <mxPoint x="514" y="300" />
      <mxPoint x="940" y="300" />
    </Array>
  </mxGeometry>
</mxCell>
```

### Webhook/External Callback (Dashed Gray)
Use for: External system → Event callbacks
```
style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;fontFamily=Helvetica;strokeColor=#666666;dashed=1;endArrow=classic;fontSize=10;"
```

## Element Sizing

- Standard element size: `width="174" height="79"`
- Gear icon size: `width="78" height="78"`
- Horizontal spacing between slices: ~270px

## Layout Guidelines

1. **Slices flow left-to-right** — Each vertical column = one slice
2. **Events on timeline** — Chronological left-to-right, but **DO NOT connect events directly**
3. **Triggers at top** — UI wireframes and automation triggers in Lane 1
4. **Commands/Views in middle** — Business logic layer in Lane 2
5. **Events at bottom** — All events aligned on the timeline in Lane 3
6. **Async connections dashed** — Use dashed lines for event-triggered flows
7. **Causal flow** — Event → Reactor → Command → Event (events cause reactors, commands produce events)

## Complete Example Element

```xml
<!-- Command: PlaceOrder -->
<mxCell id="cmd1" value="PlaceOrder" style="rounded=0;whiteSpace=wrap;html=1;fontFamily=Helvetica;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="lane2">
  <mxGeometry x="50" y="20" width="174" height="79" as="geometry" />
</mxCell>

<!-- Event: OrderPlaced -->
<mxCell id="evt1" value="OrderPlaced" style="rounded=0;whiteSpace=wrap;html=1;fontFamily=Helvetica;fillColor=#ffe6cc;strokeColor=#d79b00;" vertex="1" parent="lane3">
  <mxGeometry x="50" y="25" width="174" height="79" as="geometry" />
</mxCell>

<!-- Connection: Command to Event -->
<mxCell style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;fontFamily=Helvetica;strokeColor=#333333;endArrow=classic;" edge="1" parent="1" source="cmd1" target="evt1">
  <mxGeometry relative="1" as="geometry" />
</mxCell>
```

## Color Reference

| Element | Fill Color | Stroke Color |
|---------|------------|--------------|
| Event | #ffe6cc | #d79b00 |
| Command | #dae8fc | #6c8ebf |
| View | #d5e8d4 | #82b366 |
| UI/Trigger | #ffffff | #333333 |
| External | #f5f5f5 | #666666 |
| Reactor arrow | - | #9B59B6 |
| View arrow | - | #82b366 |
