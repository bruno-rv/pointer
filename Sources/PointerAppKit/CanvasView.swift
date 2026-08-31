import AppKit
import PointerCore

@MainActor
public final class CanvasView: NSView {
    public enum CursorPlan: Equatable, Sendable {
        case clickThrough
        case select
        case draw
        case erase
        case emoji
        case spotlight
    }

    public let display: DisplayUUID
    public var tool: PointerTool {
        didSet {
            updateCursorPlan()
        }
    }
    public private(set) var session: PointerSession
    public private(set) var cursorPlan: CursorPlan
    public private(set) var renderPlan: RenderPlan
    public var onBoundaryEvent: ((GestureBoundaryEvent) -> Void)?
    public var onSessionUpdate: ((PointerSession) -> Void)?
    public var onRedrawRequested: (() -> Void)?
    public private(set) var hasActiveGesture = false

    private var currentHoverInventory = HoverInventory(hoveredMarkID: nil, isVisible: false)

    public init(
        frame frameRect: NSRect,
        display: DisplayUUID,
        session: PointerSession = PointerSession(),
        tool: PointerTool = .arrow
    ) {
        self.display = display
        self.session = session
        self.tool = tool
        self.cursorPlan = Self.cursorPlan(for: tool, mode: session.mode)
        self.hasActiveGesture = session.hasActiveGesture(on: display)
        self.renderPlan = Self.renderPlan(for: session, display: display, hover: currentHoverInventory)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CanvasView does not support storyboards.")
    }

    public func update(session: PointerSession) {
        hasActiveGesture = session.hasActiveGesture(on: display)
        self.session = session
        updateCursorPlan()
        updateRenderPlan()
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
        hasActiveGesture = true
        let update = session.beginGesture(
            tool: tool,
            at: normalizedPoint(for: point),
            on: display
        )
        apply(update: update)
    }

    public func continueGesture(to point: NSPoint) {
        guard hasActiveGesture else { return }
        let update = session.advanceGesture(to: normalizedPoint(for: point))
        apply(update: update)
    }

    public func endGesture() {
        guard hasActiveGesture else { return }
        hasActiveGesture = false
        let commit = session.commitGesture()
        let redrawHandler = onRedrawRequested
        let sessionHandler = onSessionUpdate
        let boundaryHandler = onBoundaryEvent
        updateRenderPlan()
        needsDisplay = true
        redrawHandler?()
        sessionHandler?(session)
        boundaryHandler?(commit.boundaryEvent)
    }

    public func cancelGesture() {
        guard hasActiveGesture else { return }
        hasActiveGesture = false
        let cancellation = session.cancelGesture()
        let redrawHandler = onRedrawRequested
        let sessionHandler = onSessionUpdate
        let boundaryHandler = onBoundaryEvent
        updateRenderPlan()
        needsDisplay = true
        redrawHandler?()
        sessionHandler?(session)
        boundaryHandler?(cancellation.boundaryEvent)
        setCursorPlan(.clickThrough)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        MarkRenderer.draw(
            plan: renderPlan,
            in: bounds,
            context: context
        )
    }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
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
        let redrawHandler = onRedrawRequested
        let sessionHandler = onSessionUpdate
        let boundaryHandler = onBoundaryEvent
        updateRenderPlan()
        if update.needsRedraw {
            needsDisplay = true
            redrawHandler?()
        }
        if update.boundaryEvent != nil {
            sessionHandler?(session)
        }
        if let boundaryEvent = update.boundaryEvent {
            boundaryHandler?(boundaryEvent)
        }
    }

    private func updateRenderPlan() {
        renderPlan = Self.renderPlan(for: session, display: display, hover: currentHoverInventory)
    }

    private static func renderPlan(
        for session: PointerSession,
        display: DisplayUUID,
        hover: HoverInventory
    ) -> RenderPlan {
        let committedCanvas = session.canvas(for: display)
        let previewCanvas = session.previewCanvas(for: display)
        let activeDraft = previewCanvas.marks.first { previewMark in
            !committedCanvas.marks.contains { committedMark in
                committedMark.id == previewMark.id
            }
        }
        return RenderPlan.make(
            canvas: previewCanvas,
            mode: session.mode,
            selectedID: session.selection,
            activeDraft: activeDraft,
            hover: hover
        )
    }

    private var cursor: NSCursor {
        switch cursorPlan {
        case .clickThrough, .select:
            return .arrow
        case .draw:
            return .crosshair
        case .erase:
            return .operationNotAllowed
        case .emoji:
            return .pointingHand
        case .spotlight:
            return .openHand
        }
    }

    private func updateCursorPlan() {
        setCursorPlan(Self.cursorPlan(for: tool, mode: session.mode))
    }

    private func setCursorPlan(_ plan: CursorPlan) {
        guard cursorPlan != plan else { return }
        cursorPlan = plan
        if let window {
            window.invalidateCursorRects(for: self)
        } else {
            discardCursorRects()
        }
    }

    private static func cursorPlan(for tool: PointerTool, mode: PointerMode) -> CursorPlan {
        guard mode == .annotation else { return .clickThrough }
        switch tool {
        case .select:
            return .select
        case .arrow, .rectangle, .ellipse, .pen:
            return .draw
        case .eraser:
            return .erase
        case .emoji:
            return .emoji
        case .spotlight:
            return .spotlight
        }
    }
}
