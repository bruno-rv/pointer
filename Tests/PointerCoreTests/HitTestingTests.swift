import XCTest
@testable import PointerCore

final class HitTestingTests: XCTestCase {
    /// Reverse-order hit testing selects the topmost mark.
    func testHitTestSelectsTopmostMark() {
        let bottom = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000060")!,
            geometry: .rectangle(NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)),
            style: .default
        )
        let top = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000061")!,
            geometry: .ellipse(NormalizedRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)),
            style: .default
        )

        let target = HitTesting.hitTest(
            at: NormalizedPoint(x: 0.3, y: 0.3),
            in: [bottom, top],
            selectedID: nil
        )

        XCTAssertEqual(target, .mark(top.id))
    }

    /// Selected marks expose resize handles before body hits.
    func testHitTestPrefersResizeHandleOnSelectedMark() {
        let mark = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000062")!,
            geometry: .rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)),
            style: .default
        )

        let target = HitTesting.hitTest(
            at: NormalizedPoint(x: 0.2, y: 0.2),
            in: [mark],
            selectedID: mark.id,
            handleTolerance: 0.03
        )

        XCTAssertEqual(target, .handle(.bottomLeft))
    }

    /// Segment intersection removes marks the eraser path crosses between samples.
    func testSegmentIntersectionHitsMarkBetweenSparseSamples() {
        let mark = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000063")!,
            geometry: .arrow(
                start: NormalizedPoint(x: 0.5, y: 0.2),
                end: NormalizedPoint(x: 0.5, y: 0.8)
            ),
            style: .default
        )

        let start = NormalizedPoint(x: 0.1, y: 0.5)
        let end = NormalizedPoint(x: 0.9, y: 0.5)

        XCTAssertFalse(HitTesting.intersects(mark: mark, at: start, tolerance: 0.02))
        XCTAssertFalse(HitTesting.intersects(mark: mark, at: end, tolerance: 0.02))
        XCTAssertTrue(
            HitTesting.intersects(
                mark: mark,
                segmentFrom: start,
                to: end,
                tolerance: 0.02
            )
        )
    }

    func testEllipseSegmentThroughBoundingCornerDoesNotCountAsHit() {
        let mark = Mark(
            geometry: .ellipse(NormalizedRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)),
            style: .default
        )

        XCTAssertFalse(
            HitTesting.intersects(
                mark: mark,
                segmentFrom: NormalizedPoint(x: 0.1, y: 0.1),
                to: NormalizedPoint(x: 0.3, y: 0.3),
                tolerance: 0.01
            )
        )
    }

    func testEllipseSegmentThroughInteriorCountsAsHit() {
        let mark = Mark(
            geometry: .ellipse(NormalizedRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)),
            style: .default
        )

        XCTAssertTrue(
            HitTesting.intersects(
                mark: mark,
                segmentFrom: NormalizedPoint(x: 0.1, y: 0.5),
                to: NormalizedPoint(x: 0.9, y: 0.5),
                tolerance: 0.01
            )
        )
    }
}
