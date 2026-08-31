# Pointer A-harness phase reconciliation

Status: `READY_FOR_PHASE_REVIEW`

## Checkpoint and scope

`6ef2d60` (`test: integrate Pointer real guide lifecycle`) is the
implementation evidence checkpoint for this phase. This report is the
evidence artifact for that checkpoint; the commit containing this report
finalizes the evidence.
The report does not rely on a volatile claim about an uncommitted report.

The A-harness work stays in the stable-app worktree and consumes the accepted
B-render-integration, C, and D interfaces. The exact range reviewed is
`1dab1b7..6ef2d60`. It contains 17 changed paths: 11 A-owned paths and six
paths touched by two explicitly routed C exceptions at `cb791f8` and
`4db806f`. A did not silently edit C.

The A-owned paths are the production deterministic harness, six harness
fixture/test files, and four A evidence reports. The routed C paths are
`Sources/PointerAppKit/Palette/ControlMetadataProvider.swift`,
`Tests/PointerAppKitTests/AccessibilityMetadataTests.swift`,
`Sources/PointerAppKit/Palette/PalettePanel.swift`,
`Sources/PointerAppKit/Palette/PaletteViewController.swift`,
`Tests/PointerAppKitTests/PaletteInteractionTests.swift`, and the C phase
report. The `cb791f8` change supplies concrete native accessibility roles when
AppKit reports `AXUnknown`; A consumes that accepted contract through
metadata. The `4db806f` change keeps the real 420-point palette contained at
388 points, compresses the status line, and fails closed on post-ordering
overflow; A consumes that contract through the canonical narrow fixture.

## Real production graph

`DeterministicInteractionFixture` builds the real in-process graph:

- `DeterministicScreenProvider` supplies only the OS-facing display seam.
- `DisplayCoordinator` creates real `OverlayPanel` instances.
- Each `OverlayPanel` owns the real `CanvasView` for its stable
  `DisplayUUID`.
- `CommandRouter` is the command and local-key route.
- `PalettePanel`, `MenuBarController`, `HotKeyController`, and
  `ControlMetadataInventory` are retained production objects.
- The registrar, shortcut store, scheduler, and clock are deterministic
  seams; they do not register a machine-wide shortcut, synthesize input, or
  sleep.

The production `DeterministicInteractionHarness` delegates display sync to
`DisplayCoordinator.synchronize()`, commands to `CommandRouter.route(_:)`,
local keys to the local route, and gestures to the real
`OverlayPanel.canvasView` methods. It rejects empty or unsupported UUIDs and
rejects a non-production overlay instead of substituting a fake.

## Convergence and retained snapshots

After every sync, route, gesture boundary, and continuation, the harness
oracle compares the coordinator session with every connected real overlay:

- committed canvases are read from the coordinator;
- preview canvases and cached D `RenderPlan` values are read from each real
  `CanvasView`;
- the active draft is the one preview mark whose ID is absent from the
  committed canvas, and is reported only when both the canvas and session own
  the active gesture;
- renderer committed marks plus the draft exactly partition the preview;
- non-owner previews equal their coordinator committed canvas;
- selection, selected display, mode, tool state, handles, undo, and
  click-through mode remain aligned.

Commit removes the draft from the active plan. Cancel restores the committed
canvas and prior selection, and a stale mouse-up publishes no second boundary
and creates no undo entry. Standby retains marks and retained previews while
clearing selection, resize handles, hover, contextual Delete, and mouse
interaction. Disconnected UUIDs remain in retained mark/preview snapshots,
while `connectedDisplays` reports only current real overlays. Undo is queried
per retained display, never inferred from mark count.

## Metadata and palette edge states

The metadata matrix reads the production hierarchy and returns unique rows in
native keyboard order. Every row has a stable identifier, accessible name,
help, concrete role, value where applicable, enabled state, and keyboard
reachability.

