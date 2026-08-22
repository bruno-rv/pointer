import XCTest
@testable import PointerCore

final class PalettePlacementTests: XCTestCase {
    func testPlacementCentersNearTopAndClampsToVisibleFrame() {
        let visibleFrame = DenormalizedRect(x: 1_920, y: 0, width: 800, height: 600)
        let size = DenormalizedSize(width: 760, height: 160)

        let placement = PalettePlacement.nearTopCenter(
            paletteSize: size,
            in: visibleFrame,
            margin: 16
        )

        XCTAssertEqual(placement, DenormalizedRect(x: 1_940, y: 424, width: 760, height: 160))
    }
}
