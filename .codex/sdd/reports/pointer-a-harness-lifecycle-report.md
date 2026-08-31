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
- A successful first-use `.shown` presentation marks the guide seen only once
  after visibility; a later ordinary sync leaves the mark count unchanged.
- A `.shown` guide that never becomes visible stays unseen through display loss
  and two failed reconnect restores; `markCount` remains zero while the
  controller retries the retained display-loss intent.
- Hides a visible guide on display loss without changing its seen state,
  restores it only after palette restoration, and clears the restoration intent
  on application stop so the next start does not replay a stale restore.

## Evidence boundary

This is deterministic AppKit/resource evidence, not physical multi-display or
VoiceOver evidence. It proves production object composition, lifecycle counts,
callback cleanup, real in-process CanvasView gesture routing, and guide event
ordering. It does not prove WindowServer behavior across Spaces, physical
pointer hit targets, or a person's live VoiceOver experience; those remain
manual integration evidence.

## Verification

The focused lifecycle suite passed:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter LifecycleHarnessTests
Executed 9 tests, with 0 failures
```

The initial RED run intentionally failed to compile because
`LifecycleInteractionFixture` did not yet exist. The subsequent GREEN run
passed all nine tests, including the post-restart callback oracles and the
unseen/pending-guide state checks.
