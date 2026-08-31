# Pointer A Overlap Harness Report

Status: `DONE`

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

The final worktree boundary contains only the two paths listed above as
untracked changes; no production or pre-existing harness files were touched.
