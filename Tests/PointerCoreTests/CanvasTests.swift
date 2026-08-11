import XCTest
@testable import PointerCore

final class CanvasTests: XCTestCase {
    func testAppendingMarksPreservesTheirOrder() {
        let display = DisplayUUID(rawValue: "external-uuid")
        let first = fixtureArrow(1)
        let second = fixtureArrow(2)
        let third = fixtureArrow(3)
        var session = PointerSession()

        session.apply(.append(first, to: display))
        session.apply(.append(second, to: display))
        session.apply(.append(third, to: display))

        XCTAssertEqual(session.canvas(for: display).marks, [first, second, third])
    }

    func testClearAndUndoRestoreTheClearedCanvas() {
        let display = DisplayUUID(rawValue: "external-uuid")
        let first = fixtureArrow(1)
        let second = fixtureArrow(2)
        var session = PointerSession()

        session.apply(.append(first, to: display))
        session.apply(.append(second, to: display))
        session.apply(.clear(display))

        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)

        session.apply(.undo(on: display))

        XCTAssertEqual(session.canvas(for: display).marks, [first, second])
    }

    func testUndoIsBoundedPerCanvasAndIsolatedAcrossDisplays() {
        let builtIn = DisplayUUID(rawValue: "built-in-uuid")
        let external = DisplayUUID(rawValue: "external-uuid")
        let retained = fixtureArrow(0)
        let externalMark = fixtureArrow(200)
        var session = PointerSession()

        for index in 0 ... 100 {
            session.apply(.append(index == 0 ? retained : fixtureArrow(index), to: builtIn))
        }
        session.apply(.append(externalMark, to: external))

        for _ in 0 ..< UndoHistory.capacity {
            session.apply(.undo(on: builtIn))
        }

        XCTAssertEqual(session.canvas(for: builtIn).marks, [retained])
        XCTAssertEqual(session.canvas(for: external).marks, [externalMark])

        session.apply(.undo(on: external))

        XCTAssertTrue(session.canvas(for: external).marks.isEmpty)
        XCTAssertEqual(session.canvas(for: builtIn).marks, [retained])
    }

    func testCanvasLookupReturnsAValueSnapshot() {
        let display = DisplayUUID(rawValue: "external-uuid")
        let first = fixtureArrow(1)
        let second = fixtureArrow(2)
        var session = PointerSession()

        session.apply(.append(first, to: display))
        let snapshot = session.canvas(for: display)

        session.apply(.append(second, to: display))

        XCTAssertEqual(snapshot.marks, [first])
        XCTAssertEqual(session.canvas(for: display).marks, [first, second])
    }

    func testAppendingSpotlightReplacesExistingSpotlightInOneUndoOperation() {
        let display = DisplayUUID(rawValue: "external-uuid")
        let firstSpotlight = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            geometry: .spotlight(
                center: NormalizedPoint(x: 0.25, y: 0.25),
                radius: 0.2,
                dimness: 0.2
            ),
            style: .default
        )
        let secondSpotlight = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            geometry: .spotlight(
                center: NormalizedPoint(x: 0.75, y: 0.75),
                radius: 0.3,
                dimness: 1.2
            ),
            style: .default
        )
        var session = PointerSession()

        session.apply(.append(firstSpotlight, to: display))
        session.apply(.append(secondSpotlight, to: display))

        XCTAssertEqual(session.canvas(for: display).marks.map(\.id), [secondSpotlight.id])
        XCTAssertEqual(
            session.canvas(for: display).marks.first?.geometry,
            .spotlight(
                center: NormalizedPoint(x: 0.75, y: 0.75),
                radius: 0.3,
                dimness: 1
            )
        )

        session.apply(.undo(on: display))

        XCTAssertEqual(session.canvas(for: display).marks.map(\.id), [firstSpotlight.id])
    }

    func testUndoHistoryRetainsOnlyTheMostRecentOneHundredSnapshots() {
        let display = DisplayUUID(rawValue: "built-in-uuid")
        var session = PointerSession()

        for index in 0 ... 100 {
            session.apply(.append(fixtureArrow(index), to: display))
        }

        for _ in 0 ..< 100 {
            session.apply(.undo(on: display))
        }

        XCTAssertEqual(session.canvas(for: display).marks.map(\.id), [fixtureArrow(0).id])
    }

    private func fixtureArrow(_ index: Int) -> Mark {
        Mark(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 10))!,
            geometry: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.1),
                end: NormalizedPoint(x: 0.9, y: 0.9)
            ),
            style: .default
        )
    }
}
