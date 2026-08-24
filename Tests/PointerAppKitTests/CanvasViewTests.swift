import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class CanvasViewTests: XCTestCase {
    func testBeginBoundarySurvivesRedrawCallbackClearingHandlers() {
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
        view.onRedrawRequested = {
            view.onSessionUpdate = nil
            view.onBoundaryEvent = nil
        }

        view.beginGesture(at: NSPoint(x: 100, y: 100))

        XCTAssertEqual(boundaries, [.began])
    }

    func testCommitBoundarySurvivesCallbacksClearingHandlers() {
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
        boundaries.removeAll()
        view.onRedrawRequested = {
            view.onSessionUpdate = nil
            view.onBoundaryEvent = nil
            view.onRedrawRequested = nil
        }
        view.onSessionUpdate = { _ in
            view.onBoundaryEvent = nil
        }

        view.endGesture()

        XCTAssertEqual(boundaries, [.committed])
    }

    func testInitializerAdoptsActiveGestureOwnershipByDisplay() {
        let displayA = DisplayUUID(rawValue: "display-a")
        let displayB = DisplayUUID(rawValue: "display-b")
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        _ = session.beginGesture(
            tool: .arrow,
            at: .init(x: 0.2, y: 0.2),
            on: displayA
        )
        _ = session.advanceGesture(to: .init(x: 0.8, y: 0.8))

        let sourceView = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            display: displayA,
            session: session,
            tool: .arrow
        )
        var sourceBoundaries: [GestureBoundaryEvent] = []
        sourceView.onBoundaryEvent = { sourceBoundaries.append($0) }

        XCTAssertTrue(sourceView.hasActiveGesture)
        sourceView.endGesture()
        XCTAssertEqual(sourceBoundaries, [.committed])

        let otherView = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            display: displayB,
            session: session,
            tool: .arrow
        )
        var otherBoundaries: [GestureBoundaryEvent] = []
        otherView.onBoundaryEvent = { otherBoundaries.append($0) }

        XCTAssertFalse(otherView.hasActiveGesture)
        otherView.endGesture()
        XCTAssertTrue(otherBoundaries.isEmpty)
    }

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
        var redrawsA = 0
        var redrawsB = 0
        viewA.onBoundaryEvent = { boundariesA.append($0) }
        viewB.onBoundaryEvent = { boundariesB.append($0) }
        viewA.onRedrawRequested = { redrawsA += 1 }
        viewB.onRedrawRequested = { redrawsB += 1 }
        let updateViews: (PointerSession) -> Void = { updatedSession in
            viewA.update(session: updatedSession)
            viewB.update(session: updatedSession)
        }
        viewA.onSessionUpdate = updateViews
        viewB.onSessionUpdate = updateViews

        viewA.beginGesture(at: NSPoint(x: 100, y: 100))
        viewB.beginGesture(at: NSPoint(x: 100, y: 100))
        let sessionABeforeStaleContinue = viewA.session
        let sessionBBeforeStaleContinue = viewB.session
        redrawsA = 0
        redrawsB = 0

        viewA.continueGesture(to: NSPoint(x: 400, y: 400))

        XCTAssertEqual(viewA.session, sessionABeforeStaleContinue)
        XCTAssertEqual(viewB.session, sessionBBeforeStaleContinue)
        XCTAssertEqual(redrawsA, 0)
        XCTAssertEqual(redrawsB, 0)
        XCTAssertEqual(boundariesA, [.began])
        XCTAssertEqual(boundariesB, [.began])

        viewB.continueGesture(to: NSPoint(x: 300, y: 300))
        XCTAssertEqual(redrawsB, 1)

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
