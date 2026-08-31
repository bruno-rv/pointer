import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class CanvasIntegrationHarnessTests: XCTestCase {
    func testHarnessDrivesRealCanvasAndCommandRoutesForArrowAndRectangle() throws {
        let fixture = DeterministicInteractionFixture.oneDisplay()
        let harness = fixture.makeHarness()
        let sync = harness.synchronizeDisplays()
        let display = try XCTUnwrap(sync.connectedUUIDs.first)
        let overlay = try XCTUnwrap(fixture.displayCoordinator.overlays[display] as? OverlayPanel)
        _ = fixture.assertConvergence(harness, on: display)

        var boundaryEvents: [GestureBoundaryEvent] = []
        var activeDraftAtBegin: [Bool] = []
        var committedCountsAtCommit: [Int] = []
        let previousBoundaryHandler = fixture.displayCoordinator.onBoundaryEvent
        fixture.displayCoordinator.onBoundaryEvent = { display, event in
            previousBoundaryHandler?(display, event)
            boundaryEvents.append(event)
            switch event {
            case .began:
                activeDraftAtBegin.append(overlay.canvasView.renderPlan.activeDraft != nil)
            case .committed:
                committedCountsAtCommit.append(overlay.canvasView.renderPlan.committedMarks.count)
                XCTAssertNil(overlay.canvasView.renderPlan.activeDraft)
            case .cancelled:
                break
            }
        }

        harness.route(.setMode(.annotation))
        harness.route(.setTool(.arrow))
        try harness.beginGesture(at: NSPoint(x: 100, y: 100), on: display)
        _ = fixture.assertConvergence(harness, on: display)
        XCTAssertEqual(boundaryEvents, [.began])
        try harness.continueGesture(to: NSPoint(x: 300, y: 240), on: display)
        _ = fixture.assertConvergence(harness, on: display)
        XCTAssertEqual(boundaryEvents, [.began])
        try harness.endGesture(on: display)
        _ = fixture.assertConvergence(harness, on: display)
        XCTAssertEqual(boundaryEvents, [.began, .committed])

        harness.route(.setTool(.rectangle))
        try harness.beginGesture(at: NSPoint(x: 420, y: 320), on: display)
        _ = fixture.assertConvergence(harness, on: display)
        try harness.continueGesture(to: NSPoint(x: 700, y: 560), on: display)
        _ = fixture.assertConvergence(harness, on: display)
        try harness.endGesture(on: display)
        _ = fixture.assertConvergence(harness, on: display)

        let snapshot = harness.snapshot()
        XCTAssertEqual(snapshot.mode, .annotation)
        XCTAssertEqual(snapshot.selectedTool, .rectangle)
        XCTAssertEqual(snapshot.marksByDisplay[display]?.count, 2)
        XCTAssertEqual(snapshot.previewMarksByDisplay[display]?.count, 2)
        XCTAssertTrue(snapshot.undoAvailable)
        XCTAssertNil(snapshot.activeDraftMarkID)
        XCTAssertEqual(boundaryEvents, [.began, .committed, .began, .committed])
        XCTAssertEqual(activeDraftAtBegin, [true, true])
        XCTAssertEqual(committedCountsAtCommit, [1, 2])
        XCTAssertTrue(fixture.displayCoordinator.overlays[display] as AnyObject? === overlay)
        XCTAssertTrue(overlay.canvasView === (fixture.displayCoordinator.overlays[display] as? OverlayPanel)?.canvasView)
        XCTAssertEqual(overlay.canvasView.renderPlan.committedMarks.count, 2)
    }

    func testCancelRestoresSelectionAndStaleMouseUpCannotCommit() throws {
        let fixture = DeterministicInteractionFixture.oneDisplay()
        let harness = fixture.makeHarness()
        let display = try XCTUnwrap(harness.synchronizeDisplays().connectedUUIDs.first)
        _ = fixture.assertConvergence(harness, on: display)
        var boundaryEvents: [GestureBoundaryEvent] = []
        let previousBoundaryHandler = fixture.displayCoordinator.onBoundaryEvent
        fixture.displayCoordinator.onBoundaryEvent = { display, event in
            previousBoundaryHandler?(display, event)
            boundaryEvents.append(event)
        }

        harness.route(.setMode(.annotation))
        harness.route(.setTool(.arrow))
        try harness.beginGesture(at: NSPoint(x: 100, y: 100), on: display)
        _ = fixture.assertConvergence(harness, on: display)
        try harness.continueGesture(to: NSPoint(x: 400, y: 300), on: display)
        _ = fixture.assertConvergence(harness, on: display)
        try harness.endGesture(on: display)
        _ = fixture.assertConvergence(harness, on: display)
        let committedMarkID = try XCTUnwrap(harness.snapshot().marksByDisplay[display]?.first?.id)

        harness.route(.setTool(.select))
        try harness.beginGesture(at: NSPoint(x: 250, y: 200), on: display)
        _ = fixture.assertConvergence(harness, on: display)
        try harness.endGesture(on: display)
        _ = fixture.assertConvergence(harness, on: display)
        XCTAssertEqual(harness.snapshot().selection, committedMarkID)

        harness.route(.setTool(.rectangle))
        try harness.beginGesture(at: NSPoint(x: 500, y: 400), on: display)
        _ = fixture.assertConvergence(harness, on: display)
        try harness.continueGesture(to: NSPoint(x: 800, y: 600), on: display)
        _ = fixture.assertConvergence(harness, on: display)
        XCTAssertNotNil(harness.snapshot().activeDraftMarkID)
        try harness.cancelGesture(on: display)
        _ = fixture.assertConvergence(harness, on: display)
        try harness.endGesture(on: display)
        _ = fixture.assertConvergence(harness, on: display)

        let snapshot = harness.snapshot()
        XCTAssertEqual(snapshot.marksByDisplay[display]?.map(\.id), [committedMarkID])
        XCTAssertEqual(snapshot.previewMarksByDisplay[display]?.map(\.id), [committedMarkID])
        XCTAssertEqual(snapshot.selection, committedMarkID)
        XCTAssertTrue(snapshot.undoAvailable)
        XCTAssertNil(snapshot.activeDraftMarkID)
        XCTAssertEqual(boundaryEvents, [
            .began, .committed,
            .began, .committed,
            .began, .cancelled,
        ])
    }

    func testStandbyKeepsCommittedCanvasButHidesSelectionChrome() throws {
        let fixture = DeterministicInteractionFixture.oneDisplay()
        let harness = fixture.makeHarness()
        let display = try XCTUnwrap(harness.synchronizeDisplays().connectedUUIDs.first)
        _ = fixture.assertConvergence(harness, on: display)

        harness.route(.setMode(.annotation))
        harness.route(.setTool(.arrow))
        try harness.beginGesture(at: NSPoint(x: 100, y: 100), on: display)
        _ = fixture.assertConvergence(harness, on: display)
        try harness.continueGesture(to: NSPoint(x: 400, y: 300), on: display)
        _ = fixture.assertConvergence(harness, on: display)
        try harness.endGesture(on: display)
        _ = fixture.assertConvergence(harness, on: display)
        harness.route(.setTool(.select))
        try harness.beginGesture(at: NSPoint(x: 250, y: 200), on: display)
        _ = fixture.assertConvergence(harness, on: display)
        try harness.endGesture(on: display)
        _ = fixture.assertConvergence(harness, on: display)
        XCTAssertNotNil(harness.snapshot().selection)

        harness.route(.setMode(.standby))
        _ = fixture.assertConvergence(harness, on: display)
        let snapshot = harness.snapshot()
        XCTAssertEqual(snapshot.marksByDisplay[display]?.count, 1)
        XCTAssertEqual(snapshot.previewMarksByDisplay[display]?.count, 1)
        XCTAssertNil(snapshot.selection)
        XCTAssertNil(snapshot.activeDraftMarkID)
        XCTAssertTrue(snapshot.handleInventory.resize.handles.isEmpty)
        XCTAssertFalse(snapshot.handleInventory.selection.isVisible)
        XCTAssertFalse(snapshot.handleInventory.contextualDeleteVisible)
        XCTAssertEqual(snapshot.mode, .standby)
        let overlay = try XCTUnwrap(fixture.displayCoordinator.overlays[display] as? OverlayPanel)
        XCTAssertTrue(overlay.ignoresMouseEvents)
        XCTAssertEqual(overlay.canvasView.session.mode, .standby)
        XCTAssertEqual(overlay.canvasView.renderPlan.committedMarks.count, 1)
    }

    func testEmptyAndMalformedDisplaysFailClosed() throws {
        let empty = DeterministicInteractionFixture.empty()
        let emptyHarness = empty.makeHarness()
        let emptySync = emptyHarness.synchronizeDisplays()
        XCTAssertFalse(emptySync.hasConnectedDisplays)
        XCTAssertTrue(emptySync.connectedUUIDs.isEmpty)
        XCTAssertThrowsError(
            try emptyHarness.beginGesture(
                at: .zero,
                on: DisplayUUID(rawValue: "missing")
            )
        ) { error in
            XCTAssertEqual(
                error as? DeterministicInteractionError,
                .invalidDisplay(DisplayUUID(rawValue: "missing"))
            )
        }

        let malformed = DeterministicInteractionFixture.malformedDisplay()
        let malformedHarness = malformed.makeHarness()
        let malformedSync = malformedHarness.synchronizeDisplays()
        XCTAssertFalse(malformedSync.hasConnectedDisplays)
        XCTAssertThrowsError(
            try malformedHarness.beginGesture(
                at: .zero,
                on: DisplayUUID(rawValue: "")
            )
        ) { error in
            XCTAssertEqual(
                error as? DeterministicInteractionError,
                .invalidDisplay(DisplayUUID(rawValue: ""))
            )
        }
    }

    func testSnapshotHidesHandlesWhenSelectedDisplayIsDisconnectedDespiteStaleOtherPlan() throws {
        let fixture = DeterministicInteractionFixture.twoDisplays()
        let harness = fixture.makeHarness()
        let sync = harness.synchronizeDisplays()
        let displays = sync.connectedUUIDs.sorted { $0.rawValue < $1.rawValue }
        let displayA = try XCTUnwrap(displays.first)
        let displayB = try XCTUnwrap(displays.last)
        _ = fixture.assertConvergence(harness, on: displayA)
        _ = fixture.assertConvergence(harness, on: displayB)

        harness.route(.setMode(.annotation))
        harness.route(.setTool(.arrow))
        try harness.beginGesture(at: NSPoint(x: 100, y: 100), on: displayA)
        _ = fixture.assertConvergence(harness, on: displayA)
        try harness.continueGesture(to: NSPoint(x: 400, y: 300), on: displayA)
        _ = fixture.assertConvergence(harness, on: displayA)
        try harness.endGesture(on: displayA)
        _ = fixture.assertConvergence(harness, on: displayA)

        try harness.beginGesture(at: NSPoint(x: 100, y: 100), on: displayB)
        _ = fixture.assertConvergence(harness, on: displayB)
        try harness.continueGesture(to: NSPoint(x: 400, y: 300), on: displayB)
        _ = fixture.assertConvergence(harness, on: displayB)
        try harness.endGesture(on: displayB)
        _ = fixture.assertConvergence(harness, on: displayB)

        harness.route(.setTool(.select))
        try harness.beginGesture(at: NSPoint(x: 250, y: 200), on: displayB)
        _ = fixture.assertConvergence(harness, on: displayB)
        try harness.endGesture(on: displayB)
        let bSelectedSession = fixture.displayCoordinator.session
        let bMarkID = try XCTUnwrap(bSelectedSession.selection)
        _ = fixture.assertConvergence(harness, on: displayB)

        harness.route(.setTool(.rectangle))
        try harness.beginGesture(at: NSPoint(x: 500, y: 400), on: displayB)
        try harness.continueGesture(to: NSPoint(x: 800, y: 600), on: displayB)
        let staleBDraftSession = try XCTUnwrap(
            (fixture.displayCoordinator.overlays[displayB] as? OverlayPanel)?.canvasView.session
        )
        XCTAssertTrue(staleBDraftSession.hasActiveGesture(on: displayB))
        try harness.cancelGesture(on: displayB)
        _ = fixture.assertConvergence(harness, on: displayB)

        harness.route(.setTool(.select))
        try harness.beginGesture(at: NSPoint(x: 250, y: 200), on: displayA)
        _ = fixture.assertConvergence(harness, on: displayA)
        try harness.endGesture(on: displayA)
        let aSelectedMarkID = try XCTUnwrap(harness.snapshot().selection)
        XCTAssertNotEqual(aSelectedMarkID, bMarkID)
        _ = fixture.assertConvergence(harness, on: displayA)

        fixture.screenProvider.displays = [try XCTUnwrap(fixture.otherDescriptor)]
        fixture.screenProvider.pointerUUID = displayB
        _ = harness.synchronizeDisplays()
        _ = fixture.assertConvergence(harness, on: displayB)

        // Reintroduce only a stale, non-selected overlay plan through the real
        // OverlayPanel update API. The harness must not fall back to it when
        // the session's selected display is no longer connected.
        let remainingOverlay = try XCTUnwrap(
            fixture.displayCoordinator.overlays[displayB] as? OverlayPanel
        )
        remainingOverlay.update(session: staleBDraftSession)

        let snapshot = harness.snapshot()
        XCTAssertEqual(snapshot.selection, aSelectedMarkID)
        XCTAssertNil(snapshot.activeDraftMarkID)
        XCTAssertNil(snapshot.handleInventory.selection.selectedMarkID)
        XCTAssertFalse(snapshot.handleInventory.selection.isVisible)
        XCTAssertTrue(snapshot.handleInventory.resize.handles.isEmpty)
        XCTAssertFalse(snapshot.handleInventory.contextualDeleteVisible)
        XCTAssertEqual(snapshot.connectedDisplays, [displayB])
    }

    func testReconnectPreservesMarksAndRecreatesRealOverlayForStableUUID() throws {
        let fixture = DeterministicInteractionFixture.disconnectedAndReconnected()
        let harness = fixture.makeHarness()
        _ = harness.synchronizeDisplays()
        let display = try XCTUnwrap(fixture.reconnectedDescriptor?.uuid)
        let initialOverlay = try XCTUnwrap(fixture.displayCoordinator.overlays[display] as? OverlayPanel)
        let initialCanvas = initialOverlay.canvasView
        let other = try XCTUnwrap(fixture.otherDescriptor)
        let initialOtherOverlay = try XCTUnwrap(fixture.displayCoordinator.overlays[other.uuid] as? OverlayPanel)
        _ = fixture.assertConvergence(harness, on: display)

        harness.route(.setMode(.annotation))
        try harness.beginGesture(at: NSPoint(x: 100, y: 100), on: display)
        _ = fixture.assertConvergence(harness, on: display)
        try harness.continueGesture(to: NSPoint(x: 400, y: 300), on: display)
        _ = fixture.assertConvergence(harness, on: display)
        try harness.endGesture(on: display)
        _ = fixture.assertConvergence(harness, on: display)
        XCTAssertEqual(harness.snapshot().marksByDisplay[other.uuid, default: []].count, 0)

        fixture.screenProvider.displays = [other]
        fixture.screenProvider.pointerUUID = other.uuid
        let disconnected = harness.synchronizeDisplays()
        XCTAssertEqual(disconnected.connectedUUIDs, [other.uuid])
        XCTAssertTrue(fixture.displayCoordinator.overlays[display] == nil)
        XCTAssertTrue((fixture.displayCoordinator.overlays[other.uuid] as? OverlayPanel) === initialOtherOverlay)
        _ = fixture.assertConvergence(harness, on: other.uuid)
        let disconnectedSnapshot = harness.snapshot()
        XCTAssertEqual(disconnectedSnapshot.marksByDisplay[display]?.count, 1)
        XCTAssertTrue(disconnectedSnapshot.marksByDisplay.keys.contains(display))
        XCTAssertEqual(disconnectedSnapshot.previewMarksByDisplay[display]?.count, 1)
        XCTAssertTrue(disconnectedSnapshot.undoAvailable)
        XCTAssertEqual(disconnectedSnapshot.marksByDisplay[other.uuid, default: []].count, 0)

        fixture.screenProvider.displays = [other, try XCTUnwrap(fixture.reconnectedDescriptor)]
        fixture.screenProvider.pointerUUID = display
        let reconnected = harness.synchronizeDisplays()
        XCTAssertTrue(reconnected.connectedUUIDs.contains(display))
        XCTAssertEqual(reconnected.connectedUUIDs, [display, other.uuid])
        _ = fixture.assertConvergence(harness, on: display)

        let recreatedOverlay = try XCTUnwrap(fixture.displayCoordinator.overlays[display] as? OverlayPanel)
        XCTAssertFalse(recreatedOverlay === initialOverlay)
        XCTAssertFalse(recreatedOverlay.canvasView === initialCanvas)
        XCTAssertEqual(harness.snapshot().marksByDisplay[display]?.count, 1)
        XCTAssertEqual(harness.snapshot().marksByDisplay[other.uuid, default: []].count, 0)
        XCTAssertTrue((fixture.displayCoordinator.overlays[other.uuid] as? OverlayPanel) === initialOtherOverlay)
        XCTAssertEqual(recreatedOverlay.canvasView.renderPlan.committedMarks.count, 1)
        _ = fixture.assertConvergence(harness, on: display)
    }
}
