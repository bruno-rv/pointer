# Pointer A Overlap Harness Report

Status: `FOLLOW_UP_UNCOMMITTED`

The accepted checkpoint `85f5b7b` is committed and was clean before this
adversarial follow-up. The changes described below are intentionally
uncommitted until the independent reviewer and adversarial review reconcile
them.

## Scope

This slice adds deterministic end-to-end tests for overlapping marks. The
tests drive the real `DeterministicInteractionHarness` through
`CommandRouter`, `DisplayCoordinator`, `OverlayPanel`, and `CanvasView`; they
do not append to `PointerSession` directly or duplicate hit testing in the
test code.

Changed paths:

- `Tests/PointerAppKitTests/Harness/OverlappingMarksHarnessTests.swift`
- `.codex/sdd/reports/pointer-a-harness-overlap-report.md`

No production or existing harness file required a change. The requested
operation surface was already public and complete.

## Covered behavior

`testLatestOverlappingMarkIsSelectedDeletedAndUnderlyingReselected` creates a
rectangle followed by a clearly overlapping ellipse through real draw
gestures. It verifies that selection at their shared point chooses the latest
mark, moving that selected mark preserves mark order while changing only the
preview until commit, cancellation restores the committed geometry and
selection, local Delete removes only the top mark, and selecting the same
point again chooses the underlying rectangle.

`testOverlappingGeometryRemainsDisplayLocalWhenSelectingEachDisplay` creates
the same normalized rectangle/ellipse pair independently on two displays. It
verifies that selecting the shared point on display B selects only B's latest
mark, selecting it on display A selects only A's latest mark, and neither
selection migrates the other display's canvas or selection chrome.

The fixture oracle is invoked after synchronization, every route, every draw
gesture boundary, every gesture continuation, deletion, move, cancellation,
and re-selection transition.

## Adversarial follow-up

The follow-up closes three review gaps without changing production behavior:

- Before the shared-point click, a real CanvasView gesture at a point inside
  only the underlying rectangle selects that rectangle, and a real gesture
  outside both marks clears selection. Only then does the shared point verify
  latest/topmost ellipse selection.
- During the selected-mark move, the coordinator's committed marks and the
  snapshot's committed marks must equal the original full `Mark` values, the
  preview must differ, the underlying `Mark` must remain identical, and only
  the selected top mark may change geometry.
- With display A still the accepted pointer display, local Delete after
  selecting display B leaves display A's complete mark array unchanged and
  removes only display B's top mark. The underlying B mark remains and
  selection clears before A is selected.

## Deterministic verification

The first focused run was:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OverlappingMarksHarnessTests
```

Result: PASS, 2 tests. Because the existing production operation surface was
already sufficient, the RED-stage test compiled and passed rather than
revealing a missing operation; no production change was authorized or
needed.

Final verification:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OverlappingMarksHarnessTests` — PASS, 2 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'OverlappingMarksHarnessTests|CanvasIntegrationHarnessTests|CanvasViewTests|CommandRouterTests|DisplayCoordinatorTests|GestureTransactionTests|HitTestingTests|SelectionDisplayTests'` — PASS, 107 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` — PASS, 324 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` — PASS.
- `git diff --check` — PASS.

The current follow-up worktree is intentionally uncommitted with only the
existing overlap test and report modified relative to `85f5b7b`; no
production or pre-existing harness files were touched.
