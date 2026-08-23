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

    func testEveryResizeHandlePreservesNormalizedGeometryAndUndo() {
        struct ResizeFixture {
            let name: String
            let geometry: MarkGeometry
            let handle: ResizeHandle
            let selectionPoint: NormalizedPoint
            let handlePoint: NormalizedPoint
            let target: NormalizedPoint
            let expected: MarkGeometry
        }

        let rectangle = NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let fixtures = [
            ResizeFixture(
                name: "arrow start",
                geometry: .arrow(
                    start: NormalizedPoint(x: 0.2, y: 0.2),
                    end: NormalizedPoint(x: 0.8, y: 0.8)
                ),
                handle: .arrowStart,
                selectionPoint: NormalizedPoint(x: 0.5, y: 0.5),
                handlePoint: NormalizedPoint(x: 0.2, y: 0.2),
                target: NormalizedPoint(x: 0.1, y: 0.3),
                expected: .arrow(
                    start: NormalizedPoint(x: 0.1, y: 0.3),
                    end: NormalizedPoint(x: 0.8, y: 0.8)
                )
            ),
            ResizeFixture(
                name: "arrow end",
                geometry: .arrow(
                    start: NormalizedPoint(x: 0.2, y: 0.2),
                    end: NormalizedPoint(x: 0.8, y: 0.8)
                ),
                handle: .arrowEnd,
                selectionPoint: NormalizedPoint(x: 0.5, y: 0.5),
                handlePoint: NormalizedPoint(x: 0.8, y: 0.8),
                target: NormalizedPoint(x: 0.7, y: 0.4),
                expected: .arrow(
                    start: NormalizedPoint(x: 0.2, y: 0.2),
                    end: NormalizedPoint(x: 0.7, y: 0.4)
                )
            ),
            ResizeFixture(
                name: "rectangle top left",
                geometry: .rectangle(rectangle),
                handle: .topLeft,
                selectionPoint: NormalizedPoint(x: 0.4, y: 0.4),
                handlePoint: NormalizedPoint(x: 0.2, y: 0.6),
                target: NormalizedPoint(x: 0.1, y: 0.8),
                expected: .rectangle(NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6))
            ),
            ResizeFixture(
                name: "rectangle top center",
                geometry: .rectangle(rectangle),
                handle: .topCenter,
                selectionPoint: NormalizedPoint(x: 0.4, y: 0.4),
                handlePoint: NormalizedPoint(x: 0.4, y: 0.6),
                target: NormalizedPoint(x: 0.4, y: 0.8),
                expected: .rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.6))
            ),
            ResizeFixture(
                name: "rectangle top right",
                geometry: .rectangle(rectangle),
                handle: .topRight,
                selectionPoint: NormalizedPoint(x: 0.4, y: 0.4),
                handlePoint: NormalizedPoint(x: 0.6, y: 0.6),
                target: NormalizedPoint(x: 0.8, y: 0.8),
                expected: .rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
            ),
            ResizeFixture(
                name: "rectangle middle left",
                geometry: .rectangle(rectangle),
                handle: .middleLeft,
                selectionPoint: NormalizedPoint(x: 0.4, y: 0.4),
                handlePoint: NormalizedPoint(x: 0.2, y: 0.4),
                target: NormalizedPoint(x: 0.1, y: 0.4),
                expected: .rectangle(NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4))
            ),
            ResizeFixture(
                name: "rectangle middle right",
                geometry: .rectangle(rectangle),
                handle: .middleRight,
                selectionPoint: NormalizedPoint(x: 0.4, y: 0.4),
                handlePoint: NormalizedPoint(x: 0.6, y: 0.4),
                target: NormalizedPoint(x: 0.8, y: 0.4),
                expected: .rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.4))
            ),
            ResizeFixture(
                name: "rectangle bottom left",
                geometry: .rectangle(rectangle),
                handle: .bottomLeft,
                selectionPoint: NormalizedPoint(x: 0.4, y: 0.4),
                handlePoint: NormalizedPoint(x: 0.2, y: 0.2),
                target: NormalizedPoint(x: 0.1, y: 0.1),
                expected: .rectangle(NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
            ),
            ResizeFixture(
                name: "rectangle bottom center",
                geometry: .rectangle(rectangle),
                handle: .bottomCenter,
                selectionPoint: NormalizedPoint(x: 0.4, y: 0.4),
                handlePoint: NormalizedPoint(x: 0.4, y: 0.2),
                target: NormalizedPoint(x: 0.4, y: 0.1),
                expected: .rectangle(NormalizedRect(x: 0.2, y: 0.1, width: 0.4, height: 0.5))
            ),
            ResizeFixture(
                name: "rectangle bottom right",
                geometry: .rectangle(rectangle),
                handle: .bottomRight,
                selectionPoint: NormalizedPoint(x: 0.4, y: 0.4),
                handlePoint: NormalizedPoint(x: 0.6, y: 0.2),
                target: NormalizedPoint(x: 0.8, y: 0.1),
                expected: .rectangle(NormalizedRect(x: 0.2, y: 0.1, width: 0.6, height: 0.5))
            ),
            ResizeFixture(
                name: "ellipse top center",
                geometry: .ellipse(rectangle),
                handle: .topCenter,
                selectionPoint: NormalizedPoint(x: 0.4, y: 0.4),
                handlePoint: NormalizedPoint(x: 0.4, y: 0.6),
                target: NormalizedPoint(x: 0.4, y: 0.8),
                expected: .ellipse(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.6))
            ),
            ResizeFixture(
                name: "freehand top right",
                geometry: .freehand([
                    NormalizedPoint(x: 0.2, y: 0.2),
                    NormalizedPoint(x: 0.4, y: 0.2),
                    NormalizedPoint(x: 0.4, y: 0.3),
                    NormalizedPoint(x: 0.2, y: 0.3),
                ]),
                handle: .topRight,
                selectionPoint: NormalizedPoint(x: 0.3, y: 0.2),
                handlePoint: NormalizedPoint(x: 0.4, y: 0.3),
                target: NormalizedPoint(x: 0.6, y: 0.4),
                expected: .freehand([
                    NormalizedPoint(x: 0.2, y: 0.2),
                    NormalizedPoint(x: 0.6, y: 0.2),
                    NormalizedPoint(x: 0.6, y: 0.4),
                    NormalizedPoint(x: 0.2, y: 0.4),
                ])
            ),
            ResizeFixture(
                name: "emoji top right",
                geometry: .emoji(
                    text: "⭐️",
                    rect: NormalizedRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
                ),
                handle: .topRight,
                selectionPoint: NormalizedPoint(x: 0.4, y: 0.4),
                handlePoint: NormalizedPoint(x: 0.5, y: 0.5),
                target: NormalizedPoint(x: 0.7, y: 0.6),
                expected: .emoji(
                    text: "⭐️",
                    rect: NormalizedRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
                )
            ),
            ResizeFixture(
                name: "spotlight center",
                geometry: .spotlight(
                    center: NormalizedPoint(x: 0.5, y: 0.5),
                    radius: 0.1,
                    dimness: 0.4
                ),
                handle: .spotlightCenter,
                selectionPoint: NormalizedPoint(x: 0.5, y: 0.5),
                handlePoint: NormalizedPoint(x: 0.5, y: 0.5),
                target: NormalizedPoint(x: 0.7, y: 0.8),
                expected: .spotlight(
                    center: NormalizedPoint(x: 0.7, y: 0.8),
                    radius: 0.1,
                    dimness: 0.4
                )
            ),
            ResizeFixture(
                name: "spotlight radius",
                geometry: .spotlight(
                    center: NormalizedPoint(x: 0.5, y: 0.5),
                    radius: 0.1,
                    dimness: 0.4
                ),
                handle: .spotlightRadius,
                selectionPoint: NormalizedPoint(x: 0.5, y: 0.5),
                handlePoint: NormalizedPoint(x: 0.6, y: 0.5),
                target: NormalizedPoint(x: 0.8, y: 0.5),
                expected: .spotlight(
                    center: NormalizedPoint(x: 0.5, y: 0.5),
                    radius: 0.3,
                    dimness: 0.4
                )
            ),
        ]

        let display = DisplayUUID(rawValue: "resize-contract-display")
        func assertPoint(_ actual: NormalizedPoint, _ expected: NormalizedPoint, _ name: String) {
            XCTAssertEqual(actual.x, expected.x, accuracy: 1e-9, name)
            XCTAssertEqual(actual.y, expected.y, accuracy: 1e-9, name)
        }
        func assertRect(_ actual: NormalizedRect, _ expected: NormalizedRect, _ name: String) {
            XCTAssertEqual(actual.x, expected.x, accuracy: 1e-9, name)
            XCTAssertEqual(actual.y, expected.y, accuracy: 1e-9, name)
            XCTAssertEqual(actual.width, expected.width, accuracy: 1e-9, name)
            XCTAssertEqual(actual.height, expected.height, accuracy: 1e-9, name)
        }
        func assertGeometry(_ actual: MarkGeometry, _ expected: MarkGeometry, _ name: String) {
            switch (actual, expected) {
            case let (.arrow(actualStart, actualEnd), .arrow(expectedStart, expectedEnd)):
                assertPoint(actualStart, expectedStart, name)
                assertPoint(actualEnd, expectedEnd, name)
            case let (.rectangle(actualRect), .rectangle(expectedRect)),
                 let (.ellipse(actualRect), .ellipse(expectedRect)):
                assertRect(actualRect, expectedRect, name)
            case let (.freehand(actualPoints), .freehand(expectedPoints)):
                XCTAssertEqual(actualPoints.count, expectedPoints.count, name)
                for (actualPoint, expectedPoint) in zip(actualPoints, expectedPoints) {
                    assertPoint(actualPoint, expectedPoint, name)
                }
            case let (.emoji(actualText, actualRect), .emoji(expectedText, expectedRect)):
                XCTAssertEqual(actualText, expectedText, name)
                assertRect(actualRect, expectedRect, name)
            case let (.spotlight(actualCenter, actualRadius, actualDimness),
                      .spotlight(expectedCenter, expectedRadius, expectedDimness)):
                assertPoint(actualCenter, expectedCenter, name)
                XCTAssertEqual(actualRadius, expectedRadius, accuracy: 1e-9, name)
                XCTAssertEqual(actualDimness, expectedDimness, accuracy: 1e-9, name)
            default:
                XCTFail("Geometry kind changed for \(name)")
            }
        }

        for fixture in fixtures {
            var session = PointerSession()
            session.apply(.setMode(.annotation))
            let mark = Mark(
                id: UUID(),
                geometry: fixture.geometry,
                style: .default
            )
            session.apply(.append(mark, to: display))

            _ = session.beginGesture(tool: .select, at: fixture.selectionPoint, on: display)
            XCTAssertFalse(session.commitGesture().didMutate, fixture.name)
            XCTAssertEqual(session.selection, mark.id, fixture.name)

            _ = session.beginGesture(tool: .select, at: fixture.handlePoint, on: display)
            _ = session.advanceGesture(to: fixture.target)
            XCTAssertTrue(session.commitGesture().didMutate, fixture.name)

            guard let resized = session.canvas(for: display).marks.first(where: { $0.id == mark.id }) else {
                return XCTFail("Missing resized \(fixture.name) mark")
            }
            assertGeometry(resized.geometry, fixture.expected, fixture.name)

            session.apply(.undo(on: display))
            XCTAssertEqual(session.canvas(for: display).marks, [mark], fixture.name)
        }
    }
}
