import PointerCore

public struct OverlayCleanupResult: Equatable, Sendable {
    public let cancelledActiveGesture: Bool
    public let clearedHandlerCount: Int
    public let remainingHandlerCount: Int
    public let didClose: Bool

    public init(
        cancelledActiveGesture: Bool,
        clearedHandlerCount: Int,
        remainingHandlerCount: Int,
        didClose: Bool
    ) {
        self.cancelledActiveGesture = cancelledActiveGesture
        self.clearedHandlerCount = clearedHandlerCount
        self.remainingHandlerCount = remainingHandlerCount
        self.didClose = didClose
    }
}

@MainActor
public protocol OverlayPresenting: AnyObject {
    var display: DisplayDescriptor { get }

    func update(display: DisplayDescriptor)
    func update(session: PointerSession)
    func setMode(_ mode: PointerMode)
    func cancelActiveGesture()
    func show()
    func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    )
    func close()
    func stopAndClear() -> OverlayCleanupResult
}

public extension OverlayPresenting {
    func show() {}

    func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {}

    func cancelActiveGesture() {}

    func stopAndClear() -> OverlayCleanupResult {
        OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: false
        )
    }
}
