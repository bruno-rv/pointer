import XCTest
@testable import PointerAppKit

final class GestureBenchmarkTests: XCTestCase {
    func testGestureBenchmarkUsesProductionPathAndBoundaryPublication() {
        let result = GestureBenchmark.run(trials: 1, samples: 240)
        XCTAssertEqual(result.fixtureMarkCount, 12)
        XCTAssertEqual(result.samplesPerGesture, 240)
        XCTAssertEqual(result.publicationsPerGesture, [2])
        XCTAssertTrue(result.checksumIsStable)
    }
}
