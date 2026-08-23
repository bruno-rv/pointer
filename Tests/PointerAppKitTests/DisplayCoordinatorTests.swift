import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class DisplayCoordinatorTests: XCTestCase {
    func testSynchronizeReportsAddedRemovedPointerZeroAndReconnectFlags() {
        let uuid = DisplayUUID(rawValue: "display-a")
        let provider = FakeScreenProvider(displays: [descriptor(uuid: uuid)])
        let coordinator = makeCoordinator(provider: provider)
        var results: [DisplaySyncResult] = []
        coordinator.onDisplaySync = { results.append($0) }

        let first = coordinator.synchronize()

        XCTAssertEqual(first.connectedUUIDs, Set([uuid]))
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
        XCTAssertEqual(results.count, 3)
    }

    func testSynchronizeIgnoresDescriptorsWithInvalidStableUUIDs() {
        let invalidUUID = DisplayUUID(rawValue: "")
        let validUUID = DisplayUUID(rawValue: "display-a")
        let provider = FakeScreenProvider(displays: [
            descriptor(uuid: invalidUUID),
            descriptor(uuid: validUUID, x: 1_920),
        ])
        let coordinator = makeCoordinator(provider: provider)

        let result = coordinator.synchronize()

        XCTAssertEqual(result.connectedUUIDs, Set([validUUID]))
        XCTAssertEqual(result.addedUUIDs, Set([validUUID]))
        XCTAssertFalse(result.connectedUUIDs.contains(invalidUUID))
        XCTAssertNil(coordinator.overlays[invalidUUID])
        XCTAssertNil(result.pointerDisplay)
    }

    func testOneToZeroSynchronizeCancelsRealOverlayOnceThenAppliesStandbyBeforeCallback() {
        _ = NSApplication.shared
        let uuid = DisplayUUID(rawValue: "display-a")
        let provider = FakeScreenProvider(displays: [descriptor(uuid: uuid)])
        let coordinator = makeCoordinator(provider: provider) { descriptor in
            OverlayPanel(descriptor: descriptor)
        }
        _ = coordinator.synchronize()
        coordinator.apply(.setMode(.annotation))
        let panel = try! XCTUnwrap(coordinator.overlays[uuid] as? OverlayPanel)
        panel.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))

        provider.displays = []
        var callbackMode: PointerMode?
        var boundaryEvents: [GestureBoundaryEvent] = []
        coordinator.onBoundaryEvent = { _, event in boundaryEvents.append(event) }
        coordinator.onDisplaySync = { _ in
            callbackMode = coordinator.session.mode
            XCTAssertTrue(coordinator.overlays.isEmpty)
        }

        let result = coordinator.synchronize()

        XCTAssertTrue(result.enteredZeroDisplayState)
        XCTAssertEqual(coordinator.session.mode, .standby)
        XCTAssertEqual(callbackMode, .standby)
        XCTAssertEqual(boundaryEvents, [.cancelled])
        XCTAssertFalse(panel.canvasView.hasActiveGesture)
    }

    func testApplyCanSkipCancellationAfterCallerCancels() {
        let uuid = DisplayUUID(rawValue: "display-a")
        let provider = FakeScreenProvider(displays: [descriptor(uuid: uuid)])
        let coordinator = makeCoordinator(provider: provider)
        _ = coordinator.synchronize()
        let overlay = try! XCTUnwrap(coordinator.overlays[uuid] as? FakeOverlay)
        overlay.cancelCount = 0

        coordinator.cancelActiveGestures()
        coordinator.apply(.setMode(.standby), cancellingActiveGestures: false)

        XCTAssertEqual(overlay.cancelCount, 1)
    }

    func testStopClosesEveryOverlayOnceClearsHandlersAndCreatesFreshOverlayAfterRestart() {
        let uuidA = DisplayUUID(rawValue: "a")
        let uuidB = DisplayUUID(rawValue: "b")
        let provider = FakeScreenProvider(displays: [
            descriptor(uuid: uuidA),
            descriptor(uuid: uuidB, x: 1_920),
        ])
        var created: [FakeOverlay] = []
        let coordinator = makeCoordinator(provider: provider) { descriptor in
            let overlay = FakeOverlay(display: descriptor)
            created.append(overlay)
            return overlay
        }
        _ = coordinator.synchronize()
        let mark = Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.2, y: 0.2),
                end: NormalizedPoint(x: 0.8, y: 0.8)
            ),
            style: .default
        )
        coordinator.apply(.append(mark, to: uuidA))

        let firstStop = coordinator.stop()

        XCTAssertEqual(firstStop.closedOverlayCount, 2)
        XCTAssertEqual(firstStop.remainingOverlayCount, 0)
        XCTAssertEqual(firstStop.activeGestureCount, 0)
        XCTAssertEqual(firstStop.clearedHandlerCount, 6)
        XCTAssertEqual(firstStop.boundHandlerCount, 0)
        XCTAssertTrue(created.allSatisfy { $0.closeCount == 1 })
        XCTAssertEqual(coordinator.session.canvas(for: uuidA).marks, [mark])

        _ = coordinator.synchronize()

        XCTAssertEqual(created.count, 4)
        XCTAssertTrue(created[2] !== created[0])
        XCTAssertTrue(created[3] !== created[1])
        XCTAssertEqual(coordinator.session.canvas(for: uuidA).marks, [mark])
    }

    func testStopResetsSynchronizationBookkeepingForDirectRestart() {
        let uuidA = DisplayUUID(rawValue: "a")
        let uuidB = DisplayUUID(rawValue: "b")
        let provider = FakeScreenProvider(displays: [
            descriptor(uuid: uuidA),
            descriptor(uuid: uuidB, x: 1_920),
        ])
        let coordinator = makeCoordinator(provider: provider)
        _ = coordinator.synchronize()

        _ = coordinator.stop()
        let restarted = coordinator.synchronize()

        XCTAssertEqual(restarted.connectedUUIDs, Set([uuidA, uuidB]))
        XCTAssertEqual(restarted.addedUUIDs, Set([uuidA, uuidB]))
        XCTAssertTrue(restarted.removedUUIDs.isEmpty)
        XCTAssertFalse(restarted.enteredZeroDisplayState)
        XCTAssertFalse(restarted.reconnected)
    }

    func testStopThenZeroSyncDoesNotLoseRetainedReconnectHistory() {
        let uuid = DisplayUUID(rawValue: "display-a")
        let provider = FakeScreenProvider(displays: [descriptor(uuid: uuid)])
        let coordinator = makeCoordinator(provider: provider)
        _ = coordinator.synchronize()

        _ = coordinator.stop()
        provider.displays = []
        let empty = coordinator.synchronize()

        XCTAssertTrue(empty.connectedUUIDs.isEmpty)
        XCTAssertTrue(empty.addedUUIDs.isEmpty)
        XCTAssertTrue(empty.removedUUIDs.isEmpty)
        XCTAssertFalse(empty.enteredZeroDisplayState)
        XCTAssertFalse(empty.reconnected)

        provider.displays = [descriptor(uuid: uuid)]
        let reconnect = coordinator.synchronize()

        XCTAssertEqual(reconnect.addedUUIDs, Set([uuid]))
        XCTAssertTrue(reconnect.reconnected)
    }

    func testStopForcesStandbyAndPreservesSelectedSessionStateAcrossRestart() {
        _ = NSApplication.shared
        let uuid = DisplayUUID(rawValue: "display-a")
        let provider = FakeScreenProvider(displays: [descriptor(uuid: uuid)])
        var created: [OverlayPanel] = []
        let coordinator = makeCoordinator(provider: provider) { descriptor in
            let panel = OverlayPanel(descriptor: descriptor)
            created.append(panel)
            return panel
        }
        _ = coordinator.synchronize()
        let mark = fixtureRectangle()
        let style = MarkStyle(
            color: RGBAColor(red: 0.1, green: 0.2, blue: 0.3),
            strokeWidth: 7,
            opacity: 0.4
        )
        coordinator.apply(.append(mark, to: uuid))
        coordinator.apply(.setTool(.select))
        coordinator.apply(.setStyle(style))
        coordinator.apply(.setMode(.annotation))
        created[0].canvasView.beginGesture(at: NSPoint(x: 768, y: 378))
        created[0].canvasView.endGesture()

        XCTAssertEqual(coordinator.session.selection, mark.id)
        XCTAssertTrue(coordinator.session.canUndo(on: uuid))

        _ = coordinator.stop()

        XCTAssertEqual(coordinator.session.mode, .standby)
        XCTAssertNil(coordinator.session.selection)
        XCTAssertEqual(coordinator.session.toolState.tool, .select)
        XCTAssertEqual(coordinator.session.toolState.style, style)
        XCTAssertEqual(coordinator.session.canvas(for: uuid).marks, [mark])
        XCTAssertTrue(coordinator.session.canUndo(on: uuid))

        _ = coordinator.synchronize()

        XCTAssertEqual(created.count, 2)
        XCTAssertTrue(created[1] !== created[0])
        XCTAssertTrue(created[1].ignoresMouseEvents)
        XCTAssertEqual(created[1].canvasView.session.canvas(for: uuid).marks, [mark])
        XCTAssertEqual(created[1].canvasView.session.mode, .standby)
    }

    func testStopDetachesRegistryBeforeReentrantCleanupCallbacks() {
        _ = NSApplication.shared
        let uuidA = DisplayUUID(rawValue: "a")
        let uuidB = DisplayUUID(rawValue: "b")
        let provider = FakeScreenProvider(displays: [
            descriptor(uuid: uuidA),
            descriptor(uuid: uuidB, x: 1_920),
        ])
        var created: [OverlayPanel] = []
        let coordinator = makeCoordinator(provider: provider) { descriptor in
            let panel = OverlayPanel(descriptor: descriptor)
            created.append(panel)
            return panel
        }
        _ = coordinator.synchronize()
        coordinator.apply(.setMode(.annotation))
        let activePanel = created[0]
        let idlePanel = created[1]
        activePanel.canvasView.onRedrawRequested = {}
        idlePanel.canvasView.onRedrawRequested = {}
        activePanel.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))

        var nestedStopResults: [DisplayStopResult] = []
        var nestedSyncResults: [DisplaySyncResult] = []
        var displaySyncCallbackCount = 0
        var didReenter = false
        coordinator.onDisplaySync = { _ in displaySyncCallbackCount += 1 }
        let reenter = {
            guard !didReenter else { return }
            didReenter = true
            nestedStopResults.append(coordinator.stop())
            nestedSyncResults.append(coordinator.synchronize())
        }
        coordinator.onSessionUpdate = { _ in reenter() }
        coordinator.onBoundaryEvent = { _, event in
            if event == .cancelled {
                reenter()
            }
        }

        let outer = coordinator.stop()

        XCTAssertTrue(didReenter)
        XCTAssertEqual(nestedStopResults, [DisplayStopResult(
            closedOverlayCount: 0,
            remainingOverlayCount: 0,
            activeGestureCount: 0,
            clearedHandlerCount: 0,
            boundHandlerCount: 0
        )])
        XCTAssertEqual(nestedSyncResults, [DisplaySyncResult(
            connectedUUIDs: Set([uuidA, uuidB]),
            addedUUIDs: [],
            removedUUIDs: [],
            pointerDisplay: uuidA,
            hasConnectedDisplays: true,
            enteredZeroDisplayState: false,
            reconnected: false
        )])
        XCTAssertEqual(displaySyncCallbackCount, 1)
        XCTAssertEqual(outer, DisplayStopResult(
            closedOverlayCount: 2,
            remainingOverlayCount: 0,
            activeGestureCount: 1,
            clearedHandlerCount: 6,
            boundHandlerCount: 0
        ))
        XCTAssertTrue(coordinator.overlays.isEmpty)
        XCTAssertFalse(activePanel.isVisible)
        XCTAssertFalse(idlePanel.isVisible)
        XCTAssertFalse(activePanel.canvasView.hasActiveGesture)
        XCTAssertNil(activePanel.canvasView.onSessionUpdate)
        XCTAssertNil(activePanel.canvasView.onBoundaryEvent)
        XCTAssertNil(activePanel.canvasView.onRedrawRequested)
        XCTAssertNil(idlePanel.canvasView.onSessionUpdate)
        XCTAssertNil(idlePanel.canvasView.onBoundaryEvent)
        XCTAssertNil(idlePanel.canvasView.onRedrawRequested)

        _ = coordinator.synchronize()

        XCTAssertEqual(displaySyncCallbackCount, 2)
        XCTAssertEqual(created.count, 4)
        XCTAssertTrue(created[2] !== activePanel)
        XCTAssertTrue(created[3] !== idlePanel)
        XCTAssertTrue(created[2].ignoresMouseEvents)
        XCTAssertTrue(created[3].ignoresMouseEvents)
    }

    func testDuplicateValidDescriptorsCreateOneOverlay() {
        let uuid = DisplayUUID(rawValue: "display-a")
        let display = descriptor(uuid: uuid)
        let provider = FakeScreenProvider(displays: [display, display])
        var created: [FakeOverlay] = []
        let coordinator = makeCoordinator(provider: provider) { descriptor in
            let overlay = FakeOverlay(display: descriptor)
            created.append(overlay)
            return overlay
        }

        let result = coordinator.synchronize()

        XCTAssertEqual(result.connectedUUIDs, Set([uuid]))
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(coordinator.overlays.count, 1)
        XCTAssertEqual(created[0].presentationCount, 1)
    }

    func testPartialDisplayRemovalUsesRealCleanupAndLeavesOtherDisplay() {
        _ = NSApplication.shared
        let removedUUID = DisplayUUID(rawValue: "removed")
        let retainedUUID = DisplayUUID(rawValue: "retained")
        let provider = FakeScreenProvider(displays: [
            descriptor(uuid: removedUUID),
            descriptor(uuid: retainedUUID, x: 1_920),
        ])
        let coordinator = makeCoordinator(provider: provider) { descriptor in
            OverlayPanel(descriptor: descriptor)
        }
        _ = coordinator.synchronize()
        let removedPanel = try! XCTUnwrap(coordinator.overlays[removedUUID] as? OverlayPanel)
        let retainedPanel = try! XCTUnwrap(coordinator.overlays[retainedUUID] as? OverlayPanel)
        let mark = fixtureRectangle()
        coordinator.apply(.append(mark, to: removedUUID))
        coordinator.apply(.setMode(.annotation))
        removedPanel.canvasView.onRedrawRequested = {}

        var sessionUpdates = 0
        var boundaryEvents: [GestureBoundaryEvent] = []
        coordinator.onSessionUpdate = { _ in sessionUpdates += 1 }
        coordinator.onBoundaryEvent = { _, event in boundaryEvents.append(event) }
        removedPanel.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))
        sessionUpdates = 0
        boundaryEvents.removeAll()
        XCTAssertTrue(removedPanel.canvasView.hasActiveGesture)

        provider.displays = [descriptor(uuid: retainedUUID, x: 1_920)]
        coordinator.synchronize()

        XCTAssertEqual(boundaryEvents, [.cancelled])
        XCTAssertEqual(sessionUpdates, 1)
        XCTAssertFalse(removedPanel.canvasView.hasActiveGesture)
        XCTAssertNil(removedPanel.canvasView.onSessionUpdate)
        XCTAssertNil(removedPanel.canvasView.onBoundaryEvent)
        XCTAssertNil(removedPanel.canvasView.onRedrawRequested)
        XCTAssertNil(coordinator.overlays[removedUUID])
        XCTAssertTrue(coordinator.overlays[retainedUUID] as AnyObject? === retainedPanel)
        XCTAssertEqual(coordinator.session.canvas(for: removedUUID).marks, [mark])

        removedPanel.canvasView.endGesture()

        XCTAssertEqual(boundaryEvents, [.cancelled])
        XCTAssertEqual(coordinator.session.canvas(for: removedUUID).marks, [mark])
    }

    func testStopWhileActiveAggregatesCleanupAndForwardsCancellation() {
        _ = NSApplication.shared
        let uuid = DisplayUUID(rawValue: "display-a")
        let provider = FakeScreenProvider(displays: [descriptor(uuid: uuid)])
        let coordinator = makeCoordinator(provider: provider) { descriptor in
            OverlayPanel(descriptor: descriptor)
        }
        _ = coordinator.synchronize()
        coordinator.apply(.setMode(.annotation))
        let panel = try! XCTUnwrap(coordinator.overlays[uuid] as? OverlayPanel)
        panel.canvasView.onRedrawRequested = {}
        var sessionUpdates = 0
        var boundaryEvents: [GestureBoundaryEvent] = []
        coordinator.onSessionUpdate = { _ in sessionUpdates += 1 }
        coordinator.onBoundaryEvent = { _, event in boundaryEvents.append(event) }
        panel.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))
        sessionUpdates = 0
        boundaryEvents.removeAll()

        let result = coordinator.stop()

        XCTAssertEqual(result, DisplayStopResult(
            closedOverlayCount: 1,
            remainingOverlayCount: 0,
            activeGestureCount: 1,
            clearedHandlerCount: 3,
            boundHandlerCount: 0
        ))
        XCTAssertEqual(sessionUpdates, 1)
        XCTAssertEqual(boundaryEvents, [.cancelled])
        XCTAssertFalse(panel.canvasView.hasActiveGesture)
        XCTAssertTrue(coordinator.overlays.isEmpty)
    }

    func testStopWithZeroDisplaysReturnsAllZeroCounts() {
        let provider = FakeScreenProvider(displays: [])
        let coordinator = makeCoordinator(provider: provider)

        let result = coordinator.stop()

        XCTAssertEqual(result, DisplayStopResult(
            closedOverlayCount: 0,
            remainingOverlayCount: 0,
            activeGestureCount: 0,
            clearedHandlerCount: 0,
            boundHandlerCount: 0
        ))
    }

    func testReconnectWithSameUUIDReusesCanvasAcrossChangedFrame() {
        let uuid = DisplayUUID(rawValue: "display-a")
        let first = descriptor(uuid: uuid, x: 0, width: 1_920)
        let second = descriptor(uuid: uuid, x: 40, width: 1_600)
        let provider = FakeScreenProvider(displays: [first])
        var created: [FakeOverlay] = []
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { descriptor in
                let overlay = FakeOverlay(display: descriptor)
                created.append(overlay)
                return overlay
            }
        )

        coordinator.synchronize()
        guard let original = coordinator.overlays[uuid] as? FakeOverlay else {
            return XCTFail("Expected an overlay for the connected display")
        }
        provider.displays = [second]

        coordinator.synchronize()

        XCTAssertTrue(coordinator.overlays[uuid] === original)
        XCTAssertEqual(original.display.frame, second.frame)
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(coordinator.session.canvas(for: uuid), Canvas())
    }

    func testNewlyConnectedOverlayIsPresentedExactlyOnce() {
        let uuid = DisplayUUID(rawValue: "display-a")
        let provider = FakeScreenProvider(displays: [descriptor(uuid: uuid)])
        var created: [FakeOverlay] = []
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { descriptor in
                let overlay = FakeOverlay(display: descriptor)
                created.append(overlay)
                return overlay
            }
        )

        coordinator.synchronize()
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created[0].presentationCount, 1)

        coordinator.synchronize()
        XCTAssertEqual(created[0].presentationCount, 1)
    }

    func testRemovingScreenClosesOnlyItsOverlayAndRetainsItsCanvas() {
        let retainedUUID = DisplayUUID(rawValue: "display-a")
        let removedUUID = DisplayUUID(rawValue: "display-b")
        let retained = descriptor(uuid: retainedUUID, x: 0, width: 1_920)
        let removed = descriptor(uuid: removedUUID, x: 1_920, width: 1_920)
        let provider = FakeScreenProvider(displays: [retained, removed])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { FakeOverlay(display: $0) }
        )
        coordinator.synchronize()
        let mark = Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.2, y: 0.2),
                end: NormalizedPoint(x: 0.8, y: 0.8)
            ),
            style: .default
        )
        coordinator.apply(.append(mark, to: removedUUID))
        let removedOverlay = try! XCTUnwrap(coordinator.overlays[removedUUID] as? FakeOverlay)
        let retainedOverlay = try! XCTUnwrap(coordinator.overlays[retainedUUID] as? FakeOverlay)
        provider.displays = [retained]

        coordinator.synchronize()

        XCTAssertNil(coordinator.overlays[removedUUID])
        XCTAssertTrue(removedOverlay.didClose)
        XCTAssertFalse(retainedOverlay.didClose)
        XCTAssertEqual(coordinator.session.canvas(for: removedUUID).marks, [mark])
    }

    func testStandbyOverlayIgnoresMouseEvents() throws {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))

        XCTAssertTrue(panel.ignoresMouseEvents)

        panel.setMode(.annotation)
        XCTAssertFalse(panel.ignoresMouseEvents)

        panel.setMode(.standby)
        XCTAssertTrue(panel.ignoresMouseEvents)
    }

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
        XCTAssertEqual(panel.canvasView.cursorPlan, .clickThrough)
        XCTAssertEqual(panel.canvasView.session.canvas(for: panel.display.uuid).marks, [mark])
    }

    func testOverlayStopAndClearReturnsObservableCleanupCounts() {
        _ = NSApplication.shared
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

    func testDefaultOverlayStopAndClearIsObservableNoOp() {
        let fake = ExistingOverlayConformingFake(display: descriptor(uuid: DisplayUUID(rawValue: "display-a")))

        let result = fake.stopAndClear()

        XCTAssertEqual(result, OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: false
        ))
    }

    func testFreshOverlayStopAndClearReportsZeroInstalledHandlers() {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))

        let first = panel.stopAndClear()
        let second = panel.stopAndClear()

        XCTAssertEqual(first, OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: true
        ))
        XCTAssertEqual(second, OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: false
        ))
    }

    func testPartialOverlayStopAndClearReportsInstalledHandlerCount() {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        panel.canvasView.onBoundaryEvent = { _ in }

        let result = panel.stopAndClear()

        XCTAssertEqual(result.clearedHandlerCount, 1)
        XCTAssertEqual(result.remainingHandlerCount, 0)
        XCTAssertTrue(result.didClose)
        XCTAssertNil(panel.canvasView.onSessionUpdate)
        XCTAssertNil(panel.canvasView.onBoundaryEvent)
        XCTAssertNil(panel.canvasView.onRedrawRequested)
    }

    func testRealOverlayStopAndClearCancelsGestureAndClearsHandlers() {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        panel.update(session: session)

        var sessionUpdates = 0
        var boundaryEvents = 0
        var redrawRequests = 0
        panel.setEventHandlers(
            onSessionUpdate: { _ in sessionUpdates += 1 },
            onBoundaryEvent: { _ in boundaryEvents += 1 }
        )
        panel.canvasView.onRedrawRequested = { redrawRequests += 1 }
        panel.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))
        sessionUpdates = 0
        boundaryEvents = 0
        redrawRequests = 0

        let result = panel.stopAndClear()

        XCTAssertTrue(result.cancelledActiveGesture)
        XCTAssertEqual(result.clearedHandlerCount, 3)
        XCTAssertEqual(result.remainingHandlerCount, 0)
        XCTAssertTrue(result.didClose)
        XCTAssertFalse(panel.canvasView.hasActiveGesture)
        XCTAssertNil(panel.canvasView.onSessionUpdate)
        XCTAssertNil(panel.canvasView.onBoundaryEvent)
        XCTAssertNil(panel.canvasView.onRedrawRequested)
        XCTAssertEqual(sessionUpdates, 1)
        XCTAssertEqual(boundaryEvents, 1)
        XCTAssertEqual(redrawRequests, 1)
    }

    func testDirectCloseCancelsActiveGestureAndClearsHandlersExactlyOnce() {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        panel.update(session: session)

        var sessionUpdates = 0
        var boundaryEvents = 0
        var redrawRequests = 0
        panel.setEventHandlers(
            onSessionUpdate: { _ in sessionUpdates += 1 },
            onBoundaryEvent: { _ in boundaryEvents += 1 }
        )
        panel.canvasView.onRedrawRequested = { redrawRequests += 1 }
        panel.show()
        XCTAssertTrue(panel.isVisible)
        panel.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))
        sessionUpdates = 0
        boundaryEvents = 0
        redrawRequests = 0

        panel.close()
        panel.close()

        XCTAssertFalse(panel.canvasView.hasActiveGesture)
        XCTAssertNil(panel.canvasView.onSessionUpdate)
        XCTAssertNil(panel.canvasView.onBoundaryEvent)
        XCTAssertNil(panel.canvasView.onRedrawRequested)
        XCTAssertEqual(sessionUpdates, 1)
        XCTAssertEqual(boundaryEvents, 1)
        XCTAssertEqual(redrawRequests, 1)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.stopAndClear(), OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: false
        ))
    }

    func testClosedOverlayCannotShowOrRebindHandlers() {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        panel.show()
        XCTAssertTrue(panel.isVisible)

        let first = panel.stopAndClear()
        panel.show()
        panel.setEventHandlers(onSessionUpdate: { _ in }, onBoundaryEvent: { _ in })

        XCTAssertTrue(first.didClose)
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(panel.canvasView.onSessionUpdate)
        XCTAssertNil(panel.canvasView.onBoundaryEvent)
        XCTAssertEqual(panel.stopAndClear(), OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: false
        ))
    }

    func testStopAndClearIsReentrancySafeDuringCancellationCallbacks() {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        panel.update(session: session)

        var innerResult: OverlayCleanupResult?
        var reentrantHandlerWasBound = false
        var visibleAfterReentrantCalls = false
        panel.setEventHandlers(
            onSessionUpdate: { _ in },
            onBoundaryEvent: { [weak panel] event in
                guard event == .cancelled, let panel else { return }
                panel.canvasView.onSessionUpdate = nil
                panel.setEventHandlers(
                    onSessionUpdate: { _ in },
                    onBoundaryEvent: { _ in }
                )
                reentrantHandlerWasBound = panel.canvasView.onSessionUpdate != nil
                innerResult = panel.stopAndClear()
                panel.close()
                panel.show()
                visibleAfterReentrantCalls = panel.isVisible
            }
        )
        panel.canvasView.onRedrawRequested = {}
        panel.show()
        panel.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))

        let outerResult = panel.stopAndClear()

        XCTAssertEqual(innerResult, OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: false
        ))
        XCTAssertFalse(reentrantHandlerWasBound)
        XCTAssertTrue(visibleAfterReentrantCalls)
        XCTAssertTrue(outerResult.cancelledActiveGesture)
        XCTAssertEqual(outerResult.clearedHandlerCount, 3)
        XCTAssertEqual(outerResult.remainingHandlerCount, 0)
        XCTAssertTrue(outerResult.didClose)
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(panel.canvasView.onSessionUpdate)
        XCTAssertNil(panel.canvasView.onBoundaryEvent)
        XCTAssertNil(panel.canvasView.onRedrawRequested)
        panel.show()
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.stopAndClear(), OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: false
        ))
    }

    private func makeCoordinator(
        provider: FakeScreenProvider,
        overlayFactory: @escaping DisplayCoordinator.OverlayFactory = { FakeOverlay(display: $0) }
    ) -> DisplayCoordinator {
        DisplayCoordinator(screenProvider: provider, overlayFactory: overlayFactory)
    }

    private func descriptor(uuid: DisplayUUID, x: Double = 0, width: Double = 1_920) -> DisplayDescriptor {
        DisplayDescriptor(
            uuid: uuid,
            frame: DisplayFrame(x: x, y: 0, width: width, height: 1_080),
            visibleFrame: DisplayFrame(x: x, y: 24, width: width, height: 1_056),
            scaleFactor: 2
        )
    }

    private func fixtureRectangle() -> Mark {
        Mark(
            geometry: .rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.3)),
            style: .default
        )
    }
}