- Wide displays show an 822-point palette with all eight direct tools and no
  overflow tool rows. The native traversal reaches mode, all eight tools,
  color, stroke width, and opacity, then wraps to mode.
- The clamped fixture uses a 792-point visible display, which clamps the real
  palette to 760 points. Select, Arrow, Rectangle, Ellipse, Pen, and More stay
  direct; Eraser, Emoji, and Spotlight appear exactly once in the real
  overflow menu after its disabled header. The header exposes its own
  accessible label, help, value, and `AXMenuItem` role.
- The canonical narrow fixture uses a synchronized 420-point display and the
  real palette remains exactly 388 points wide. Select stays direct; the
  remaining seven tools appear exactly once under More, while style controls
  retain their metadata values and the style row remains horizontally
  scrollable. Native focus traverses More and wraps without losing a tool.
  This is deterministic containment and metadata evidence, not physical
  no-clipping proof.
- Pending shortcut metadata keeps P selected and O pending while the parent,
  candidates, palette status, and menu-bar status share the same five-second
  guidance. They remain enabled and action-capable.
- With no connected display, annotation, Clear All, and Undo Clear All are
  disabled with explicit values while Show Palette, Learn Pointer, Quit, and
  shortcut actions remain discoverable. Repeated reads are equal and command
  attempts do not mutate the session.

The four slider value captions and six static labels are intentionally
noninteractive context text, not additional semantic controls or status
rows. The palette has one explicit `palette.status` accessibility status.

## Overlap and cross-display ownership

The overlap tests create a rectangle and then an overlapping ellipse through
real draw gestures. Hit testing selects the newest mark at the shared point;
moving it changes only the owner preview until commit, cancellation restores
the exact original geometry, Delete removes only the top mark, and the
underlying rectangle is selectable afterward.

The same normalized geometry is created independently on two displays.
Selection, move, delete, handles, committed order, and canvas content remain
display-local. A selection on display B cannot migrate or delete display A's
marks, and a stale plan on a disconnected selected display cannot borrow
handles from another display.

## Lifecycle, resources, and guide behavior

The lifecycle harness composes the real controller, coordinator, overlays,
canvas views, palette, menu, shortcut controller, and guide seams. Running
resource checkpoints are exact for one and two displays:

| State | Palette | Menu | Screen observer | Appearance observer | Shortcut wiring | Overlays | Callbacks | Timers | Guide |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Running, one display, guide visible | 1 | 1 | 1 | 1 | 1 | 1 | 5 | 0 | 1 |
| Running, two displays, guide visible | 1 | 1 | 1 | 1 | 1 | 2 | 5 | 0 | 1 |
| Running after seen-guide restart | 1 | 1 | 1 | 1 | 1 | N | 5 | 0 | 0 |
| Stopped | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Stop also reports `closedOverlayCount == N`, zero remaining overlays,
`clearedHandlerCount == 2N`, and zero bound handlers. Repeated stop is
idempotent. Restart creates fresh overlay/canvas and menu-item identities,
retains the display-local canvas exactly once, and does not duplicate
callbacks, registrations, timers, or resources.

An unfinished real canvas gesture is canceled during stop without committing a
draft. Captured stale shortcut candidates, active tokens, and canceled timer
actions do not mutate the stopped session, event log, shortcut state, stop
result, or zero-resource checkpoint.

The integrated `PointerApplicationController.start()` path loads
`GuideAssetIdentity.json` and all 24 mapped PNGs through an injected bundle,
then verifies the real `FirstUseGuideController` panel is visible, key,
Done-focused, fully resolved, and observing appearance changes. Stop hides the
panel and removes its observer. First-use state changes only after a
successful visible callback. Display loss hides and retries the guide without
marking it seen; application stop clears restore intent; restart does not
replay stale restore work. A later explicit `showGuide()` creates a fresh real
panel and `applicationShouldTerminate` completes teardown. This is real
in-process controller/guide evidence, not executable launch proof.

