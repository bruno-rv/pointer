import PointerCore
import XCTest
@testable import PointerAppKit

final class SmokeRunnerTests: XCTestCase {
    func testSmokeReportPlansOnePaletteAndOverlayPerDisplay() {
        let report = SmokeRunner.report(displays: SmokeFixtures.displays)

        XCTAssertEqual(report.paletteCount, 1)
        XCTAssertEqual(report.overlayCount, 2)
        XCTAssertEqual(report.mode, .standby)
        XCTAssertEqual(report.shortcutID, "control-option-command-p")
    }

    func testSmokeReportIncludesStableDefaultToolAndStyle() throws {
        let report = SmokeRunner.report(displays: SmokeFixtures.displays)
        XCTAssertEqual(report.paletteCount, 1)
        XCTAssertEqual(report.overlayCount, 2)
        XCTAssertEqual(report.mode, .standby)
        XCTAssertEqual(report.selectedToolID, "arrow")
        XCTAssertEqual(report.styleColorRGBA, [1, 0, 0, 1])
        XCTAssertEqual(report.strokeWidth, 4)
        XCTAssertEqual(report.opacity, 1)
        XCTAssertEqual(report.shortcutID, "control-option-command-p")
    }

    func testSmokeJSONIsStableAndContainsNoWindowRequirement() throws {
        let first = try SmokeRunner.json(displays: SmokeFixtures.displays)
        let second = try SmokeRunner.json(displays: SmokeFixtures.displays)
        XCTAssertEqual(first, second)
        XCTAssertEqual(String(decoding: first, as: UTF8.self),
                       "{\"mode\":\"standby\",\"opacity\":1,\"overlayCount\":2,\"paletteCount\":1,\"selectedToolID\":\"arrow\",\"shortcutID\":\"control-option-command-p\",\"strokeWidth\":4,\"styleColorRGBA\":[1,0,0,1]}")
    }
}
