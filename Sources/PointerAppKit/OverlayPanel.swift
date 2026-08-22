import AppKit
import PointerCore

@MainActor
public final class OverlayPanel: NSPanel, OverlayPresenting {
    public private(set) var display: DisplayDescriptor
    public let canvasView: CanvasView

    public init(
        descriptor: DisplayDescriptor,
        session: PointerSession = PointerSession()
    ) {
        display = descriptor
        canvasView = CanvasView(
            frame: NSRect(origin: .zero, size: descriptor.frame.cgRect.size),
            display: descriptor.uuid,
            session: session,
            tool: session.toolState.tool
        )
        super.init(
            contentRect: descriptor.frame.cgRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        level = .screenSaver
        collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
        ignoresMouseEvents = session.mode == .standby
        isReleasedWhenClosed = false
        contentView = canvasView
    }

    public func update(display: DisplayDescriptor) {
        self.display = display
        setFrame(display.frame.cgRect, display: false)
        canvasView.setFrameSize(display.frame.cgRect.size)
        canvasView.needsDisplay = true
    }

    public func update(session: PointerSession) {
        canvasView.update(session: session)
        canvasView.tool = session.toolState.tool
        setMode(session.mode)
    }

    public func setMode(_ mode: PointerMode) {
        ignoresMouseEvents = mode == .standby
    }

    public func cancelActiveGesture() {
        canvasView.cancelGesture()
    }

    public func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {
        canvasView.onSessionUpdate = onSessionUpdate
        canvasView.onBoundaryEvent = onBoundaryEvent
    }

    public func show() {
        orderFrontRegardless()
    }

    public override func close() {
        orderOut(nil)
        super.close()
    }
}
