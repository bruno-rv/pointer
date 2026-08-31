# Pointer B render integration report

## Scope

The reviewed B render seam landed at commit `6af9073` (based on `99a7241`).
This follow-up tightens that implementation without changing
PointerCore gesture semantics, OverlayPanel forwarding, DisplayCoordinator
lifecycle logic, or the D renderer/plan contracts.

Changed files:

- `Sources/PointerAppKit/CanvasView.swift`
- `Tests/PointerAppKitTests/CanvasViewRenderIntegrationTests.swift`
- `.codex/sdd/reports/pointer-b-render-integration-report.md`

The current worktree contains the follow-up production optimization (materialize
committed mark IDs once per plan update), stronger source/callback tests, and
the corrected report. These follow-up edits are uncommitted; no additional
commit was created.

## Implementation

`CanvasView` now exposes a `public private(set) var renderPlan: RenderPlan`.
The plan is recomputed from the two session canvas views at one private seam:

1. read the committed canvas for the view's display;
2. read the preview canvas for that display;
3. materialize committed mark IDs once, then identify the first preview mark
   whose ID is not committed;
4. pass the preview canvas, mode, selection, draft, and hidden hover inventory
   to `RenderPlan.make`.

The adapter runs during initialization, external session adoption, gesture
begin/advance updates, commit, and cancellation before redraw or callback
observation. `draw(_:)` now calls only `MarkRenderer.draw(plan:in:context:)`.
No hover producer or `CanvasView.setMode` API was introduced.

## Test-first evidence

The new focused suite was written before the production adapter. The first
focused run failed at compile time because `CanvasView.renderPlan` was absent,
which is the expected RED failure. After the adapter was added:

```text
swift test --filter CanvasViewRenderIntegrationTests
Executed 6 tests, with 0 failures
```

The suite proves:

- selected rectangle resize handles are present in the cached plan and in a
  real offscreen `CanvasView` render;
- the selected → standby transition keeps committed pixels, removes selection,
  resize, hover, and contextual Delete state, and matches the accepted literal
  digest `049d2e0cfbdd8f6c02f4db31955dc408f6eda47ad93f2e4bf50516acfd4d5771`;
- annotation re-entry is unselected until an explicit selection click;
- a preview draft is cached during begin/advance, excluded from committed
  marks, removed after commit, and removed on cancellation; redraw,
  `onSessionUpdate`, and `onBoundaryEvent` callbacks observe the post-commit
  and post-cancel plans in the existing redraw → session → boundary order;
- external session adoption recomputes the committed plan;
- a whitespace-tolerant regex source guard extracts the actual `draw(_:)` body,
  requires the plan renderer overload there, and rejects any legacy
  `MarkRenderer.draw(canvas: ...)` call there; a second guard verifies the
  committed-ID `Set` avoids an O(N²) nested committed-mark scan;
- the real view is attached to a non-visible borderless `NSWindow` and remains
  non-visible while rendered through a fixed 512×512 sRGB RGBA8 bitmap context.

Additional focused green evidence:

```text
swift test --filter 'CanvasViewRenderIntegrationTests|CanvasViewTests|DisplayCoordinatorTests'
Executed 50 tests, with 0 failures
```

Full verification:

```text
swift test
Executed 309 tests, with 0 failures
swift build
Build complete
git diff --check
clean
```

The explicit renderer-overload source checks also passed: the actual
`draw(_:)` body contains the plan overload and contains no legacy
`MarkRenderer.draw(canvas: ...)` call.

## Handoff and remaining risk

Hover remains intentionally hidden because B has no hover producer and the
reviewed D renderer does not draw hover indicators. Adding hover interaction
would expand this bounded seam and needs a separate owner/spec.

This is an offscreen real-`CanvasView` proof, not packaged launch proof. F/A
still own wiring the compiled guide assets and release composition, then
proving the live unseen-guide → palette Arrow → real `OverlayPanel.canvasView`
gesture → Escape → standby path in the packaged app.
