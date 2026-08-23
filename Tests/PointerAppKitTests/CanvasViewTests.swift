import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class CanvasViewTests: XCTestCase {
    func testCursorPlanCoversEveryToolAndStandby() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let view = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            display: DisplayUUID(rawValue: "display-a"),
            session: session
        )

        for (tool, expected) in [
            (PointerTool.select, CanvasView.CursorPlan.select),
            (.arrow, .draw),
            (.rectangle, .draw),
            (.ellipse, .draw),
            (.pen, .draw),
            (.eraser, .erase),
            (.emoji, .emoji),
            (.spotlight, .spotlight)
        ] {
            view.tool = tool
            XCTAssertEqual(view.cursorPlan, expected)
        }

        view.update(session: PointerSession())
        XCTAssertEqual(view.cursorPlan, .clickThrough)
    }

    func testCancelThenStaleMouseUpDoesNotCommitOrPublishSecondBoundary() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let view = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            display: DisplayUUID(rawValue: "display-a"),
            session: session,
            tool: .arrow
        )
        var boundaries: [GestureBoundaryEvent] = []
        view.onBoundaryEvent = { boundaries.append($0) }

        view.beginGesture(at: NSPoint(x: 100, y: 100))
        view.continueGesture(to: NSPoint(x: 300, y: 300))
        view.cancelGesture()
        view.endGesture()

        XCTAssertEqual(boundaries, [.began, .cancelled])
        XCTAssertTrue(view.session.canvas(for: view.display).marks.isEmpty)
    }

    func testCanvasContinuationRequestsRedrawWithoutPublishingBoundary() throws {
        let uuid = DisplayUUID(rawValue: "display-a")
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let view = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            display: uuid,
            session: session,
            tool: .pen
        )
        var boundaries: [GestureBoundaryEvent] = []
        view.onBoundaryEvent = { boundaries.append($0) }

        view.beginGesture(at: NSPoint(x: 80, y: 60))
        var redrawRequests = 0
        view.onRedrawRequested = { redrawRequests += 1 }
        view.continueGesture(to: NSPoint(x: 160, y: 120))

        XCTAssertEqual(redrawRequests, 1)
        XCTAssertEqual(boundaries, [.began])

        view.endGesture()
        XCTAssertEqual(boundaries, [.began, .committed])
    }

    func testCanvasContinuationDoesNotPublishSharedSessionState() {
        let uuid = DisplayUUID(rawValue: "display-a")
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let view = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            display: uuid,
            session: session,
            tool: .pen
        )
        var publications = 0
        view.onSessionUpdate = { _ in publications += 1 }

        view.beginGesture(at: NSPoint(x: 80, y: 60))
        XCTAssertEqual(publications, 1)

        view.continueGesture(to: NSPoint(x: 160, y: 120))
        XCTAssertEqual(publications, 1)

        view.endGesture()
        XCTAssertEqual(publications, 2)
    }
}
