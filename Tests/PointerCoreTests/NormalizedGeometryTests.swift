import XCTest
@testable import PointerCore

final class NormalizedGeometryTests: XCTestCase {
    func testNormalizedRectDenormalizesAgainstNewDisplaySize() {
        let rect = NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)

        XCTAssertEqual(
            rect.denormalized(width: 1600, height: 900),
            DenormalizedRect(x: 400, y: 450, width: 800, height: 225)
        )
    }

    func testNormalizedValuesClampToTheDisplayBounds() {
        XCTAssertEqual(NormalizedPoint(x: -0.2, y: 1.2), NormalizedPoint(x: 0, y: 1))
        XCTAssertEqual(NormalizedSize(width: -0.5, height: 2), NormalizedSize(width: 0, height: 1))
        XCTAssertEqual(
            NormalizedRect(x: 0.75, y: -0.2, width: 1, height: 0.5),
            NormalizedRect(x: 0.75, y: 0, width: 0.25, height: 0.5)
        )
    }

    func testNormalizedValuesAndStyleInputsClampNonFiniteValues() {
        let point = NormalizedPoint(x: .nan, y: .infinity)
        let size = NormalizedSize(width: -.infinity, height: .nan)
        let rect = NormalizedRect(x: .nan, y: .infinity, width: .infinity, height: .nan)
        let color = RGBAColor(red: .nan, green: .infinity, blue: -.infinity, alpha: .nan)
        let style = MarkStyle(color: color, strokeWidth: 4, opacity: .nan)
        let toolState = ToolState(spotlightDimness: .nan)

        XCTAssertEqual(point.x, 0)
        XCTAssertEqual(point.y, 1)
        XCTAssertEqual(size.width, 0)
        XCTAssertEqual(size.height, 0)
        XCTAssertEqual(rect, NormalizedRect(x: 0, y: 1, width: 1, height: 0))
        XCTAssertEqual(color, RGBAColor(red: 0, green: 1, blue: 0, alpha: 0))
        XCTAssertEqual(style.opacity, 0)
        XCTAssertEqual(toolState.spotlightDimness, 0)
    }
}
