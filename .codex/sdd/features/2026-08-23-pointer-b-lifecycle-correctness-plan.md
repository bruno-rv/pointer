# Pointer B — Core Gesture, Display, and Lifecycle Correctness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking. The coordinating agent owns commits and publication; worker tasks end with evidence/status handoff instead of commit steps.

**Goal:** Make PointerCore, CanvasView event/cursor behavior, overlays, and display lifecycle preserve marks and presenter control with exact cancellation and resource ownership; a separately gated B-render-integration phase wires D's accepted renderer plan afterward.

**Architecture:** B-core keeps PointerCore as the source of truth for transactional gestures, normalized geometry, hit testing, selection, and undo, and makes CanvasView/OverlayPanel expose deterministic boundary/cursor/lifecycle behavior while DisplayCoordinator reports immutable display-sync and stop results. After D is accepted, the isolated B-render-integration phase wires MarkRenderer's mode-aware plan through CanvasView; C consumes lifecycle results but B never mutates palette visibility.

**Tech Stack:** Swift tools 5.10, macOS 14+, AppKit, PointerCore, PointerAppKit, XCTest, CoreGraphics geometry, NSPanel/NSView, Swift concurrency.

**Spec:** .codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md (Workstream B — gesture, display, and lifecycle correctness; Workstream A deterministic seam is consumed only through accepted public contracts).

## Global Constraints

