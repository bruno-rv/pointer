import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class OverlappingMarksHarnessTests: XCTestCase {
    func testLatestOverlappingMarkIsSelectedDeletedAndUnderlyingReselected() throws {
        let fixture = DeterministicInteractionFixture.oneDisplay()
        let harness = fixture.makeHarness()
        let display = try XCTUnwrap(harness.synchronizeDisplays().connectedUUIDs.first)
        assertConvergence(fixture, harness, on: [display])

        harness.route(.setMode(.annotation))
        assertConvergence(fixture, harness, on: [display])

        try draw(
            tool: .rectangle,
            from: NSPoint(x: 400, y: 240),
            to: NSPoint(x: 1_200, y: 840),
            on: display,
            fixture: fixture,
            harness: harness
        )
        try draw(
            tool: .ellipse,
            from: NSPoint(x: 520, y: 300),
            to: NSPoint(x: 1_400, y: 900),
            on: display,
            fixture: fixture,
            harness: harness
        )

        let created = harness.snapshot().marksByDisplay[display, default: []]
        XCTAssertEqual(created.count, 2)
        let underlyingID = try XCTUnwrap(created.first?.id)
        let topmostID = try XCTUnwrap(created.last?.id)

        harness.route(.setTool(.select))
        assertConvergence(fixture, harness, on: [display])
        let sharedPoint = NSPoint(x: 850, y: 560)
        try harness.beginGesture(at: sharedPoint, on: display)
        assertConvergence(fixture, harness, on: [display])
        XCTAssertEqual(harness.snapshot().selection, topmostID)
        try harness.endGesture(on: display)
        assertConvergence(fixture, harness, on: [display])
        XCTAssertEqual(harness.snapshot().selection, topmostID)
        XCTAssertEqual(fixture.displayCoordinator.session.selectedDisplay, display)

        let selectedOverlay = try XCTUnwrap(
            fixture.displayCoordinator.overlays[display] as? OverlayPanel
        )
        XCTAssertEqual(
            selectedOverlay.canvasView.renderPlan.handles.selection.selectedMarkID,
            topmostID
        )
        XCTAssertTrue(selectedOverlay.canvasView.renderPlan.handles.selection.isVisible)

        let orderBeforeMove = harness.snapshot().marksByDisplay[display, default: []].map(\.id)
        try harness.beginGesture(at: sharedPoint, on: display)
        assertConvergence(fixture, harness, on: [display])
        try harness.continueGesture(to: NSPoint(x: 900, y: 600), on: display)
        let duringMove = harness.snapshot()
        assertConvergence(fixture, harness, on: [display])
        XCTAssertEqual(
            duringMove.previewMarksByDisplay[display, default: []].map(\.id),
            orderBeforeMove
        )
        XCTAssertEqual(duringMove.selection, topmostID)
        XCTAssertEqual(fixture.displayCoordinator.session.canvas(for: display).marks.map(\.id), orderBeforeMove)
        try harness.endGesture(on: display)
        assertConvergence(fixture, harness, on: [display])
        let afterMove = harness.snapshot().marksByDisplay[display, default: []]
        XCTAssertEqual(afterMove.map(\.id), orderBeforeMove)
        XCTAssertEqual(harness.snapshot().selection, topmostID)
        XCTAssertNotEqual(afterMove, created)

        let committedBeforeCancel = afterMove
        try harness.beginGesture(at: NSPoint(x: 900, y: 600), on: display)
        assertConvergence(fixture, harness, on: [display])
        try harness.continueGesture(to: NSPoint(x: 970, y: 650), on: display)
        let duringCancel = harness.snapshot()
        assertConvergence(fixture, harness, on: [display])
        XCTAssertEqual(
            duringCancel.marksByDisplay[display, default: []],
            committedBeforeCancel
        )
        XCTAssertNotEqual(
            duringCancel.previewMarksByDisplay[display, default: []],
            committedBeforeCancel
        )
        try harness.cancelGesture(on: display)
        assertConvergence(fixture, harness, on: [display])
        let afterCancel = harness.snapshot()
        XCTAssertEqual(afterCancel.marksByDisplay[display, default: []], committedBeforeCancel)
        XCTAssertEqual(afterCancel.previewMarksByDisplay[display, default: []], committedBeforeCancel)
        XCTAssertEqual(afterCancel.selection, topmostID)
        XCTAssertEqual(afterCancel.marksByDisplay[display]?.map(\.id), [underlyingID, topmostID])

        XCTAssertTrue(harness.routeLocalKey(keyCode: 51))
        assertConvergence(fixture, harness, on: [display])
        let afterDelete = harness.snapshot()
        XCTAssertEqual(afterDelete.marksByDisplay[display]?.map(\.id), [underlyingID])
        XCTAssertNil(afterDelete.selection)
        XCTAssertEqual(afterDelete.previewMarksByDisplay[display]?.map(\.id), [underlyingID])

        try harness.beginGesture(at: sharedPoint, on: display)
        assertConvergence(fixture, harness, on: [display])
        XCTAssertEqual(harness.snapshot().selection, underlyingID)
        try harness.endGesture(on: display)
        assertConvergence(fixture, harness, on: [display])
        XCTAssertEqual(harness.snapshot().selection, underlyingID)
        XCTAssertEqual(fixture.displayCoordinator.session.selectedDisplay, display)
    }

    func testOverlappingGeometryRemainsDisplayLocalWhenSelectingEachDisplay() throws {
        let fixture = DeterministicInteractionFixture.twoDisplays()
        let harness = fixture.makeHarness()
        let displays = harness.synchronizeDisplays().connectedUUIDs.sorted {
            $0.rawValue < $1.rawValue
        }
        let displayA = try XCTUnwrap(displays.first)
        let displayB = try XCTUnwrap(displays.last)
        assertConvergence(fixture, harness, on: displays)

        harness.route(.setMode(.annotation))
        assertConvergence(fixture, harness, on: displays)
        try draw(
            tool: .rectangle,
            from: NSPoint(x: 400, y: 240),
            to: NSPoint(x: 1_200, y: 840),
            on: displayA,
            fixture: fixture,
            harness: harness,
            allDisplays: displays
        )
        try draw(
            tool: .ellipse,
            from: NSPoint(x: 520, y: 300),
            to: NSPoint(x: 1_400, y: 900),
            on: displayA,
            fixture: fixture,
            harness: harness,
            allDisplays: displays
        )
        try draw(
            tool: .rectangle,
            from: NSPoint(x: 400, y: 240),
            to: NSPoint(x: 1_200, y: 840),
            on: displayB,
            fixture: fixture,
            harness: harness,
            allDisplays: displays
        )
        try draw(
            tool: .ellipse,
            from: NSPoint(x: 520, y: 300),
            to: NSPoint(x: 1_400, y: 900),
            on: displayB,
            fixture: fixture,
            harness: harness,
            allDisplays: displays
        )

        let marksA = harness.snapshot().marksByDisplay[displayA, default: []]
        let marksB = harness.snapshot().marksByDisplay[displayB, default: []]
        XCTAssertEqual(marksA.count, 2)
        XCTAssertEqual(marksB.count, 2)
        let sharedPoint = NSPoint(x: 850, y: 560)

        harness.route(.setTool(.select))
        assertConvergence(fixture, harness, on: displays)
        try harness.beginGesture(at: sharedPoint, on: displayB)
        assertConvergence(fixture, harness, on: displays)
        try harness.endGesture(on: displayB)
        assertConvergence(fixture, harness, on: displays)
        let selectedB = harness.snapshot()
        let topBID = try XCTUnwrap(marksB.last?.id)
        XCTAssertEqual(selectedB.selection, topBID)
        XCTAssertEqual(fixture.displayCoordinator.session.selectedDisplay, displayB)
        XCTAssertEqual(selectedB.marksByDisplay[displayA], marksA)
        XCTAssertEqual(selectedB.marksByDisplay[displayB], marksB)
        let overlayA = try XCTUnwrap(fixture.displayCoordinator.overlays[displayA] as? OverlayPanel)
        let overlayB = try XCTUnwrap(fixture.displayCoordinator.overlays[displayB] as? OverlayPanel)
        XCTAssertFalse(overlayA.canvasView.renderPlan.handles.selection.isVisible)
        XCTAssertEqual(overlayB.canvasView.renderPlan.handles.selection.selectedMarkID, topBID)
        XCTAssertTrue(overlayB.canvasView.renderPlan.handles.selection.isVisible)

        try harness.beginGesture(at: sharedPoint, on: displayA)
        assertConvergence(fixture, harness, on: displays)
        try harness.endGesture(on: displayA)
        assertConvergence(fixture, harness, on: displays)
        let selectedA = harness.snapshot()
        let topAID = try XCTUnwrap(marksA.last?.id)
        XCTAssertEqual(selectedA.selection, topAID)
        XCTAssertEqual(fixture.displayCoordinator.session.selectedDisplay, displayA)
        XCTAssertEqual(selectedA.marksByDisplay[displayA], marksA)
        XCTAssertEqual(selectedA.marksByDisplay[displayB], marksB)
        XCTAssertEqual(overlayA.canvasView.renderPlan.handles.selection.selectedMarkID, topAID)
        XCTAssertTrue(overlayA.canvasView.renderPlan.handles.selection.isVisible)
        XCTAssertFalse(overlayB.canvasView.renderPlan.handles.selection.isVisible)
    }

    private func draw(
        tool: PointerTool,
        from start: NSPoint,
        to end: NSPoint,
        on display: DisplayUUID,
        fixture: DeterministicInteractionFixture,
        harness: DeterministicInteractionHarness,
        allDisplays: [DisplayUUID]? = nil
    ) throws {
        let displays = allDisplays ?? [display]
        harness.route(.setTool(tool))
        assertConvergence(fixture, harness, on: displays)
        try harness.beginGesture(at: start, on: display)
        assertConvergence(fixture, harness, on: displays)
        try harness.continueGesture(to: end, on: display)
        assertConvergence(fixture, harness, on: displays)
        try harness.endGesture(on: display)
        assertConvergence(fixture, harness, on: displays)
    }

    private func assertConvergence(
        _ fixture: DeterministicInteractionFixture,
        _ harness: DeterministicInteractionHarness,
        on displays: [DisplayUUID],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for display in displays {
            _ = fixture.assertConvergence(harness, on: display, file: file, line: line)
        }
    }
}
