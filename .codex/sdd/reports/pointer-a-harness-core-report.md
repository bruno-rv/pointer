# Pointer A-harness Core Report

Status: `DONE_WITH_CONCERNS`

## Scope

Implemented the first deterministic, real-object interaction slice after the
B-render-integration handoff. The production harness accepts the documented
injected coordinator graph and only obtains gesture state through the real
`DisplayCoordinator`, `OverlayPanel`, and `CanvasView` objects. Commands and
local keyboard routing remain on `CommandRouter`; no global input, event tap,
screen capture, accessibility API, or parallel gesture engine was added.

Changed paths owned by this task:

- `Sources/PointerAppKit/Diagnostics/DeterministicInteractionHarness.swift`
- `Tests/PointerAppKitTests/Harness/DeterministicInteractionFixture.swift`
- `Tests/PointerAppKitTests/Harness/CanvasIntegrationHarnessTests.swift`
- `.codex/sdd/reports/pointer-a-harness-core-report.md`

No commit was created by this worker.

## Production seam

`DeterministicInteractionHarness` exposes the planned snapshot and operation
surface with only the dependencies it reads in this slice:

- `synchronizeDisplays()` delegates to `DisplayCoordinator.synchronize()`.
- `route(_:)` delegates to `CommandRouter.route(_:)`.
- `routeLocalKey(keyCode:modifiers:)` delegates to the local command route.
- `metadata()` delegates to the injected `ControlMetadataProviding`; metadata
  enumeration itself remains a later A slice.
- Gesture methods validate the synchronized stable UUID, downcast only the
  production `OverlayPanel`, and call its real `CanvasView` methods.
- Snapshots use coordinator session canvases, real CanvasView preview canvases,
  real CanvasView `RenderPlan`/`HandleInventory`, router shortcut state, and
  the connected overlay UUID set. Handle inventory is exposed only when the
  session's selected display has a matching real plan and selected mark;
  otherwise it is hidden. No mark-count inference is used for undo.
- Empty or unsupported UUIDs fail closed with
  `DeterministicInteractionError.invalidDisplay`; a non-production overlay
  fails with `unavailableOverlay` rather than silently substituting a fake.

The fixture constructs real `DisplayCoordinator`, `OverlayPanel`,
`CanvasView`, `CommandRouter`, `PalettePanel`, `MenuBarController`,
`HotKeyController`, and `ControlMetadataInventory`. Its OS-facing hot-key
registrar/store/scheduler are deterministic fixture seams so the tests do not
register a machine-wide shortcut or sleep; the interaction clock adapter is
the planned local wrapper around the phase-neutral deterministic clock.

## RED/GREEN evidence

RED command:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CanvasIntegrationHarnessTests
```

Result: expected compile failure because `InteractionClock`,
`DeterministicInteractionHarness`, and `DeterministicInteractionError` did not
exist. The test assertions were not weakened.

Focused GREEN command:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CanvasIntegrationHarnessTests
```

Result: `6 passed, 0 failed`.

Related GREEN command:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'CanvasIntegrationHarnessTests|CanvasViewTests|DisplayCoordinatorTests|CommandRouterTests'
```

Result: `68 passed, 0 failed`.

Full GREEN command:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Result: `315 passed, 0 failed` across the package.

## Covered scenarios

`CanvasIntegrationHarnessTests` uses the real display coordinator overlay
factory and verifies. A reusable fixture oracle runs after every display sync,
gesture begin, continuation, commit, and cancel. During an active continuation
it checks the shared mode/tool/selection/committed-canvas projection while
allowing the intentional gesture-local preview divergence; after boundaries it
checks the full relevant per-display projection, preview/RenderPlan partition,
and overlay click-through mode. This preserves the production rule that
continuation samples do not publish shared session state.

1. Arrow and rectangle commits travel through command routing and real canvas
   gestures, produce two committed marks, leave no active draft, and publish
   exactly `began, committed, began, committed` boundary events. A committed
   callback inspects the post-boundary real `RenderPlan` and confirms the draft
   is gone; the overlay and canvas object identities are also asserted.
2. Cancelling a rectangle after selecting a previously committed arrow restores
   the committed canvas and selection. A subsequent stale `endGesture` emits no
   second boundary and creates no undo entry.
3. Standby retains committed and preview canvas marks while clearing selection,
   active draft, resize handles, and contextual Delete.
4. Empty and malformed display fixtures report no connected displays and reject
   unsupported UUIDs without mutating the session.
5. A multi-display stale-plan case proves that a disconnected selected display
   cannot borrow handles from another display's stale real plan.
6. Disconnect/reconnect preserves an `display-a` mark while `display-b` remains
   connected and empty; the coordinator recreates A's real overlay and CanvasView
   without migrating content into B.

The test target's `DisplayFixtures` supplies the one-display, empty,
malformed, and stable-UUID reconnect descriptors. The first slice intentionally
does not claim physical display, WindowServer, VoiceOver, or screen-capture
proof.

## Deferred A-harness slices

The following remain for the next bounded A task and are not implied by this
partial report:

- production control metadata assertions through `harness.metadata()`;
- narrow-display and full-palette affordance matrices;
- overlapping-mark fixture and hit-testing matrix;
- explicit stop/reset and restart resource checkpoints;
- shortcut/menu action metadata and physical keyboard/VoiceOver evidence;
- final composition-root wiring and Release bundle/manual proof in F;
- E performance and resilience measurements.

The harness core is ready for independent review and adversarial review, but
the campaign goal remains active until those downstream slices reconcile.
