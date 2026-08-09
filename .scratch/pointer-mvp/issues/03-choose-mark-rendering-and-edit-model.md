# Choose the mark rendering and edit model

Type: prototype
Status: resolved
Blocked by: none

## Question

Which native rendering and state representation gives Pointer smooth drawing,
stable geometry, undo, adjustable opacity, selection, movement, and deletion
without overbuilding the first version?

## Answer

Render marks directly in an AppKit `NSView` and keep each display canvas as an
ordered in-memory array of value-type `Mark` records. Each mark has a stable
UUID, opacity, and enum-backed geometry: arrow endpoints, shape bounds,
freehand points, or an emoji value plus bounds. Render in array order and hit
test in reverse order so the visually topmost mark wins.

Selection stores only the selected mark ID plus transient move or resize
gesture state. Arrow endpoints resize independently; bounded marks use corner
handles. Each completed editing gesture records one whole-canvas value
snapshot for undo. An eraser drag likewise records one snapshot before removing
every intersected mark, so one undo restores the whole gesture.

The approved prototype validates creation, rendering, opacity, selection,
movement, resizing, deletion, erasing, undo, and clearing for arrows,
rectangles, ellipses, freehand strokes, and emoji stamps. The grid and inspector
belong only to the prototype; production rendering will use the transparent
presentation overlays.

Use AppKit drawing and the value model as the production baseline. Do not carry
the prototype source into the app wholesale; extract the validated model and
behaviors behind testable production types.

Prototype asset: [Mark rendering prototype](../prototypes/mark-rendering/README.md)
