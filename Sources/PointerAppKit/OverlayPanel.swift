import AppKit
import PointerCore

@MainActor
public final class OverlayPanel: NSPanel, OverlayPresenting {
    public private(set) var display: DisplayDescriptor
    public let canvasView: CanvasView
    private var didClose = false

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
        ignoresMouseEvents = session.mode == .standby
    }

    public func setMode(_ mode: PointerMode) {
        ignoresMouseEvents = mode == .standby

        var updatedSession = canvasView.session
        if updatedSession.mode != mode {
            updatedSession.apply(.setMode(mode))
        }
        canvasView.update(session: updatedSession)
    }

    public func cancelActiveGesture() {
        canvasView.cancelGesture()
    }

    public func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {
        guard !didClose else { return }
        canvasView.onSessionUpdate = onSessionUpdate
        canvasView.onBoundaryEvent = onBoundaryEvent
    }

    public func show() {
        guard !didClose else { return }
        orderFrontRegardless()
    }

    public func stopAndClear() -> OverlayCleanupResult {
        guard !didClose else {
            return OverlayCleanupResult(
                cancelledActiveGesture: false,
                clearedHandlerCount: 0,
                remainingHandlerCount: 0,
                didClose: false
            )
        }

        let clearedHandlerCount =
            (canvasView.onSessionUpdate == nil ? 0 : 1)
            + (canvasView.onBoundaryEvent == nil ? 0 : 1)
            + (canvasView.onRedrawRequested == nil ? 0 : 1)
        let cancelledActiveGesture = canvasView.hasActiveGesture
        if cancelledActiveGesture {
            canvasView.cancelGesture()
        }
        canvasView.onSessionUpdate = nil
        canvasView.onBoundaryEvent = nil
        canvasView.onRedrawRequested = nil

        return OverlayCleanupResult(
            cancelledActiveGesture: cancelledActiveGesture,
            clearedHandlerCount: clearedHandlerCount,
            remainingHandlerCount: 0,
            didClose: closeIfNeeded()
        )
    }

    public override func close() {
        _ = stopAndClear()
    }

    private func closeIfNeeded() -> Bool {
        guard !didClose else { return false }
        didClose = true
        orderOut(nil)
        super.close()
        return true
    }
}
