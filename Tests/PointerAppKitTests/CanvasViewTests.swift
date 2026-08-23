import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class CanvasViewTests: XCTestCase {
    func testSessionEchoRetainsGestureOwnershipOnlyOnSourceView() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let displayA = DisplayUUID(rawValue: "display-a")
        let displayB = DisplayUUID(rawValue: "display-b")
        let viewA = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            display: displayA,
            session: session,
            tool: .arrow
        )
        let viewB = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            display: displayB,
            session: session,
            tool: .arrow
        )

        viewA.onSessionUpdate = { updatedSession in
            viewA.update(session: updatedSession)
            viewB.update(session: updatedSession)
        }
        viewA.beginGesture(at: NSPoint(x: 100, y: 100))

        XCTAssertTrue(viewA.hasActiveGesture)
        XCTAssertFalse(viewB.hasActiveGesture)
    }

    func testSupersededViewIgnoresStaleMouseUpAndOtherViewCommitsOnce() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let displayA = DisplayUUID(rawValue: "display-a")
        let displayB = DisplayUUID(rawValue: "display-b")
        let viewA = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            display: displayA,
            session: session,
            tool: .arrow
        )
        let viewB = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            display: displayB,
            session: session,
            tool: .arrow
        )
        var boundariesA: [GestureBoundaryEvent] = []
        var boundariesB: [GestureBoundaryEvent] = []
        viewA.onBoundaryEvent = { boundariesA.append($0) }
        viewB.onBoundaryEvent = { boundariesB.append($0) }
        let updateViews: (PointerSession) -> Void = { updatedSession in
            viewA.update(session: updatedSession)
            viewB.update(session: updatedSession)
        }
        viewA.onSessionUpdate = updateViews
        viewB.onSessionUpdate = updateViews

        viewA.beginGesture(at: NSPoint(x: 100, y: 100))
        viewB.beginGesture(at: NSPoint(x: 100, y: 100))
        viewB.continueGesture(to: NSPoint(x: 300, y: 300))

        viewA.endGesture()
        viewB.endGesture()

        XCTAssertEqual(boundariesA, [.began])
        XCTAssertEqual(boundariesB, [.began, .committed])
        XCTAssertTrue(viewA.session.canvas(for: displayA).marks.isEmpty)
        XCTAssertEqual(viewB.session.canvas(for: displayB).marks.count, 1)
    }

    func testAttachedNonVisibleWindowUsesCanvasCursorRectPath() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let view = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            display: DisplayUUID(rawValue: "display-a"),
            session: session,
            tool: .arrow
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view

        XCTAssertFalse(window.isVisible)
        XCTAssertIdentical(view.window, window)

        view.tool = .pen
        view.resetCursorRects()

        XCTAssertEqual(view.cursorPlan, .draw)
    }

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
