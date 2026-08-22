import PointerCore

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
}

public extension OverlayPresenting {
    func show() {}

    func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {}

    func cancelActiveGesture() {}
}
