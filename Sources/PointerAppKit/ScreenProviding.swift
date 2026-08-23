import AppKit
import PointerCore

public struct DisplaySyncResult: Equatable, Sendable {
    public let connectedUUIDs: Set<DisplayUUID>
    public let addedUUIDs: Set<DisplayUUID>
    public let removedUUIDs: Set<DisplayUUID>
    public let pointerDisplay: DisplayUUID?
    public let hasConnectedDisplays: Bool
    public let enteredZeroDisplayState: Bool
    public let reconnected: Bool

    public init(
        connectedUUIDs: Set<DisplayUUID>,
        addedUUIDs: Set<DisplayUUID>,
        removedUUIDs: Set<DisplayUUID>,
        pointerDisplay: DisplayUUID?,
        hasConnectedDisplays: Bool,
        enteredZeroDisplayState: Bool,
        reconnected: Bool
    ) {
        self.connectedUUIDs = connectedUUIDs
        self.addedUUIDs = addedUUIDs
        self.removedUUIDs = removedUUIDs
        self.pointerDisplay = pointerDisplay
        self.hasConnectedDisplays = hasConnectedDisplays
        self.enteredZeroDisplayState = enteredZeroDisplayState
        self.reconnected = reconnected
    }
}

public struct DisplayStopResult: Equatable, Sendable {
    public let closedOverlayCount: Int
    public let remainingOverlayCount: Int
    public let activeGestureCount: Int
    public let clearedHandlerCount: Int
    public let boundHandlerCount: Int

    public init(
        closedOverlayCount: Int,
        remainingOverlayCount: Int,
        activeGestureCount: Int,
        clearedHandlerCount: Int,
        boundHandlerCount: Int
    ) {
        self.closedOverlayCount = closedOverlayCount
        self.remainingOverlayCount = remainingOverlayCount
        self.activeGestureCount = activeGestureCount
        self.clearedHandlerCount = clearedHandlerCount
        self.boundHandlerCount = boundHandlerCount
    }
}

public struct DisplayFrame: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct DisplayDescriptor: Equatable, Sendable {
    public let uuid: DisplayUUID
    public let frame: DisplayFrame
    public let visibleFrame: DisplayFrame
    public let scaleFactor: Double

    public init(
        uuid: DisplayUUID,
        frame: DisplayFrame,
        visibleFrame: DisplayFrame,
        scaleFactor: Double
    ) {
        self.uuid = uuid
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scaleFactor = scaleFactor
    }
}

@MainActor
public protocol ScreenProviding {
    func currentDisplays() -> [DisplayDescriptor]
    func pointerDisplay() -> DisplayUUID?
}
