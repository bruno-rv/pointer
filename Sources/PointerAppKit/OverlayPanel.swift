import AppKit
import PointerCore

@MainActor
public final class OverlayPanel: NSPanel, OverlayPresenting {
    private enum LifecycleState {
        case open
        case stopping
        case closed
    }

    public private(set) var display: DisplayDescriptor
    public let canvasView: CanvasView
    private var lifecycleState: LifecycleState = .open

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
        guard lifecycleState == .open else { return }

        let modeChanged = canvasView.session.mode != mode
        if modeChanged, canvasView.hasActiveGesture {
            canvasView.cancelGesture()
            guard lifecycleState == .open else { return }
        }

        var updatedSession = canvasView.session
        let currentModeChanged = updatedSession.mode != mode
        if currentModeChanged {
            updatedSession.apply(.setMode(mode))
        }
        canvasView.update(session: updatedSession)
        ignoresMouseEvents = mode == .standby
        if currentModeChanged {
            canvasView.onSessionUpdate?(updatedSession)
        }
    }

    public func cancelActiveGesture() {
        guard lifecycleState == .open else { return }
        canvasView.cancelGesture()
    }

    public func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {
        guard lifecycleState == .open else { return }
        canvasView.onSessionUpdate = onSessionUpdate
        canvasView.onBoundaryEvent = onBoundaryEvent
    }

    public func show() {
        guard lifecycleState == .open else { return }
        orderFrontRegardless()
    }

    public func stopAndClear() -> OverlayCleanupResult {
        guard lifecycleState == .open else {
            return OverlayCleanupResult(
                cancelledActiveGesture: false,
                clearedHandlerCount: 0,
                remainingHandlerCount: 0,
                didClose: false
            )
        }

        lifecycleState = .stopping
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
        guard lifecycleState == .stopping else { return false }
        lifecycleState = .closed
        orderOut(nil)
        super.close()
        return true
    }
}
