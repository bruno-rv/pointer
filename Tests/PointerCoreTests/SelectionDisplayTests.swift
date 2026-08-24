import XCTest
@testable import PointerCore

final class SelectionDisplayTests: XCTestCase {
    private let displayA = DisplayUUID(rawValue: "display-a")
    private let displayB = DisplayUUID(rawValue: "display-b")

    func testSelectedDisplayTracksSelectionWhileAnotherDisplayExists() {
        let session = selectedSession()

        XCTAssertEqual(session.selectedDisplay, displayA)
        XCTAssertEqual(session.selection, session.canvas(for: displayA).marks[0].id)
    }

    func testDisplayConnectionChangesDoNotAlterSelectedDisplay() {
        var session = selectedSession()

        session.ensureCanvas(for: displayB)
        session.disconnect(displayB)
        session.ensureCanvas(for: displayB)
        session.disconnect(displayA)

        XCTAssertEqual(session.selectedDisplay, displayA)
    }

    func testEmptyClickClearsSelectedDisplay() {
        var session = selectedSession()

        _ = session.beginGesture(
            tool: .select,
            at: NormalizedPoint(x: 0.05, y: 0.05),
            on: displayB
        )
        _ = session.commitGesture()

        XCTAssertNil(session.selectedDisplay)
    }

    func testDeleteClearsSelectedDisplay() {
        var session = selectedSession()

        session.apply(.deleteSelected)

        XCTAssertNil(session.selectedDisplay)
    }

    func testClearClearsSelectedDisplay() {
        var session = selectedSession()

        session.apply(.clear(displayA))

        XCTAssertNil(session.selectedDisplay)
    }

    func testStandbyClearsSelectedDisplay() {
        var session = selectedSession()

        session.apply(.setMode(.standby))

        XCTAssertNil(session.selectedDisplay)
    }

    func testCancelRestoresPriorSelectedDisplay() {
        var session = selectedSession()

        _ = session.beginGesture(
            tool: .rectangle,
            at: NormalizedPoint(x: 0.5, y: 0.5),
            on: displayB
        )
        _ = session.advanceGesture(to: NormalizedPoint(x: 0.8, y: 0.8))
        _ = session.cancelGesture()

        XCTAssertEqual(session.selectedDisplay, displayA)
    }

    func testNonmeaningfulCommitRestoresPriorSelectedDisplay() {
        var session = selectedSession()
        let start = NormalizedPoint(x: 0.5, y: 0.5)

        _ = session.beginGesture(tool: .arrow, at: start, on: displayB)
        XCTAssertFalse(session.commitGesture().didMutate)

        XCTAssertEqual(session.selectedDisplay, displayA)
    }

    private func selectedSession() -> PointerSession {
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        session.ensureCanvas(for: displayB)
        let mark = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            geometry: .rectangle(
                NormalizedRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)
            ),
            style: .default
        )
        session.apply(.append(mark, to: displayA))
        _ = session.beginGesture(
            tool: .select,
            at: NormalizedPoint(x: 0.3, y: 0.3),
            on: displayA
        )
        XCTAssertFalse(session.commitGesture().didMutate)
        return session
    }
}
