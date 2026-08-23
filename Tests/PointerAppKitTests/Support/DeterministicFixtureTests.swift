import XCTest
@testable import PointerAppKit

final class DeterministicFixtureTests: XCTestCase {
    @MainActor
    func testFixtureCoversEmptyOneTwoNarrowInvalidAndReconnectStates() {
        XCTAssertTrue(DisplayFixtures.empty().isEmpty)
        XCTAssertEqual(DisplayFixtures.oneDisplay().count, 1)
        XCTAssertEqual(DisplayFixtures.twoDisplays().count, 2)
        XCTAssertLessThan(DisplayFixtures.narrowDisplay()[0].visibleFrame.width, 500)
        XCTAssertEqual(DisplayFixtures.invalidDisplayIdentifier()[0].uuid.rawValue, "")
        XCTAssertEqual(DisplayFixtures.disconnectedAndReconnected().reconnectUUID.rawValue, "display-a")
    }
}
