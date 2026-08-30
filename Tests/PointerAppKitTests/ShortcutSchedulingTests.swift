import XCTest
@testable import PointerAppKit

@MainActor
final class ShortcutSchedulingTests: XCTestCase {
    func testLongScheduleReportsOneActiveTimerUntilCancellation() {
        let scheduler = DispatchShortcutScheduler()
        var actionCount = 0

        let token = scheduler.schedule(after: 60) {
            actionCount += 1
        }

        XCTAssertEqual(scheduler.activeTimerCount, 1)
        scheduler.cancel(token)
        XCTAssertEqual(scheduler.activeTimerCount, 0)
        XCTAssertEqual(actionCount, 0)
    }

    func testShortScheduleRemovesActiveTimerBeforeInvokingAction() async {
        let scheduler = DispatchShortcutScheduler()
        let actionExpectation = expectation(description: "scheduled action runs once")
        var actionCount = 0

        _ = scheduler.schedule(after: 0.01) {
            actionCount += 1
            XCTAssertEqual(scheduler.activeTimerCount, 0)
            actionExpectation.fulfill()
        }

        await fulfillment(of: [actionExpectation], timeout: 1)
        XCTAssertEqual(actionCount, 1)
        XCTAssertEqual(scheduler.activeTimerCount, 0)
    }
}
