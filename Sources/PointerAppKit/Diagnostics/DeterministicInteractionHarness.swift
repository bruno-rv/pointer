import AppKit
import PointerCore

@MainActor
public struct DeterministicInteractionSnapshot: Equatable, Sendable {
    public let mode: PointerMode
    public let selectedTool: PointerTool
    public let selectedStyle: MarkStyle
    public let selection: Mark.ID?
    public let marksByDisplay: [DisplayUUID: [Mark]]
    public let previewMarksByDisplay: [DisplayUUID: [Mark]]
    public let activeDraftMarkID: Mark.ID?
    public let handleInventory: HandleInventory
    public let undoAvailable: Bool
    public let shortcutID: String?
    public let shortcutError: String?
    public let connectedDisplays: Set<DisplayUUID>

    public init(
        mode: PointerMode,
        selectedTool: PointerTool,
        selectedStyle: MarkStyle,
        selection: Mark.ID?,
        marksByDisplay: [DisplayUUID: [Mark]],
        previewMarksByDisplay: [DisplayUUID: [Mark]],
        activeDraftMarkID: Mark.ID?,
        handleInventory: HandleInventory,
        undoAvailable: Bool,
        shortcutID: String?,
        shortcutError: String?,
        connectedDisplays: Set<DisplayUUID>
    ) {
        self.mode = mode
        self.selectedTool = selectedTool
        self.selectedStyle = selectedStyle
        self.selection = selection
        self.marksByDisplay = marksByDisplay
        self.previewMarksByDisplay = previewMarksByDisplay
        self.activeDraftMarkID = activeDraftMarkID
        self.handleInventory = handleInventory
        self.undoAvailable = undoAvailable
        self.shortcutID = shortcutID
        self.shortcutError = shortcutError
        self.connectedDisplays = connectedDisplays
    }
}

@MainActor
public protocol InteractionClock: AnyObject {
    var nowNanoseconds: UInt64 { get }
}

@MainActor
public enum DeterministicInteractionError: Error, Equatable, Sendable {
    case invalidDisplay(DisplayUUID)
    case unavailableOverlay(DisplayUUID)
}

@MainActor
public final class DeterministicInteractionHarness {
    private let displayCoordinator: DisplayCoordinator
    private let commandRouter: CommandRouter
    private let metadataProvider: any ControlMetadataProviding
    private let clock: any InteractionClock

    public init(
        displayCoordinator: DisplayCoordinator,
        commandRouter: CommandRouter,
        metadataProvider: any ControlMetadataProviding,
        clock: any InteractionClock
    ) {
        self.displayCoordinator = displayCoordinator
        self.commandRouter = commandRouter
        self.metadataProvider = metadataProvider
        self.clock = clock
    }

    @discardableResult
    public func synchronizeDisplays() -> DisplaySyncResult {
        displayCoordinator.synchronize()
    }

    public func route(_ command: CommandRouter.Command) {
        commandRouter.route(command)
    }

    @discardableResult
    public func routeLocalKey(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) -> Bool {
        commandRouter.routeLocalKeyEvent(keyCode: keyCode, modifierFlags: modifiers)
    }

    public func beginGesture(at point: NSPoint, on display: DisplayUUID) throws {
        try canvasView(for: display).beginGesture(at: point)
    }

    public func continueGesture(to point: NSPoint, on display: DisplayUUID) throws {
        try canvasView(for: display).continueGesture(to: point)
    }

    public func endGesture(on display: DisplayUUID) throws {
        try canvasView(for: display).endGesture()
    }

    public func cancelGesture(on display: DisplayUUID) throws {
        try canvasView(for: display).cancelGesture()
    }

    public func snapshot() -> DeterministicInteractionSnapshot {
        let session = displayCoordinator.session
        let orderedOverlays = displayCoordinator.overlays.keys.sorted {
            $0.rawValue < $1.rawValue
        }
        let connectedDisplays = Set(orderedOverlays)
        var marksByDisplay: [DisplayUUID: [Mark]] = [:]
        var previewMarksByDisplay: [DisplayUUID: [Mark]] = [:]
        var plans: [(DisplayUUID, RenderPlan)] = []

        for display in orderedOverlays {
            marksByDisplay[display] = session.canvas(for: display).marks
            guard let overlay = displayCoordinator.overlays[display] as? OverlayPanel else {
                continue
            }
            previewMarksByDisplay[display] = overlay.canvasView.session
                .previewCanvas(for: display)
                .marks
            plans.append((display, overlay.canvasView.renderPlan))
        }

        let selectedPlan = session.selectedDisplay.flatMap { selectedDisplay in
            plans.first { display, plan in
                display == selectedDisplay
                    && plan.handles.selection.selectedMarkID == session.selection
            }?.1
        }
        let activeDraftMarkID = plans.compactMap { $0.1.activeDraft?.id }.first
        let undoAvailable = connectedDisplays.contains {
            session.canUndo(on: $0)
        }

        // Reading the injected clock keeps the diagnostic dependency explicit;
        // this first slice does not invent time-based behavior.
        _ = clock.nowNanoseconds

        return DeterministicInteractionSnapshot(
            mode: session.mode,
            selectedTool: session.toolState.tool,
            selectedStyle: session.toolState.style,
            selection: session.selection,
            marksByDisplay: marksByDisplay,
            previewMarksByDisplay: previewMarksByDisplay,
            activeDraftMarkID: activeDraftMarkID,
            handleInventory: selectedPlan?.handles ?? Self.hiddenHandleInventory,
            undoAvailable: undoAvailable,
            shortcutID: commandRouter.activeShortcutID,
            shortcutError: commandRouter.shortcutError,
            connectedDisplays: connectedDisplays
        )
    }

    public func metadata() -> [ControlMetadata] {
        metadataProvider.metadata()
    }

    private func canvasView(for display: DisplayUUID) throws -> CanvasView {
        guard !display.rawValue.isEmpty,
              let overlay = displayCoordinator.overlays[display]
        else {
            throw DeterministicInteractionError.invalidDisplay(display)
        }
        guard let overlay = overlay as? OverlayPanel else {
            throw DeterministicInteractionError.unavailableOverlay(display)
        }
        return overlay.canvasView
    }

    private static let hiddenHandleInventory = HandleInventory(
        selection: SelectionInventory(selectedMarkID: nil, isVisible: false),
        hover: HoverInventory(hoveredMarkID: nil, isVisible: false),
        resize: ResizeInventory(handles: [], isVisible: false),
        contextualDeleteVisible: false
    )
}
