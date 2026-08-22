import AppKit
import PointerCore

@MainActor
public final class CanvasView: NSView {
    public let display: DisplayUUID
    public var tool: PointerTool
    public private(set) var session: PointerSession
    public var onBoundaryEvent: ((GestureBoundaryEvent) -> Void)?
    public var onSessionUpdate: ((PointerSession) -> Void)?
    public var onRedrawRequested: (() -> Void)?

    public init(
        frame frameRect: NSRect,
        display: DisplayUUID,
        session: PointerSession = PointerSession(),
        tool: PointerTool = .arrow
    ) {
        self.display = display
        self.session = session
        self.tool = tool
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CanvasView does not support storyboards.")
    }

    public func update(session: PointerSession) {
        self.session = session
        needsDisplay = true
    }

    public func normalizedPoint(for point: NSPoint) -> NormalizedPoint {
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        return NormalizedPoint(
            x: Double((point.x - bounds.minX) / width),
            y: Double((point.y - bounds.minY) / height)
        )
    }

    public func beginGesture(at point: NSPoint) {
        let update = session.beginGesture(
            tool: tool,
            at: normalizedPoint(for: point),
            on: display
        )
        apply(update: update)
    }

    public func continueGesture(to point: NSPoint) {
        let update = session.advanceGesture(to: normalizedPoint(for: point))
        apply(update: update)
    }

    public func endGesture() {
        let commit = session.commitGesture()
        needsDisplay = true
        onRedrawRequested?()
        onSessionUpdate?(session)
        onBoundaryEvent?(commit.boundaryEvent)
    }

    public func cancelGesture() {
        let cancellation = session.cancelGesture()
        needsDisplay = true
        onRedrawRequested?()
        onSessionUpdate?(session)
        onBoundaryEvent?(cancellation.boundaryEvent)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        MarkRenderer.draw(
            canvas: session.previewCanvas(for: display),
            in: bounds,
            context: context
        )
    }

    public override func mouseDown(with event: NSEvent) {
        beginGesture(at: convert(event.locationInWindow, from: nil))
    }

    public override func mouseDragged(with event: NSEvent) {
        continueGesture(to: convert(event.locationInWindow, from: nil))
    }

    public override func mouseUp(with event: NSEvent) {
        endGesture()
    }

    private func apply(update: GestureUpdate) {
        if update.needsRedraw {
            needsDisplay = true
            onRedrawRequested?()
        }
        if update.boundaryEvent != nil {
            onSessionUpdate?(session)
        }
        if let boundaryEvent = update.boundaryEvent {
            onBoundaryEvent?(boundaryEvent)
        }
    }
}