@MainActor
private final class FakeScreenProvider: ScreenProviding {
    var displays: [DisplayDescriptor]

    init(displays: [DisplayDescriptor]) {
        self.displays = displays
    }

    func currentDisplays() -> [DisplayDescriptor] { displays }
    func pointerDisplay() -> DisplayUUID? { displays.first?.uuid }
}

@MainActor
private final class FakeOverlay: OverlayPresenting {
    var display: DisplayDescriptor
    var didClose = false
    var presentationCount = 0
    var closeCount = 0
    var cancelCount = 0
    private var didClear = false

    init(display: DisplayDescriptor) {
        self.display = display
    }

    func update(display: DisplayDescriptor) {
        self.display = display
    }

    func update(session: PointerSession) {}
    func setMode(_ mode: PointerMode) {}
    func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {}
    func show() { presentationCount += 1 }
    func cancelActiveGesture() { cancelCount += 1 }
    func close() {
        guard !didClose else { return }
        didClose = true
        closeCount += 1
    }
    func stopAndClear() -> OverlayCleanupResult {
        guard !didClear else {
            return OverlayCleanupResult(
                cancelledActiveGesture: false,
                clearedHandlerCount: 0,
                remainingHandlerCount: 0,
                didClose: false
            )
        }
        didClear = true
        return OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 3,
            remainingHandlerCount: 0,
            didClose: false
        )
    }
}

