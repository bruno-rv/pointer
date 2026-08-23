import PointerCore
@testable import PointerAppKit

enum DisplayFixtures {
    private static let displayAUUID = DisplayUUID(rawValue: "display-a")
    private static let displayBUUID = DisplayUUID(rawValue: "display-b")

    static func empty() -> [DisplayDescriptor] {
        []
    }

    static func oneDisplay() -> [DisplayDescriptor] {
        [displayA]
    }

    static func twoDisplays() -> [DisplayDescriptor] {
        [displayA, displayB]
    }

    static func narrowDisplay() -> [DisplayDescriptor] {
        [DisplayDescriptor(
            uuid: displayAUUID,
            frame: DisplayFrame(x: 0, y: 0, width: 420, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 420, height: 1_056),
            scaleFactor: 2
        )]
    }

    static func invalidDisplayIdentifier() -> [DisplayDescriptor] {
        [DisplayDescriptor(
            uuid: DisplayUUID(rawValue: ""),
            frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
            scaleFactor: 2
        )]
    }

    static func disconnectedAndReconnected() -> DisplayReconnectFixtures {
        DisplayReconnectFixtures(
            disconnected: [displayA],
            reconnected: [reconnectedDisplayA],
            reconnectUUID: displayAUUID
        )
    }

    private static let displayA = DisplayDescriptor(
        uuid: displayAUUID,
        frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
        visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
        scaleFactor: 2
    )

    private static let displayB = DisplayDescriptor(
        uuid: displayBUUID,
        frame: DisplayFrame(x: 1_920, y: 0, width: 1_920, height: 1_080),
        visibleFrame: DisplayFrame(x: 1_920, y: 24, width: 1_920, height: 1_056),
        scaleFactor: 1
    )

    private static let reconnectedDisplayA = DisplayDescriptor(
        uuid: displayAUUID,
        frame: DisplayFrame(x: 0, y: 0, width: 2_560, height: 1_440),
        visibleFrame: DisplayFrame(x: 0, y: 24, width: 2_560, height: 1_416),
        scaleFactor: 1
    )
}

struct DisplayReconnectFixtures {
    let disconnected: [DisplayDescriptor]
    let reconnected: [DisplayDescriptor]
    let reconnectUUID: DisplayUUID
}
