# Pointer D Task 1 Report — Render Plan

Status: `DONE_WITH_CONCERNS`

## Scope and implementation

Implemented the public `RenderPlan` and `HandleInventory` values, the
mode-aware `MarkRenderer.draw(plan:in:context:)` path, and the canonical
offscreen render tests. The plan now partitions an explicit active draft out
of a preview canvas, keeps the initializer internal, and gates resize-handle
drawing on visible selection. `CanvasView.swift` was not edited.

Changed paths owned by this task:

- `Sources/PointerAppKit/Rendering/RenderPlan.swift`
- `Sources/PointerAppKit/Rendering/HandleInventory.swift`
- `Sources/PointerAppKit/MarkRenderer.swift`
- `Tests/PointerAppKitTests/RenderPlanTests.swift`
- `Tests/PointerAppKitTests/VisualFixtures.swift`

Task 2 changes in the shared worktree remain outside this task's write scope.

## Strict RED/GREEN evidence

RED command:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RenderPlanTests
```

Result: expected compile failure. The public `RenderPlan`, `HoverInventory`,
and `MarkRenderer.draw(plan:in:context:)` symbols were missing.

Initial implementation check used the same command. The two public-shape tests
passed; the pixel test failed only because the fixture still contained the
zero digest placeholder. The renderer output was:

```text
049d2e0cfbdd8f6c02f4db31955dc408f6eda47ad93f2e4bf50516acfd4d5771
```

That measured digest is now the literal `expectedStandbyDigest`.

After Task 2 reached green, the focused command was rerun successfully. No
Task 2 files were modified by this task.

## Initial implementation verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RenderPlanTests` — PASS, 3 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'RenderPlanTests|MarkRendererTests|CanvasViewTests'` — PASS, 16 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` — PASS, 276 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` — PASS.
- `git diff --check` — PASS.

## Adversarial repair evidence

The inherited RenderPlan test additions first failed to compile because
labeled pixel tuples do not conform to `Equatable` for `XCTAssertEqual`.
Component assertions replaced those tuple comparisons. The fixture assertions
also now account for Core Graphics bitmap row orientation and sRGB conversion:
the real `PointerSession` preview supplies a draft whose ID is absent from the
committed canvas, the draft is rendered once, and its asymmetric 8-point blue
stroke reports exact alpha 128 at the top/left/right edges with zero alpha
outside the stroke. Light, dark, Increase Contrast, Reduce Transparency,
dense-canvas, and full-screen-content fixtures compare their outside pixels to
an empty render of the same background and verify the red mark remains visible.

Current focused result:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RenderPlanTests` — PASS, 8 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'RenderPlanTests|MarkRendererTests|CanvasViewTests'` — PASS, 21 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` — PASS, 291 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` — PASS.
- `git diff --check` — PASS.

## Fix round 1 evidence

The reviewer requested annotation compositing/order/style coverage and
fail-closed inventory semantics. RED was rerun with:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RenderPlanTests
```

After correcting an initial pixel sample that accidentally landed on the
bottom-center resize handle, the RED result was 5 tests with 5 failures: the
unknown selection/hover IDs remained visible and valid annotation selection did
not expose contextual Delete. The annotation pixel test passed, proving
committed mark -> custom draft -> visible handle ordering, including custom
blue color, 0.5 opacity, and non-default stroke width.

The minimal fix validates selection and hover IDs against committed marks,
clears invalid inventories, and exposes contextual Delete only for a valid
annotation selection. GREEN results:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RenderPlanTests` — PASS, 5 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'RenderPlanTests|MarkRendererTests|CanvasViewTests'` — PASS, 18 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` — PASS, 285 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` — PASS.
- `git diff --check` — PASS.

## Accepted render contract and handoff

`RenderPlan.make(canvas:mode:selectedID:activeDraft:hover:)` retains committed
marks in every mode. Standby discards the draft and clears selection, hover,
resize handles, and contextual Delete. Annotation keeps the supplied draft,
restores only the explicit selection and supplied hover inventory, and derives
resize handles from the selected committed mark.

The fixed bitmap contract is a 512 x 512 sRGB RGBA8 bitmap with bounds
`(0,0,512,512)`, normalized rectangle `(x: 0.25, y: 0.25, width: 0.5,
height: 0.5)`, default red 4-point stroke, alpha checks at `(256,128)`,
`(128,256)`, `(256,120)`, and `(120,256)`, and no opaque white/black handle
sentinel within radius 9 (coordinate tolerance 1) around the four corners.
The accepted lowercase SHA-256 is
`049d2e0cfbdd8f6c02f4db31955dc408f6eda47ad93f2e4bf50516acfd4d5771`.

For the separate B render-integration phase, on every session update and
gesture boundary, use this exact sequence:

```text
committedCanvas = session.canvas(for: display)
previewCanvas = session.previewCanvas(for: display)
activeDraft = previewCanvas.marks.first(where: { previewMark in
    !committedCanvas.marks.contains(where: { $0.id == previewMark.id })
})
CanvasView.renderPlan = RenderPlan.make(
    canvas: previewCanvas,
    mode: session.mode,
    selectedID: session.selection,
    activeDraft: activeDraft,
    hover: currentHoverInventory
)
CanvasView.draw(_:) -> MarkRenderer.draw(plan:in:context:)
```

`RenderPlan.make` partitions the explicit draft ID defensively, so B must pass
both the preview canvas and the derived draft. D has not wired this sequence
through `CanvasView` and makes no claim that the live draw path is complete.
Remaining concern: B must integrate and verify the contract; the fresh
focused, related, and full suites validate the standalone D surface only.
