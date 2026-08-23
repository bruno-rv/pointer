import PointerCore
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

    func testFixtureUsesExactStableDisplayDescriptors() {
        let expectedFirst = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "display-a"),
            frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
            scaleFactor: 2
        )
        let expectedSecond = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "display-b"),
            frame: DisplayFrame(x: 1_920, y: 0, width: 1_920, height: 1_080),
            visibleFrame: DisplayFrame(x: 1_920, y: 24, width: 1_920, height: 1_056),
            scaleFactor: 1
        )

        XCTAssertEqual(DisplayFixtures.oneDisplay(), [expectedFirst])
        XCTAssertEqual(DisplayFixtures.twoDisplays(), [expectedFirst, expectedSecond])
    }

    func testNarrowInvalidAndReconnectFixturesPreserveTheirContracts() throws {
        let narrow = try XCTUnwrap(DisplayFixtures.narrowDisplay().first)
        XCTAssertEqual(narrow.uuid.rawValue, "display-a")
        XCTAssertEqual(narrow.frame, DisplayFrame(x: 0, y: 0, width: 420, height: 1_080))
        XCTAssertEqual(narrow.visibleFrame, DisplayFrame(x: 0, y: 24, width: 420, height: 1_056))
        XCTAssertEqual(narrow.scaleFactor, 2)

        let invalid = try XCTUnwrap(DisplayFixtures.invalidDisplayIdentifier().first)
        XCTAssertEqual(invalid.uuid.rawValue, "")

        let reconnect = DisplayFixtures.disconnectedAndReconnected()
        let disconnected = try XCTUnwrap(reconnect.disconnected.first)
        let reconnected = try XCTUnwrap(reconnect.reconnected.first)
        XCTAssertEqual(disconnected.uuid.rawValue, "display-a")
        XCTAssertEqual(reconnected.uuid, disconnected.uuid)
        XCTAssertEqual(reconnected.uuid, reconnect.reconnectUUID)
        XCTAssertNotEqual(reconnected.frame, disconnected.frame)
        XCTAssertNotEqual(reconnected.visibleFrame, disconnected.visibleFrame)
        XCTAssertNotEqual(reconnected.scaleFactor, disconnected.scaleFactor)
        XCTAssertEqual(reconnected.frame, DisplayFrame(x: 0, y: 0, width: 2_560, height: 1_440))
        XCTAssertEqual(reconnected.visibleFrame, DisplayFrame(x: 0, y: 24, width: 2_560, height: 1_416))
        XCTAssertEqual(reconnected.scaleFactor, 1)
    }

    @MainActor
    func testScreenProviderReflectsMutableDisplaysAndPointerUUIDThroughProtocolMethods() {
        let provider = DeterministicScreenProvider(
            displays: DisplayFixtures.oneDisplay(),
            pointerUUID: DisplayUUID(rawValue: "display-a")
        )
        let screenProvider: any ScreenProviding = provider

        XCTAssertEqual(screenProvider.currentDisplays(), DisplayFixtures.oneDisplay())
        XCTAssertEqual(screenProvider.pointerDisplay()?.rawValue, "display-a")

        provider.displays = DisplayFixtures.twoDisplays()
        provider.pointerUUID = DisplayUUID(rawValue: "display-b")

        XCTAssertEqual(screenProvider.currentDisplays(), DisplayFixtures.twoDisplays())
        XCTAssertEqual(screenProvider.pointerDisplay()?.rawValue, "display-b")

        provider.displays = DisplayFixtures.empty()
        provider.pointerUUID = nil

        XCTAssertTrue(screenProvider.currentDisplays().isEmpty)
        XCTAssertNil(screenProvider.pointerDisplay())
    }

    func testClockAdvancesByExactNanoseconds() {
        let clock = DeterministicClock(nowNanoseconds: 100)

        clock.advance(by: 23)
        XCTAssertEqual(clock.nowNanoseconds, 123)
        clock.advance(by: 0)
        XCTAssertEqual(clock.nowNanoseconds, 123)
    }

    func testClockSaturatesAtUInt64MaxOnOverflow() {
        let clock = DeterministicClock(nowNanoseconds: UInt64.max - 1)

        clock.advance(by: 2)

        XCTAssertEqual(clock.nowNanoseconds, UInt64.max)
    }
}