@MainActor
private final class RecordingOverlay: OverlayPresenting {
    private let panel: OverlayPanel
    var closeCount = 0

    var display: DisplayDescriptor { panel.display }

    init(display: DisplayDescriptor) {
        panel = OverlayPanel(descriptor: display)
        panel.setEventHandlers(onSessionUpdate: { _ in }, onBoundaryEvent: { _ in })
        panel.canvasView.onRedrawRequested = {}
    }

    func update(display: DisplayDescriptor) {
        panel.update(display: display)
    }

    func update(session: PointerSession) {
        panel.update(session: session)
    }

    func setMode(_ mode: PointerMode) {
        panel.setMode(mode)
    }

    func cancelActiveGesture() {
        panel.cancelActiveGesture()
    }

    func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {
        panel.setEventHandlers(onSessionUpdate: onSessionUpdate, onBoundaryEvent: onBoundaryEvent)
    }

    func show() {
        panel.show()
    }

    func close() {
        panel.close()
    }

    func stopAndClear() -> OverlayCleanupResult {
        let result = panel.stopAndClear()
        if result.didClose {
            closeCount += 1
        }
        return result
    }
}

@MainActor
private final class ExistingOverlayConformingFake: OverlayPresenting {
    var display: DisplayDescriptor

    init(display: DisplayDescriptor) {
        self.display = display
    }

    func update(display: DisplayDescriptor) {
        self.display = display
    }

    func update(session: PointerSession) {}
    func setMode(_ mode: PointerMode) {}
    func close() {}
}
