# Mark Rendering Prototype

> PROTOTYPE — throwaway code used to choose Pointer's mark rendering and state
> model. It is not production application code.

Run it:

```sh
cd /Users/bruno/Dev/pointer/.scratch/pointer-mvp/prototypes/mark-rendering
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run MarkRenderingPrototype
```

Use the toolbar to draw arrows, rectangles, ellipses, freehand strokes, and
emoji stamps. Switch to Select to choose, move, or resize a mark. Delete removes
the selected mark; Eraser removes marks by clicking or dragging across them.
Undo and Clear operate on the in-memory canvas. The inspector refreshes
diagnostic state on committed actions and at drag boundaries, rather than every
drag sample.

## Benchmark

Build and run the release benchmark with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build -c release --product MarkRenderingPrototype
.build/release/MarkRenderingPrototype \
  --benchmark-drag --label local --format json
```

It measures only the shared `CanvasView` gesture event-handler path. It excludes
drawing, including the grid, event dispatch, and compositing.