## Reconciliation record

The active orchestration recorded an independent reviewer `APPROVED` and an
adversarial Codex `RECONCILED` for each A-harness slice:

| Slice | Reviewer | Adversarial Codex |
| --- | --- | --- |
| Core real-path harness | `APPROVED` | `RECONCILED` |
| Metadata matrix and display edge cases | `APPROVED` | `RECONCILED` |
| Canonical narrow layout and containment matrix | `APPROVED` | `RECONCILED` |
| Overlap and cross-display ownership | `APPROVED` | `RECONCILED` |
| Lifecycle and resource harness | `APPROVED` | `RECONCILED` |
| Integrated real guide lifecycle | `APPROVED` | `RECONCILED` |

The `cb791f8` native-role repair was a C-owned routed finding. It received a
separate reviewer `APPROVED` and adversarial Codex `RECONCILED` result before
A's metadata matrix consumed it. No A worker edited that C-owned production
path.

The `4db806f` narrow-palette containment repair was a second C-owned routed
finding. It received a separate reviewer `APPROVED` and adversarial Codex
`RECONCILED` result before A's canonical narrow fixture consumed it. No A
worker edited the C-owned containment paths.

The A slices were implemented in this chronology:

```text
59ed5ed  test: add Pointer interaction harness core
0d9a08a  fix: harden Pointer harness convergence
a31d657  test: prove Pointer preview convergence
2e151aa  docs: finalize Pointer harness core evidence
b21ede6  test: prove Pointer control metadata matrix
cb791f8  fix: expose native Pointer accessibility roles (routed C repair)
6637ea8  test: harden Pointer metadata semantics
85f5b7b  test: prove Pointer overlap hit testing
d7f1b6e  test: harden Pointer overlap ownership
725cf64  docs: finalize Pointer overlap evidence
0909b70  docs: make Pointer overlap evidence durable
5ef8142  test: prove Pointer lifecycle resources
eb60e7a  test: harden Pointer lifecycle teardown
4db806f  fix: keep Pointer narrow palette contained (routed C repair)
5d99808  test: prove Pointer canonical narrow layout
6ef2d60  test: integrate Pointer real guide lifecycle
```

## Verification at `6ef2d60`

Fresh focused command:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'CanvasIntegrationHarnessTests|ControlMetadataHarnessTests|OverlappingMarksHarnessTests|LifecycleHarnessTests'
```

Result: `28 passed, 0 failed` — Canvas 7, metadata 6, lifecycle 13, and
overlap 2.

Full package command:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Result: `340 passed, 0 failed`.

Build command:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

Result: `Build complete` with exit code 0.

`git diff --check 1dab1b7..6ef2d60` passed. The path inventory for that range
contains 17 paths: four A reports, one shared C report update, one A
production harness, six A harness test or fixture files, and six unique
C-owned paths touched by the two separately reconciled C exceptions. The
worktree was clean before this report was added.

## Remaining evidence boundaries

This phase provides deterministic AppKit and real in-process object evidence.
It does not prove physical pointer hit targets, WindowServer layering across
Spaces, physical multi-display behavior, live VoiceOver navigation, or human
discoverability.

F still owns the executable composition root, package/resource integration,
compiled `Assets.car`, Launch Services/icon resolution, Release bundle,
clean-clone and signature checks, and the manual physical/VoiceOver matrix.
The integrated A row exercises the real guide controller through
`PointerApplicationController` with an injected bundle; it does not replace
F's executable composition and compiled-resource proof.

E still owns paired performance and resilience evidence: model, renderer,
compositor, combined-frame, launch, allocation, redraw/layout,
responsiveness, input-to-visible, memory time series, resource plateau, and
display/shortcut churn measurements. This report makes no performance or
campaign-completion claim.

The phase is therefore `READY_FOR_PHASE_REVIEW`, not campaign complete.