- PointerCore owns AppKit-free value models, normalized display-local geometry, gesture transactions, hit testing, tool state, selection, and undo.
- There is one overlay and one in-memory display canvas per connected physical display. Canvas identity is a stable display UUID, never a transient display ID. .scratch/ prototypes remain evidence and are not production dependencies.
- Entering standby clears selection while retaining committed marks and undo history; standby overlays ignore mouse events and keep selection chrome, resize handles, hover indicators, active drafts, and contextual Delete absent.
- Every gesture is a transaction: preview during drag, at most one undo entry on a meaningful commit, and exact pre-gesture restoration on cancel.
- Preserve documented arrow, rectangle, ellipse, pen, emoji, spotlight, select, and eraser pointer contracts; zero-length shapes are discarded and sparse eraser samples sweep the segment between samples.
- Preserve normalized geometry, aspect-ratio rules, selection ownership, and display-local meaning across resize and display frame changes.
- Work only in /Users/bruno/Dev/pointer/.worktrees/stable-app; preserve unrelated dirty files and generated artifacts in /Users/bruno/Dev/pointer.
- This workstream owns Sources/PointerCore/**, Sources/PointerAppKit/CanvasView.swift, DisplayCoordinator.swift, OverlayPanel.swift, OverlayPresenting.swift, ScreenProviding.swift, NSScreenProvider.swift, DisplayUUIDProvider.swift, and their model/display tests; it does not edit A's Support/** or Harness/**, D's Rendering files, C/E/F scopes.
- Do not add global event monitors, Quartz event taps, input synthesis, screen capture, new dependencies, new permissions, saved canvases, or distribution infrastructure.

---

## Dependency and interface contract

A's harness consumes the signatures below after B reports them. C consumes DisplaySyncResult and DisplayStopResult; B owns the result types and callback but does not hide/show or reposition a palette. C owns the palette decision. D consumes B's mark/render geometry behavior. No B task may edit A's shared fixtures or C's controller.

    public struct DisplaySyncResult: Equatable, Sendable {
        public let connectedUUIDs: Set<DisplayUUID>
        public let addedUUIDs: Set<DisplayUUID>
        public let removedUUIDs: Set<DisplayUUID>
        public let pointerDisplay: DisplayUUID?
        public let hasConnectedDisplays: Bool
        public let enteredZeroDisplayState: Bool
        public let reconnected: Bool
    }

    public struct DisplayStopResult: Equatable, Sendable {
        public let closedOverlayCount: Int
        public let remainingOverlayCount: Int
        public let activeGestureCount: Int
        public let clearedHandlerCount: Int
        public let boundHandlerCount: Int
    }

    public struct OverlayCleanupResult: Equatable, Sendable {
        public let cancelledActiveGesture: Bool
        public let clearedHandlerCount: Int
        public let remainingHandlerCount: Int
        public let didClose: Bool
        public init(cancelledActiveGesture: Bool, clearedHandlerCount: Int,
                    remainingHandlerCount: Int, didClose: Bool)
    }
    }

    @MainActor
    public extension OverlayPresenting {
        func stopAndClear() -> OverlayCleanupResult {
            OverlayCleanupResult(
                cancelledActiveGesture: false,
                clearedHandlerCount: 0,
                remainingHandlerCount: 0,
                didClose: false
            )
        }
    }

    @MainActor
    public func synchronize() -> DisplaySyncResult

    @MainActor
    public func stop() -> DisplayStopResult

    @MainActor
    public func apply(_ command: SessionCommand, cancellingActiveGestures: Bool)

    @MainActor
    public var onDisplaySync: ((DisplaySyncResult) -> Void)? { get set }

    public extension PointerSession {
        public func canUndo(on display: DisplayUUID) -> Bool
    }

    @MainActor
    public extension CanvasView {
        public enum CursorPlan: Equatable, Sendable {
            case clickThrough
            case select
            case draw
            case erase
            case emoji
            case spotlight
        }
        public private(set) var cursorPlan: CursorPlan { get }
    }

The cursor plan is a value description; CanvasView owns applying and restoring the corresponding native cursor. synchronize() emits exactly one callback per call, even when no display set changes. A stop() result reports post-cleanup counts, not pre-cleanup counts.

## Task 1: Lock core cancellation, standby, and geometric boundary regressions

**Files:**

- Modify: Sources/PointerCore/PointerSession.swift
- Modify: Sources/PointerCore/SessionCommand.swift
- Modify: Sources/PointerCore/GestureTransaction.swift
- Modify: Sources/PointerCore/HitTesting.swift
- Modify: Tests/PointerCoreTests/GestureTransactionTests.swift
- Modify: Tests/PointerCoreTests/HitTestingTests.swift
- Modify: Tests/PointerCoreTests/CanvasTests.swift
- Create: Tests/PointerCoreTests/LifecycleRegressionTests.swift

**Interfaces:**

- Preserve beginGesture(tool:at:on:), advanceGesture(to:), commitGesture(), cancelGesture(), and previewCanvas(for:).
- Add PointerSession.canUndo(on:) -> Bool as a read-only query over the per-display undo history.
- Make a mode transition to standby clear selection/selection display after cancelling the active transaction; preserve canvases, marks, tool state, and undo histories.
- Make stale CanvasView mouseUp impossible to commit after cancel by preserving the existing active-gesture guard and exposing exact cancellation state to the AppKit layer.

- [ ] **Step 1: Add failing core tests for standby and stale cancellation.**

    func testStandbyClearsSelectionButRetainsMarksAndUndoAvailability() {
        let display = DisplayUUID(rawValue: "display-a")
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let mark = fixtureRectangle()
        session.apply(.append(mark, to: display))
        _ = session.beginGesture(tool: .select, at: NormalizedPoint(x: 0.3, y: 0.3), on: display)
        _ = session.commitGesture()
        XCTAssertEqual(session.selection, mark.id)

        session.apply(.setMode(.standby))

        XCTAssertEqual(session.mode, .standby)
        XCTAssertNil(session.selection)
        XCTAssertEqual(session.canvas(for: display).marks, [mark])
        XCTAssertTrue(session.canUndo(on: display))
        session.apply(.undo(on: display))
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)
    }

    func testCancelledGestureThenCommitWithoutActiveTransactionDoesNotMutateOrAddUndo() {
        let display = DisplayUUID(rawValue: "display-a")
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        _ = session.beginGesture(tool: .arrow, at: .init(x: 0.2, y: 0.2), on: display)
        _ = session.advanceGesture(to: .init(x: 0.8, y: 0.8))
        _ = session.cancelGesture()
        let staleCommit = session.commitGesture()
        XCTAssertFalse(staleCommit.didMutate)
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)
        XCTAssertFalse(session.canUndo(on: display))
    }

- [ ] **Step 2: Run focused tests and verify RED.**

Run:

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'LifecycleRegressionTests|GestureTransactionTests.testModeChangeCancelsActiveGestureBeforeStandby'

Expected: the selection remains selected or canUndo(on:) is missing; the stale commit test must fail before implementation.

- [ ] **Step 3: Implement the smallest core fix.**

In PointerSession.apply, cancel before .setMode whenever an active gesture exists, set mode, then clear selection and selection display for .standby. Add canUndo(on:) by exposing only whether the corresponding private UndoHistory has a snapshot. Do not make UndoHistory storage mutable or change the 100-entry capacity. Keep cancellation restoring baseCanvas, baseSelection, and baseSelectionDisplay exactly.

- [ ] **Step 4: Add and run explicit hit-boundary regressions.**

    func testCollinearOverlapOnRectangleEdgeCountsAsHit()
    func testTangentEllipseBoundaryCountsAsHit()
    func testArrowEndpointContactWithinEpsilonCountsAsHit()
    func testSegmentOutsideEpsilonMisses()

Each test constructs normalized values with tolerance 0.02, asserts true for collinear/endpoint/tangent contact, and asserts false after adding 0.001 to the outside distance. Fix segment orientation handling in HitTesting.segmentsIntersect so collinear overlap and endpoint contact count, while retaining the just-outside-epsilon miss. Do not widen the global tolerance beyond 0.02.

- [ ] **Step 5: Run the complete core suite and verify GREEN.**

Run:

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PointerCoreTests|LifecycleRegressionTests|HitTestingTests|GestureTransactionTests'

Expected: all existing core tests and the named boundary tests pass with no geometry drift. Hand off the exact canUndo(on:) and standby semantics to A/C.

## Task 2: Add CanvasView cursor ownership and event cancellation

**Files:**

- Modify: Sources/PointerAppKit/CanvasView.swift
- Modify: Tests/PointerAppKitTests/CanvasViewTests.swift

**Interfaces:**

- CanvasView.CursorPlan has exactly .clickThrough, .select, .draw, .erase, .emoji, and .spotlight.
- CanvasView exposes cursorPlan and updates it when tool or session mode changes.
- CanvasView.update(session:) adopts a standby session whose PointerSession cancellation already occurred by clearing local hasActiveGesture without invoking cancelGesture(), so it emits no second cancellation boundary.
- beginGesture(at:), continueGesture(to:), endGesture(), and cancelGesture() remain the public point-based production seam.
- endGesture() is a no-op when hasActiveGesture is false; cancel restores the normal click-through cursor and does not publish a commit.

- [ ] **Step 1: Write failing cursor and stale-mouse-up tests.**

    @MainActor
    func testCursorPlanCoversEveryToolAndStandby() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 800, height: 600),
                              display: DisplayUUID(rawValue: "display-a"),
                              session: session)
        for (tool, expected) in [(PointerTool.select, CanvasView.CursorPlan.select),
                                 (.arrow, .draw), (.rectangle, .draw), (.ellipse, .draw),
                                 (.pen, .draw), (.eraser, .erase), (.emoji, .emoji),
                                 (.spotlight, .spotlight)] {
            view.tool = tool
            XCTAssertEqual(view.cursorPlan, expected)
        }
        view.update(session: PointerSession())
        XCTAssertEqual(view.cursorPlan, .clickThrough)
    }

    @MainActor
    func testCancelThenStaleMouseUpDoesNotCommitOrPublishSecondBoundary() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 800, height: 600),
                              display: DisplayUUID(rawValue: "display-a"),
                              session: session,
                              tool: .arrow)
        var boundaries: [GestureBoundaryEvent] = []
        view.onBoundaryEvent = { boundaries.append($0) }
        view.beginGesture(at: NSPoint(x: 100, y: 100))
        view.continueGesture(to: NSPoint(x: 300, y: 300))
        view.cancelGesture()
        view.endGesture()
        XCTAssertEqual(boundaries, [.began, .cancelled])
        XCTAssertTrue(view.session.canvas(for: view.display).marks.isEmpty)
    }

- [ ] **Step 2: Run focused tests and verify RED.**

Run:

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CanvasViewTests

Expected: compilation fails for CursorPlan or cursor assertions fail because tool changes do not own cursor state.

- [ ] **Step 3: Implement cursor plan and native cursor application.**

Store cursorPlan privately, derive draw/select/erase/emoji/spotlight from tool, and set .clickThrough whenever session.mode == .standby. Use NSCursor.arrow for click-through/select, crosshair for draw, operationNotAllowed for erase, pointingHand for emoji, and openHand for spotlight. Apply the cursor in resetCursorRects() and restore via discardCursorRects() on mode/tool transitions. The palette and CommandRouter must not write cursor state.

- [ ] **Step 4: Run AppKit and core regression tests.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'CanvasViewTests|GestureTransactionTests|LifecycleRegressionTests'

Expected: PASS, including continuation redraw without boundary publication and cancel/stale mouse-up behavior.

## Task 3: Make overlay behavior calm and lifecycle-safe

**Files:**

- Modify: Sources/PointerAppKit/OverlayPanel.swift
- Modify: Sources/PointerAppKit/OverlayPresenting.swift
- Modify: Tests/PointerAppKitTests/DisplayCoordinatorTests.swift
- Modify: Tests/PointerAppKitTests/CanvasViewTests.swift

**Interfaces:**

- OverlayPanel.setMode(_:) sets ignoresMouseEvents for standby and refreshes CanvasView cursor state.
- OverlayPanel.update(session:) updates CanvasView with the session and never introduces selection chrome in standby.
- OverlayPanel.close() is idempotent: repeated close calls order out once and never invoke a closed panel's handler.
- OverlayPresenting retains setEventHandlers, cancelActiveGesture, update(session:), update(display:), show(), and close(), and adds stopAndClear() -> OverlayCleanupResult. The protocol extension default is an observable zero/no-op for existing conforming fakes; OverlayPanel overrides it. The real override cancels the active CanvasView gesture, clears onSessionUpdate/onBoundaryEvent/onRedrawRequested, closes exactly once, and returns cancelledActiveGesture, clearedHandlerCount, remainingHandlerCount, and didClose; it does not alter the coordinator's PointerSession.

- [ ] **Step 1: Add failing overlay tests.**

    @MainActor
    func testStandbyOverlayKeepsMarksVisibleButRemovesHandlesAndMouseEvents() throws {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let mark = fixtureRectangle()
        session.apply(.append(mark, to: panel.display.uuid))
        session.apply(.setTool(.select))
        panel.update(session: session)
        panel.setMode(.standby)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.canvasView.session.canvas(for: panel.display.uuid).marks, [mark])
    }

    @MainActor
    func testOverlayStopAndClearReturnsObservableCleanupCounts() {
        let overlay = RecordingOverlay(display: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        let first = overlay.stopAndClear()
        let second = overlay.stopAndClear()
        XCTAssertEqual(first.clearedHandlerCount, 3)
        XCTAssertEqual(first.remainingHandlerCount, 0)
        XCTAssertTrue(first.didClose)
        XCTAssertEqual(second.clearedHandlerCount, 0)
        XCTAssertFalse(second.didClose)
        XCTAssertEqual(overlay.closeCount, 1)
    }

    @MainActor
    func testDefaultOverlayStopAndClearIsObservableNoOp() {
        let fake = ExistingOverlayConformingFake(display: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        let result = fake.stopAndClear()
        XCTAssertEqual(result, OverlayCleanupResult(cancelledActiveGesture: false,
                                                    clearedHandlerCount: 0,
                                                    remainingHandlerCount: 0,
                                                    didClose: false))
    }

- [ ] **Step 2: Run focused tests and verify RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'DisplayCoordinatorTests|CanvasViewTests'

Expected: the recording overlay either counts duplicate close calls or retains handlers; no test may be made green by skipping the production OverlayPanel path.

- [ ] **Step 3: Implement idempotent close and lifecycle reset.**

Add an internal closed flag to OverlayPanel and implement stopAndClear() as the only lifecycle cleanup operation: record hasActiveGesture, cancel it, nil CanvasView.onSessionUpdate/onBoundaryEvent/onRedrawRequested and count three cleared handlers, call orderOut/super.close only on the first invocation, and return exact remaining/closed counts. Keep the display-local session in DisplayCoordinator; cleanup must not delete the coordinator's canvas. close() delegates to the same idempotent close guard for normal callers.

- [ ] **Step 4: Run overlay tests and verify GREEN.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'DisplayCoordinatorTests|CanvasViewTests'

Expected: PASS with one close, zero handlers, click-through standby, and marks still in the session preview.

## Task 4: Return display-sync and stop oracles

**Files:**

- Modify: Sources/PointerAppKit/DisplayCoordinator.swift
- Modify: Sources/PointerAppKit/ScreenProviding.swift
- Modify: Tests/PointerAppKitTests/DisplayCoordinatorTests.swift

**Interfaces:**

- DisplayCoordinator.synchronize() -> DisplaySyncResult computes connected, added, removed, pointer UUID, zero-display entry, and reconnect flags from stable UUIDs.
- DisplayCoordinator.onDisplaySync receives exactly the same result once per synchronize call.
- DisplayCoordinator.stop() -> DisplayStopResult calls each overlay's stopAndClear(), aggregates its returned cleanup counts, closes/removes all overlays exactly once, retains display-local session canvases, and leaves no closed panel in overlays.
- A one-to-zero synchronize calls each real overlay.cancelActiveGesture() exactly once, forwards its actual .cancelled boundary, then applies SessionCommand.setMode(.standby) to the already-cancelled session before constructing/emitting DisplaySyncResult; the callback observes session.mode == .standby and no input-intercepting overlay.
- DisplayCoordinator.cancelActiveGestures() remains available for command routing and calls every overlay exactly once. CommandRouter Escape/display-loss callers use cancelActiveGestures() once, then apply(.setMode(.standby), cancellingActiveGestures: false); the cancellation-free overload updates the already-cancelled session without a second overlay call.

- [ ] **Step 1: Add failing sync and stop tests.**

    @MainActor
    func testSynchronizeReportsAddedRemovedPointerZeroAndReconnectFlags() {
        let uuid = DisplayUUID(rawValue: "display-a")
        let provider = FakeScreenProvider(displays: [descriptor(uuid: uuid)])
        let coordinator = makeCoordinator(provider: provider)
        var results: [DisplaySyncResult] = []
        coordinator.onDisplaySync = { results.append($0) }
        let first = coordinator.synchronize()
        XCTAssertEqual(first.addedUUIDs, Set([uuid]))
        XCTAssertTrue(first.hasConnectedDisplays)
        XCTAssertFalse(first.enteredZeroDisplayState)
        XCTAssertFalse(first.reconnected)
        provider.displays = []
        let zero = coordinator.synchronize()
        XCTAssertEqual(zero.removedUUIDs, Set([uuid]))
        XCTAssertFalse(zero.hasConnectedDisplays)
        XCTAssertTrue(zero.enteredZeroDisplayState)
        provider.displays = [descriptor(uuid: uuid, x: 40, width: 1_600)]
        let reconnect = coordinator.synchronize()
        XCTAssertTrue(reconnect.reconnected)
        XCTAssertEqual(reconnect.pointerDisplay, uuid)
        XCTAssertEqual(results, [first, zero, reconnect])
    }

    @MainActor
    func testOneToZeroSynchronizeCancelsRealOverlayOnceThenAppliesStandbyBeforeCallback() {
        let uuid = DisplayUUID(rawValue: "display-a")
        let provider = FakeScreenProvider(displays: [descriptor(uuid: uuid)])
        let coordinator = makeCoordinator(provider: provider)
        _ = coordinator.synchronize()
        coordinator.apply(.setMode(.annotation))
        provider.displays = []
        var callbackMode: PointerMode?
        var boundaryEvents: [GestureBoundaryEvent] = []
        coordinator.onBoundaryEvent = { _, event in boundaryEvents.append(event) }
        coordinator.onDisplaySync = { _ in callbackMode = coordinator.session.mode }
        let result = coordinator.synchronize()
        XCTAssertTrue(result.enteredZeroDisplayState)
        XCTAssertEqual(coordinator.session.mode, .standby)
        XCTAssertEqual(callbackMode, .standby)
        XCTAssertEqual(boundaryEvents, [.cancelled])
    }

    @MainActor
    func testStopClosesEveryOverlayOnceClearsHandlersAndCreatesFreshOverlayAfterRestart() {
        let provider = FakeScreenProvider(displays: [descriptor(uuid: DisplayUUID(rawValue: "a")),
                                                     descriptor(uuid: DisplayUUID(rawValue: "b"))])
        var created: [FakeOverlay] = []
        let coordinator = makeCoordinator(provider: provider) { descriptor in
            let overlay = FakeOverlay(display: descriptor)
            created.append(overlay)
            return overlay
        }
        _ = coordinator.synchronize()
        let firstStop = coordinator.stop()
        XCTAssertEqual(firstStop.closedOverlayCount, 2)
        XCTAssertEqual(firstStop.remainingOverlayCount, 0)
        XCTAssertEqual(firstStop.activeGestureCount, 0)
        XCTAssertEqual(firstStop.clearedHandlerCount, 6)
        XCTAssertEqual(firstStop.boundHandlerCount, 0)
        XCTAssertTrue(created.allSatisfy { $0.closeCount == 1 })
        _ = coordinator.synchronize()
        XCTAssertEqual(created.count, 4)
        XCTAssertTrue(created[2] !== created[0])
        XCTAssertTrue(created[3] !== created[1])
    }

- [ ] **Step 2: Run focused tests and verify RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DisplayCoordinatorTests

Expected: compilation fails because synchronize currently returns Void and DisplaySyncResult, DisplayStopResult, OverlayCleanupResult, stopAndClear(), and onDisplaySync are absent.

- [ ] **Step 3: Implement immutable result computation.**

Capture the previous connected UUID set before querying the provider. Ignore descriptors with empty UUIDs and include only valid stable UUIDs in connected/added/removed. enteredZeroDisplayState is true only when previous connected is nonempty and current connected is empty. The single display-loss cancellation path is: call each real overlay.cancelActiveGesture() exactly once; its actual CanvasView.onBoundaryEvent callback forwards .cancelled through DisplayCoordinator.onBoundaryEvent and its onSessionUpdate callback installs the cancelled PointerSession; then call apply(.setMode(.standby), cancellingActiveGestures: false), which sees no active transaction and only changes mode/selection. Do not call overlay.cancelActiveGesture a second time, and do not claim PointerSession.apply emits the boundary. Update overlays with standby, close/remove them, construct the result, and emit exactly one callback after session/overlays are consistent. reconnected is true only when current is nonempty after a prior empty synchronization and includes a UUID retained in the session.

- [ ] **Step 4: Implement stop cleanup and fresh overlay creation.**

For every current overlay during deliberate stop: call stopAndClear(), aggregate cancelledActiveGesture, clearedHandlerCount, remainingHandlerCount, and didClose, update it to standby, and remove it from the dictionary. Existing test fakes compile against the protocol extension default; real OverlayPanel overrides it. Keep session canvases and undo histories untouched. DisplayStopResult.clearedHandlerCount is the sum returned by overlays; boundHandlerCount is the sum of remainingHandlerCount and must be zero after stop. synchronize() must construct a new overlay for a later connection even if the same UUID returns; the existing session canvas is reused by UUID.

- [ ] **Step 5: Run B display tests and verify GREEN.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'DisplayCoordinatorTests|PointerApplicationControllerTests'

Expected: B tests pass; any C controller compilation failure is reported as the accepted interface handoff, not fixed by editing C files.

## Task 5: Cover pointer contracts, resize, display churn, and resource invariants

**Files:**

- Modify: Tests/PointerCoreTests/GestureTransactionTests.swift
- Modify: Tests/PointerCoreTests/ResizeGeometryTests.swift
- Modify: Tests/PointerCoreTests/HitTestingTests.swift
- Modify: Tests/PointerAppKitTests/DisplayCoordinatorTests.swift
- Create: Tests/PointerAppKitTests/DisplayLifecycleRegressionTests.swift

**Interfaces:**

- Tests consume only B production APIs and verify geometry/resource invariants; they do not add production behavior in test support.
- Display lifecycle tests use fake ScreenProviding and OverlayPresenting implementations local to B tests; they do not edit A's Support/** or Harness/**.

- [ ] **Step 1: Add failing pointer-contract tests.**

    func testAllSupportedToolsHaveDocumentedCommitContracts()
    func testSelectionChoosesTopmostAndEmptyClickClearsSelection()
    func testEveryResizeHandlePreservesNormalizedGeometryAndUndo()
    func testSparseEraserSweepCreatesOneUndoSnapshot()
    func testDisplayResizeChangesPixelsButNotDisplayLocalMeaning()

Each test uses named fixtures for arrow, rectangle, ellipse, pen, emoji, spotlight, select, and eraser; asserts zero-length discard, topmost hit, aspect-preserving freehand/emoji resize, one erase snapshot, and exact normalized values after a descriptor frame change.

- [ ] **Step 2: Run the new tests and verify RED for each uncovered edge.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'GestureTransactionTests|ResizeGeometryTests|HitTestingTests|DisplayLifecycleRegressionTests'

Expected: each new test either fails on the known missing behavior or passes against existing behavior; a pre-existing pass is recorded as baseline evidence and not treated as a new fix.

- [ ] **Step 3: Add failing display resource-oracle tests.**

    @MainActor
    func testZeroDisplayTransitionCancelsGesturesClosesOverlayAndRetainsSessionCanvas()
    func testDisplayLossProducesExactlyOneCancellationBoundaryPerActiveOverlay()
    @MainActor
    func testPointerDisplayChangeDoesNotMigrateMarks()
    @MainActor
    func testRepeatedSynchronizeDoesNotDuplicateOverlayOrCallback()
    @MainActor
    func testStopWithZeroDisplaysReturnsAllZeroCounts()

Assert exact callback count, no orphan overlay, standby/no input interception, retained mode/tool/style/emoji/spotlight/canvas/undo state in the B-owned session oracle, and fresh overlay identity after reconnect. Record the C/F handoff for shortcut and menu-bar retention; B does not reach into those owners.
The display-loss cancellation test uses the real OverlayPanel factory, begins a real CanvasView gesture, changes the provider to zero displays, records exactly one forwarded .cancelled boundary, then invokes the stale mouseUp path and asserts no second boundary or mark commit.

- [ ] **Step 4: Implement only B-owned fixes required by failing tests.**

Do not hide palette state in DisplayCoordinator. Do not retain closed panel instances for reuse. Do not move marks between UUIDs. Do not widen geometry tolerance to make unrelated tests pass.

- [ ] **Step 5: Run the full B verification.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
    git diff --check

Expected: all current and new B tests pass. Record exact results and list any unsupported physical display/Space case for F's manual ledger.

## Phase B-render-integration: Wire D's accepted render plan through CanvasView

**Prerequisite:** This phase starts only after D's public RenderPlan, HandleInventory, RenderPlan.make(canvas:mode:selectedID:activeDraft:hover:), and MarkRenderer.draw(plan:in:context:) are reviewed and accepted. B core is complete and reconciled first; D does not edit CanvasView, and this phase does not reopen B core behavior.

**Files:**

- Modify: Sources/PointerAppKit/CanvasView.swift
- Modify: Sources/PointerAppKit/OverlayPanel.swift
- Create: Tests/PointerAppKitTests/CanvasViewRenderIntegrationTests.swift

**Interfaces:**

- CanvasView exposes public private(set) var renderPlan: RenderPlan.
- update(session:), begin/advance/commit/cancel boundaries, and setMode recompute renderPlan from the latest PointerSession preview canvas, mode, selected ID, and active draft.
- draw(_:) calls MarkRenderer.draw(plan:in:context:) using the current renderPlan; it does not call the old mode-blind selected-canvas overload.

- [ ] **Step 1: Write the failing integration test after D handoff.**

    import AppKit
    import CryptoKit
    import XCTest

    @MainActor
    func testCanvasViewDrawUsesRealNonVisibleWindowAndFixedBitmapAcrossModeReselection() throws {
        _ = NSApplication.shared
        let display = DisplayUUID(rawValue: "display-a")
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let mark = Mark(
            geometry: .rectangle(NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)),
            style: .default
        )
        session.apply(.append(mark, to: display))
        session.apply(.setTool(.select))
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 512, height: 512),
                              display: display, session: session, tool: .select)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 512, height: 512),
            styleMask: [.borderless], backing: .buffered, defer: true
        )
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 512, height: 512)
        XCTAssertFalse(window.isVisible)

        view.beginGesture(at: NSPoint(x: 256, y: 256))
        view.endGesture()
        XCTAssertEqual(view.renderPlan.handles.selection.selectedMarkID, mark.id)
        XCTAssertTrue(view.renderPlan.handles.selection.isVisible)
        XCTAssertFalse(view.renderPlan.handles.resize.handles.isEmpty)
        XCTAssertTrue(view.renderPlan.handles.resize.isVisible)
        let selectedPixels = try renderToFixedBitmap(view)
        XCTAssertTrue(containsHandleSentinel(selectedPixels, around: [
            CGPoint(x: 128, y: 128), CGPoint(x: 384, y: 128),
            CGPoint(x: 128, y: 384), CGPoint(x: 384, y: 384),
        ], radius: 9, coordinateTolerance: 1))

        session = view.session
        session.apply(.setMode(.standby))
        view.update(session: session)
        let standbyPixels = try renderToFixedBitmap(view)
        XCTAssertEqual(view.renderPlan.committedMarks, [mark])
        XCTAssertNil(view.renderPlan.activeDraft)
        XCTAssertNil(view.renderPlan.handles.selection.selectedMarkID)
        XCTAssertFalse(view.renderPlan.handles.selection.isVisible)
        XCTAssertTrue(view.renderPlan.handles.resize.handles.isEmpty)
        XCTAssertFalse(view.renderPlan.handles.resize.isVisible)
        XCTAssertFalse(view.renderPlan.handles.contextualDeleteVisible)
        XCTAssertTrue(alpha(of: standbyPixels, at: CGPoint(x: 256, y: 128)) > 0)
        XCTAssertTrue(alpha(of: standbyPixels, at: CGPoint(x: 128, y: 256)) > 0)
        XCTAssertLessThanOrEqual(alpha(of: standbyPixels, at: CGPoint(x: 256, y: 120)), 1)
        XCTAssertLessThanOrEqual(alpha(of: standbyPixels, at: CGPoint(x: 120, y: 256)), 1)
        XCTAssertFalse(containsHandleSentinel(standbyPixels, around: [
            CGPoint(x: 128, y: 128), CGPoint(x: 384, y: 128),
            CGPoint(x: 128, y: 384), CGPoint(x: 384, y: 384),
        ], radius: 9, coordinateTolerance: 1))
        XCTAssertEqual(sha256Hex(standbyPixels), expectedStandbyDigest)

        session.apply(.setMode(.annotation))
        view.update(session: session)
        let annotationWithoutReselection = try renderToFixedBitmap(view)
        XCTAssertTrue(alpha(of: annotationWithoutReselection, at: CGPoint(x: 256, y: 128)) > 0)
        XCTAssertNil(view.renderPlan.activeDraft)
        XCTAssertTrue(view.renderPlan.handles.resize.handles.isEmpty)
        XCTAssertFalse(containsHandleSentinel(annotationWithoutReselection, around: [
            CGPoint(x: 128, y: 128), CGPoint(x: 384, y: 128),
            CGPoint(x: 128, y: 384), CGPoint(x: 384, y: 384),
        ], radius: 9, coordinateTolerance: 1))

        view.beginGesture(at: NSPoint(x: 256, y: 256))
        view.endGesture()
        let reselectedPixels = try renderToFixedBitmap(view)
        XCTAssertEqual(view.renderPlan.handles.selection.selectedMarkID, mark.id)
        XCTAssertTrue(view.renderPlan.handles.selection.isVisible)
        XCTAssertFalse(view.renderPlan.handles.resize.handles.isEmpty)
        XCTAssertTrue(view.renderPlan.handles.resize.isVisible)
        XCTAssertTrue(containsHandleSentinel(reselectedPixels, around: [
            CGPoint(x: 128, y: 128), CGPoint(x: 384, y: 128),
            CGPoint(x: 128, y: 384), CGPoint(x: 384, y: 384),
        ], radius: 9, coordinateTolerance: 1))
    }

    @MainActor
    func testCanvasViewSourceUsesOnlyModeAwareRendererOverload() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PointerAppKit/CanvasView.swift"))
        let normalized = source.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        XCTAssertNotNil(normalized.range(of: "MarkRenderer\\.draw\\s*\\(\\s*plan:", options: .regularExpression))
        XCTAssertNil(normalized.range(of: "MarkRenderer\\.draw\\s*\\(\\s*canvas:", options: .regularExpression))
    }

    private func renderToFixedBitmap(_ view: CanvasView) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: 512 * 512 * 4)
        try pixels.withUnsafeMutableBytes { rawBuffer in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: rawBuffer.baseAddress,
                      width: 512, height: 512,
                      bitsPerComponent: 8, bytesPerRow: 512 * 4,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { throw BitmapError.cannotCreateContext }
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            view.draw(view.bounds)
            NSGraphicsContext.restoreGraphicsState()
        }
        return pixels
    }

    private enum BitmapError: Error { case cannotCreateContext }

    private func alpha(of pixels: [UInt8], at point: CGPoint) -> UInt8 {
        pixels[(Int(point.y) * 512 + Int(point.x)) * 4 + 3]
    }

    private func containsHandleSentinel(
        _ pixels: [UInt8], around points: [CGPoint], radius: Int, coordinateTolerance: Int
    ) -> Bool {
        for point in points {
            for y in (Int(point.y) - radius - coordinateTolerance)...(Int(point.y) + radius + coordinateTolerance) {
                for x in (Int(point.x) - radius - coordinateTolerance)...(Int(point.x) + radius + coordinateTolerance) {
                    let offset = (y * 512 + x) * 4
                    guard offset >= 0, offset + 3 < pixels.count else { continue }
                    let red = pixels[offset], green = pixels[offset + 1], blue = pixels[offset + 2]
                    if pixels[offset + 3] > 0,
                       (red > 245 && green > 245 && blue > 245)
                        || (red < 10 && green < 10 && blue < 10)
                    { return true }
                }
            }
        }
        return false
    }

    private func sha256Hex(_ pixels: [UInt8]) -> String {
        SHA256.hash(data: Data(pixels)).map { String(format: "%02x", $0) }.joined()
    }

- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CanvasViewRenderIntegrationTests

Expected: compilation fails because CanvasView.renderPlan and the public top-level mode-aware draw path are not wired.

- [ ] **Step 3: Implement the real CanvasView sequence.**

Use this sequence for every session update and gesture boundary: session.previewCanvas(for: display) plus session.mode/selection/active draft -> RenderPlan.make(canvas:mode:selectedID:activeDraft:hover:) -> renderPlan -> draw(_:) -> MarkRenderer.draw(plan:in:context:). In standby, renderPlan retains committed marks and has no draft, selection inventory, hover inventory, resize inventory, or contextual Delete. In annotation, only an explicit selection restores selection chrome. OverlayPanel passes session/mode to CanvasView without introducing a parallel render path.

- [ ] **Step 4: Run GREEN and hand off to A.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'CanvasViewRenderIntegrationTests|CanvasViewTests|DisplayCoordinatorTests'
    ! rg -n --pcre2 'MarkRenderer\.draw\s*\(\s*canvas:' Sources/PointerAppKit/CanvasView.swift
    rg -q --pcre2 'MarkRenderer\.draw\s*\(\s*plan:' Sources/PointerAppKit/CanvasView.swift

Expected: the real-window fixed-bitmap integration test, source-level overload guard, and core lifecycle tests pass. Record the accepted B-render-integration interface for A's later Harness phase.

## Task 6: Worker/reviewer/adversarial reconciliation gate

**Files:**

- Modify only files listed in Tasks 1–5 after a finding is accepted.
- Evidence handoff: coordinator-owned review record; no commit or publication from this worker.

- [ ] **Step 1: Check disjoint scope.**

    git status --short
    git diff --name-only -- Sources/PointerCore Sources/PointerAppKit/CanvasView.swift Sources/PointerAppKit/DisplayCoordinator.swift Sources/PointerAppKit/OverlayPanel.swift Sources/PointerAppKit/OverlayPresenting.swift Sources/PointerAppKit/ScreenProviding.swift Sources/PointerAppKit/NSScreenProvider.swift Sources/PointerAppKit/DisplayUUIDProvider.swift Tests/PointerCoreTests Tests/PointerAppKitTests

Expected: no A Support/** or Harness/**, palette, command, shortcut, guide, composition, script, or report path is changed by B.

- [ ] **Step 2: Run focused and full verification.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'LifecycleRegressionTests|GestureTransactionTests|HitTestingTests|ResizeGeometryTests|CanvasViewTests|DisplayCoordinatorTests|DisplayLifecycleRegressionTests'
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

Expected: PASS with zero failures and exact callback/stop counts.

- [ ] **Step 3: Handoff to the configured Luna reviewer.**

Provide changed paths, test output, result-type signatures, cancellation proof, geometry boundary proof, overlay close counts, stable UUID proof, and the explicit statement that palette visibility remains C-owned. Reviewer returns REVISE with exact findings or APPROVED only when lifecycle behavior is supported by tests and no ownership boundary is crossed.

- [ ] **Step 4: After reviewer approval, run adversarial Codex review.**

Challenge stale mouse-up, standby selection/handles, collinear and tangent geometry, zero-display mode, reconnect without migration, closed-panel reuse, exactly-once callback/close, handler clearing, cursor restoration, and accidental palette mutation. Re-run the smallest relevant tests.

- [ ] **Step 5: Reconcile until worker, reviewer, and Codex agree.**

Return each finding to the smallest B-owned file, rerun RED/GREEN verification, obtain reviewer re-approval, and repeat adversarial checks. Report RECONCILED only with no unresolved blocker/high-severity lifecycle or geometry finding; report any required C interface exactly without editing C.

## Plan self-check

- Core cancellation/undo, hit-test epsilon, cursor plan, standby overlay, display-sync result, stop result, zero-display, reconnect, pointer contract, resource, and disjoint-scope requirements are assigned to Tasks 1–5. The D-gated CanvasView render-plan integration is isolated in Phase B-render-integration and has its own RED/GREEN/reviewer handoff.
- All interfaces use consistent names: DisplaySyncResult, DisplayStopResult, PointerSession.canUndo(on:), CanvasView.CursorPlan, and CanvasView point-based gesture methods.
- The separate B-render-integration phase is the only B section that names public RenderPlan/renderPlan/CanvasViewRenderIntegrationTests, and it is explicitly gated after D acceptance.
- OverlayCleanupResult/stopAndClear(), one-to-zero standby-before-callback ordering, and the normalized forbidden-overload regex are explicit; no cleanup count is inferred from a guessed handler map.
- No task instructs a commit, physical-use claim, global input synthesis, palette mutation, saved-state feature, or unrelated cleanup.
