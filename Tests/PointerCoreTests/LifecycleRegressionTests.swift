import XCTest
@testable import PointerCore

final class LifecycleRegressionTests: XCTestCase {
    func testStandbyClearsSelectionButRetainsMarksAndUndoAvailability() {
        let display = DisplayUUID(rawValue: "display-a")
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let mark = fixtureRectangle()
        session.apply(.append(mark, to: display))
        _ = session.beginGesture(
            tool: .select,
            at: NormalizedPoint(x: 0.3, y: 0.3),
            on: display
        )
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
        _ = session.beginGesture(
            tool: .arrow,
            at: .init(x: 0.2, y: 0.2),
            on: display
        )
        _ = session.advanceGesture(to: .init(x: 0.8, y: 0.8))
        _ = session.cancelGesture()
        let staleCommit = session.commitGesture()
        XCTAssertFalse(staleCommit.didMutate)
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)
        XCTAssertFalse(session.canUndo(on: display))
    }

    private func fixtureRectangle() -> Mark {
        Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            geometry: .rectangle(
                NormalizedRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)
            ),
            style: .default
        )
    }
}
