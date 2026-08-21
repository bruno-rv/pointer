import XCTest
@testable import PointerCore

final class ResizeGeometryTests: XCTestCase {
    /// Freehand corner resize scales uniformly from the opposite anchor.
    func testFreehandCornerResizeUsesUniformScaleFromOppositeAnchor() {
        let original: MarkGeometry = .freehand([
            NormalizedPoint(x: 0.2, y: 0.2),
            NormalizedPoint(x: 0.4, y: 0.2),
            NormalizedPoint(x: 0.4, y: 0.3),
            NormalizedPoint(x: 0.2, y: 0.3),
        ])

        let resized = ResizeGeometry.resize(
            original,
            using: .topRight,
            to: NormalizedPoint(x: 0.6, y: 0.4),
            original: original
        )

        guard case let .freehand(points) = resized else {
            return XCTFail("Expected freehand geometry")
        }

        // Opposite anchor is bottom-left (0.2, 0.2). Uniform scale 2 from a
        // 0.2×0.1 bounds yields a 0.4×0.2 result mapped from that anchor.
        XCTAssertEqual(points[0].x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(points[0].y, 0.2, accuracy: 1e-9)
        XCTAssertEqual(points[1].x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(points[1].y, 0.2, accuracy: 1e-9)
        XCTAssertEqual(points[2].x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(points[2].y, 0.4, accuracy: 1e-9)
        XCTAssertEqual(points[3].x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(points[3].y, 0.4, accuracy: 1e-9)
    }

    /// Rectangle exposes eight bounds handles; arrow exposes endpoints.
    func testHandleSetsMatchMarkKind() {
        XCTAssertEqual(
            ResizeGeometry.handles(for: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.1),
                end: NormalizedPoint(x: 0.9, y: 0.9)
            )),
            [.arrowStart, .arrowEnd]
        )

        let rect = MarkGeometry.rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4))
        XCTAssertEqual(
            ResizeGeometry.handles(for: rect),
            [
                .topLeft, .topCenter, .topRight,
                .middleLeft, .middleRight,
                .bottomLeft, .bottomCenter, .bottomRight,
            ]
        )

        let freehand = MarkGeometry.freehand([
            NormalizedPoint(x: 0.1, y: 0.1),
            NormalizedPoint(x: 0.2, y: 0.2),
        ])
        XCTAssertEqual(
            ResizeGeometry.handles(for: freehand),
            [.topLeft, .topRight, .bottomLeft, .bottomRight]
        )

        let spotlight = MarkGeometry.spotlight(
            center: NormalizedPoint(x: 0.5, y: 0.5),
            radius: 0.1,
            dimness: 0.4
        )
        XCTAssertEqual(
            ResizeGeometry.handles(for: spotlight),
            [.spotlightCenter, .spotlightRadius]
        )
    }

    /// Session select+resize uses the same uniform freehand corner mapping.
    func testSessionFreehandCornerResizeUsesUniformScaleFromOppositeAnchor() {
        let display = DisplayUUID(rawValue: "resize-display")
        var session = PointerSession()
        session.apply(.setMode(.annotation))

        let mark = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000070")!,
            geometry: .freehand([
                NormalizedPoint(x: 0.2, y: 0.2),
                NormalizedPoint(x: 0.4, y: 0.2),
                NormalizedPoint(x: 0.4, y: 0.3),
                NormalizedPoint(x: 0.2, y: 0.3),
            ]),
            style: .default
        )
        session.apply(.append(mark, to: display))

        // Hit the stroke itself (freehand is not a filled body).
        _ = session.beginGesture(tool: .select, at: NormalizedPoint(x: 0.3, y: 0.2), on: display)
        _ = session.commitGesture()
        XCTAssertEqual(session.selection, mark.id)

        _ = session.beginGesture(tool: .select, at: NormalizedPoint(x: 0.4, y: 0.3), on: display)
        _ = session.advanceGesture(to: NormalizedPoint(x: 0.6, y: 0.4))
        XCTAssertTrue(session.commitGesture().didMutate)

        guard case let .freehand(points) = session.canvas(for: display).marks[0].geometry else {
            return XCTFail("Expected resized freehand")
        }
        XCTAssertEqual(points[0].x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(points[0].y, 0.2, accuracy: 1e-9)
        XCTAssertEqual(points[1].x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(points[1].y, 0.2, accuracy: 1e-9)
        XCTAssertEqual(points[2].x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(points[2].y, 0.4, accuracy: 1e-9)
        XCTAssertEqual(points[3].x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(points[3].y, 0.4, accuracy: 1e-9)
        XCTAssertEqual(session.canvas(for: display).marks[0].id, mark.id)
    }
}
