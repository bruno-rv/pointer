import XCTest
@testable import PointerCore

final class PointerSessionTests: XCTestCase {
    func testSessionStartsInStandbyWithTheRequiredArrowStyle() {
        let session = PointerSession()

        XCTAssertEqual(session.mode, .standby)
        XCTAssertEqual(session.toolState.tool, .arrow)
        XCTAssertEqual(session.toolState.style, MarkStyle(color: .red, strokeWidth: 4, opacity: 1))
        XCTAssertEqual(session.toolState.emoji, "👉")
        XCTAssertEqual(session.toolState.spotlightRadius, 0.15)
        XCTAssertEqual(session.toolState.spotlightDimness, 0.5)
    }

    func testModeCommandsTransitionBetweenAnnotationAndStandby() {
        var session = PointerSession()

        session.apply(.setMode(.annotation))
        XCTAssertEqual(session.mode, .annotation)

        session.apply(.setMode(.standby))
        XCTAssertEqual(session.mode, .standby)
    }

    func testReconnectUsesCanvasOwnedByStableDisplayUUID() {
        let id = DisplayUUID(rawValue: "external-uuid")
        let fixtureArrow = makeArrow(index: 1)
        var session = PointerSession()

        session.ensureCanvas(for: id)
        session.apply(.append(fixtureArrow, to: id))
        session.disconnect(id)
        session.ensureCanvas(for: id)

        XCTAssertEqual(session.canvas(for: id).marks.map(\.id), [fixtureArrow.id])
    }

    func testClearAllUndoRestoresEveryCanvasAndTheirPriorUndoStacks() {
        let builtIn = DisplayUUID(rawValue: "built-in-uuid")
        let external = DisplayUUID(rawValue: "external-uuid")
        let first = makeArrow(index: 1)
        let second = makeArrow(index: 2)
        let third = makeArrow(index: 3)
        let fourth = makeArrow(index: 4)
        let fifth = makeArrow(index: 5)
        let sixth = makeArrow(index: 6)
        var session = PointerSession()

        session.apply(.append(first, to: builtIn))
        session.apply(.append(second, to: builtIn))
        session.apply(.append(third, to: builtIn))
        session.apply(.undo(on: builtIn))

        session.apply(.append(fourth, to: external))
        session.apply(.append(fifth, to: external))
        session.apply(.append(sixth, to: external))
        session.apply(.undo(on: external))
        session.apply(.clearAll)

        XCTAssertTrue(session.canvas(for: builtIn).marks.isEmpty)
        XCTAssertTrue(session.canvas(for: external).marks.isEmpty)

        session.apply(.undoClearAll)

        XCTAssertEqual(session.canvas(for: builtIn).marks.map(\.id), [first.id, second.id])
        XCTAssertEqual(session.canvas(for: external).marks.map(\.id), [fourth.id, fifth.id])

        session.apply(.undo(on: builtIn))
        session.apply(.undo(on: external))

        XCTAssertEqual(session.canvas(for: builtIn).marks.map(\.id), [first.id])
        XCTAssertEqual(session.canvas(for: external).marks.map(\.id), [fourth.id])

        session.apply(.undo(on: builtIn))
        session.apply(.undo(on: external))

        XCTAssertTrue(session.canvas(for: builtIn).marks.isEmpty)
        XCTAssertTrue(session.canvas(for: external).marks.isEmpty)
    }

    func testCommandsAreTheContentMutationRouteAndUpdateModeAndToolState() {
        var session = PointerSession()
        let style = MarkStyle(
            color: RGBAColor(red: 1.5, green: -1, blue: 0.5, alpha: 2),
            strokeWidth: 2,
            opacity: -0.1
        )

        session.apply(.setMode(.annotation))
        session.apply(.setTool(.ellipse))
        session.apply(.setStyle(style))
        session.apply(.setEmoji("⭐️"))
        session.apply(.setSpotlight(radius: 0.25, dimness: 1.5))

        XCTAssertEqual(session.mode, .annotation)
        XCTAssertEqual(session.toolState.tool, .ellipse)
        XCTAssertEqual(session.toolState.style.opacity, 0)
        XCTAssertEqual(session.toolState.style.color, RGBAColor(red: 1, green: 0, blue: 0.5, alpha: 1))
        XCTAssertEqual(session.toolState.emoji, "⭐️")
        XCTAssertEqual(session.toolState.spotlightRadius, 0.25)
        XCTAssertEqual(session.toolState.spotlightDimness, 1)
    }

    private func makeArrow(index: Int) -> Mark {
        Mark(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
            geometry: .arrow(
                start: NormalizedPoint(x: 0.2, y: 0.3),
                end: NormalizedPoint(x: 0.8, y: 0.7)
            ),
            style: .default
        )
    }
}
