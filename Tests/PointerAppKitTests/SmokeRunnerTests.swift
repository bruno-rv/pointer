import PointerCore
import XCTest
@testable import PointerAppKit

final class SmokeRunnerTests: XCTestCase {
    func testSmokeReportPlansOnePaletteAndOverlayPerDisplay() {
        let report = SmokeRunner.report(displays: [.builtIn, .external])

        XCTAssertEqual(report.paletteCount, 1)
        XCTAssertEqual(report.overlayCount, 2)
        XCTAssertEqual(report.mode, .standby)
        XCTAssertEqual(report.shortcutID, "control-option-command-p")
    }
}
