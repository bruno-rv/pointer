# Pointer A-harness lifecycle evidence

## Scope

This slice adds a test-only lifecycle fixture and resource harness under
`Tests/PointerAppKitTests/Harness/`. It does not modify production code or
reuse a synthetic coordinator, overlay, canvas, palette, menu, or gesture
engine.

`LifecycleInteractionFixture` composes:

- the real `DisplayCoordinator` with a real `OverlayPanel` factory;
- the real `OverlayPanel.canvasView` and `CanvasView` gesture methods;
- the real `PalettePanel` and `MenuBarController`;
- the real `HotKeyController`;
- deterministic screen, shortcut registrar/store/scheduler, clock, and guide
  presentation seams.

`IntegratedRealGuideLifecycleFixture` composes the same real graph but injects
the real D `FirstUseGuideController`, backed by a temporary bundle populated
from the tracked guide manifest and all 24 source PNGs.

Each test boots AppKit through `_ = NSApplication.shared`. No global event
monitor, event tap, input synthesis, screen capture, or sleep is used.

## Resource oracle

The controller's `PointerResourceCheckpoint` is asserted independently for
one and two connected displays.

| State | Palette | Menu | Screen observer | Appearance observer | Shortcut wiring | Overlays | Callbacks | Timers | Guide |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Running, one display, first-use guide visible after successful show | 1 | 1 | 1 | 1 | 1 | 1 | 5 | 0 | 1 |
| Running, two displays, first-use guide visible after successful show | 1 | 1 | 1 | 1 | 1 | 2 | 5 | 0 | 1 |
| Running after seen-guide restart | 1 | 1 | 1 | 1 | 1 | N | 5 | 0 | 0 |
| Stopped | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

The five running callbacks are two router callbacks (state and annotation),
one menu binding, one display-sync callback, and one shortcut-state callback.
The stop oracle also requires `DisplayStopResult` to report:

- `closedOverlayCount == N`;
- `remainingOverlayCount == 0`;
- `clearedHandlerCount == 2N` (the production session and boundary handlers);
- `boundHandlerCount == 0`.

The stopped fixture additionally verifies hidden palette/menu/guide state,
zero appearance observers, cleared controller/router/hotkey callbacks, no
registrations, no pending shortcut token, and no re-open on a late screen
parameter notification. The complete stopped checkpoint and the original
`DisplayStopResult` are reasserted after that late notification.

## Covered behaviors

- Draws a real arrow or rectangle through each real overlay's `CanvasView` and
  verifies committed marks and the D render plan before lifecycle teardown.
- Cancels a pending shortcut delivery timer and candidate registration on stop,
  proving the timer inventory goes from exactly one to zero.
- Makes repeated `stop()` calls idempotent and proves the coordinator's second
  stop is an all-zero result.
- Restarts through the same controller instance, proves fresh overlay/canvas
  and menu status-item identities, retains the display-local canvas mark, and
  proves repeated `start()` does not replace those objects.
- After restart, one screen notification yields one display-sync callback and
  one delivered active shortcut yields one state publication.
- An unfinished real CanvasView gesture is canceled on stop for both one- and
  two-display fixtures: `activeGestureCount == 1`, no draft is committed, the
  pre-gesture canvas remains, and `clearedHandlerCount == 2N`.
- A captured stale candidate token, active token, and canceled scheduler action
  are delivered after stop; none mutates the stopped session, shortcut store,
  event log, stop result, or zero-resource checkpoint.
- A successful first-use `.shown` presentation marks the guide seen only once
  after visibility; a later ordinary sync leaves the mark count unchanged.
- A `.shown` guide that never becomes visible stays unseen through display loss
  and two failed reconnect restores; `markCount` remains zero while the
  controller retries the retained display-loss intent.
- Hides a visible guide on display loss without changing its seen state,
  restores it only after palette restoration, and clears the restoration intent
  on application stop so the next start does not replay a stale restore.
- The integrated `PointerApplicationController.start()` path uses a concrete
  `FirstUseGuideController` with the tracked `GuideAssetIdentity.json` and all
  24 copied PNGs in an injected temporary bundle. The real
  `FirstUseGuidePanelWindow` is checked for visibility, key focus, Done focus,
  eight resolved images, and an active appearance observer; controller-stop
  teardown removes visibility/key status and the observer.
- After the integrated controller stops, a seen guide does not auto-reopen on
  restart; an explicit `showGuide()` creates a fresh real panel, and
  `applicationShouldTerminate` performs the second complete teardown.
- Exercises an unseen hidden guide through display loss, deliberate application
  stop, and restart. Restart emits only `palette.show` then a fresh
  `guide.showIfNeeded`, never a stale restore; mode, tool, canvas, seen state,
  and mark count remain unchanged until actual visibility.

## Evidence boundary

This is deterministic AppKit/resource evidence, not physical multi-display or
VoiceOver evidence. It proves production object composition, lifecycle counts,
callback cleanup, real in-process CanvasView gesture routing, and guide event
ordering. The integrated row exercises the D `FirstUseGuideController` through
the real `PointerApplicationController` in `PointerAppKit`, but does not claim
executable launch or Release `Assets.car` proof: `Sources/Pointer/main.swift`
composition and packaged resource validation remain F-owned integration
evidence. This suite also does not prove WindowServer behavior across Spaces,
physical pointer hit targets, or a person's live VoiceOver experience; those
remain manual integration evidence.

## Verification

The focused lifecycle suite passed:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter LifecycleHarnessTests
Executed 13 tests, with 0 failures
```

The initial RED run intentionally failed to compile because
`LifecycleInteractionFixture` did not yet exist. The subsequent GREEN run
passed all thirteen tests, including concrete guide-panel teardown, active
gesture cancellation, stale shortcut delivery, post-restart callback oracles,
and unseen/pending-guide state checks.

The related lifecycle/controller/guide/hotkey/display/render suites passed:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'LifecycleHarnessTests|PointerApplicationControllerTests|GuideIntegrationTests|FirstUseGuideTests|HotKeyControllerTests|ShortcutLifecycleTests|DisplayLifecycleRegressionTests|CanvasIntegrationHarnessTests|CanvasViewRenderIntegrationTests'
Executed 121 tests, with 0 failures
```

The full package and build gates also passed:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
Executed 340 tests, with 0 failures
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
Build complete
git diff --check
passed
```
