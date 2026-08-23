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

    func testAnnotationModeCommandCancelsDraftBeforeStaleCommit() {
        let display = DisplayUUID(rawValue: "display-a")
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        _ = session.beginGesture(
            tool: .arrow,
            at: .init(x: 0.2, y: 0.2),
            on: display
        )
        _ = session.advanceGesture(to: .init(x: 0.8, y: 0.8))

        session.apply(.setMode(.annotation))

        let staleCommit = session.commitGesture()
        XCTAssertEqual(session.mode, .annotation)
        XCTAssertFalse(staleCommit.didMutate)
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)
        XCTAssertFalse(session.canUndo(on: display))
    }

    func testClearAllCancelsDraftAndUndoClearAllRestoresExactPreClearState() {
        let firstDisplay = DisplayUUID(rawValue: "display-a")
        let secondDisplay = DisplayUUID(rawValue: "display-b")
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let first = fixtureRectangle()
        let second = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            geometry: .ellipse(
                NormalizedRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
            ),
            style: .default
        )
        session.apply(.append(first, to: firstDisplay))
        session.apply(.append(second, to: secondDisplay))
        let firstBeforeClear = session.canvas(for: firstDisplay)
        let secondBeforeClear = session.canvas(for: secondDisplay)

        _ = session.beginGesture(
            tool: .arrow,
            at: .init(x: 0.2, y: 0.2),
            on: firstDisplay
        )
        _ = session.advanceGesture(to: .init(x: 0.8, y: 0.8))

        session.apply(.clearAll)

        XCTAssertTrue(session.previewCanvas(for: firstDisplay).marks.isEmpty)
        XCTAssertTrue(session.canvas(for: firstDisplay).marks.isEmpty)
        XCTAssertTrue(session.canvas(for: secondDisplay).marks.isEmpty)

        let staleCommit = session.commitGesture()
        XCTAssertFalse(staleCommit.didMutate)
        XCTAssertTrue(session.canvas(for: firstDisplay).marks.isEmpty)
        XCTAssertTrue(session.canvas(for: secondDisplay).marks.isEmpty)
        XCTAssertTrue(session.canUndoClearAll)

        session.apply(.undoClearAll)

        XCTAssertEqual(session.canvas(for: firstDisplay), firstBeforeClear)
        XCTAssertEqual(session.canvas(for: secondDisplay), secondBeforeClear)
    }

    func testCanUndoIsPerDisplayAndTurnsFalseAfterLastSnapshotIsConsumed() {
        let firstDisplay = DisplayUUID(rawValue: "display-a")
        let secondDisplay = DisplayUUID(rawValue: "display-b")
        var session = PointerSession()
        let first = fixtureRectangle()
        let second = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            geometry: .arrow(
                start: .init(x: 0.1, y: 0.1),
                end: .init(x: 0.9, y: 0.9)
            ),
            style: .default
        )

        session.apply(.append(first, to: firstDisplay))
        session.apply(.append(second, to: secondDisplay))
        XCTAssertTrue(session.canUndo(on: firstDisplay))
        XCTAssertTrue(session.canUndo(on: secondDisplay))

        session.apply(.undo(on: firstDisplay))
        XCTAssertFalse(session.canUndo(on: firstDisplay))
        XCTAssertTrue(session.canUndo(on: secondDisplay))

        session.apply(.undo(on: secondDisplay))
        XCTAssertFalse(session.canUndo(on: firstDisplay))
        XCTAssertFalse(session.canUndo(on: secondDisplay))
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
