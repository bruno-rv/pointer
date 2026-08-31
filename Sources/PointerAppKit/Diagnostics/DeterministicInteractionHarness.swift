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

    init(
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
    private let screenProvider: any ScreenProviding
    private let displayCoordinator: DisplayCoordinator
    private let commandRouter: CommandRouter
    private let palette: any PalettePresenting
    private let menuBar: (any MenuBarPresenting)?
    private let shortcutController: HotKeyController
    private let metadataProvider: any ControlMetadataProviding
    private let clock: any InteractionClock
    private var knownDisplayUUIDs: Set<DisplayUUID> = []

    public init(
        screenProvider: any ScreenProviding,
        displayCoordinator: DisplayCoordinator,
        commandRouter: CommandRouter,
        palette: any PalettePresenting,
        menuBar: (any MenuBarPresenting)?,
        shortcutController: HotKeyController,
        metadataProvider: any ControlMetadataProviding,
        clock: any InteractionClock
    ) {
        self.screenProvider = screenProvider
        self.displayCoordinator = displayCoordinator
        self.commandRouter = commandRouter
        self.palette = palette
        self.menuBar = menuBar
        self.shortcutController = shortcutController
        self.metadataProvider = metadataProvider
        self.clock = clock
        knownDisplayUUIDs = Set(
            screenProvider.currentDisplays()
                .map(\.uuid)
                .filter { !$0.rawValue.isEmpty }
        )
    }

    @discardableResult
    public func synchronizeDisplays() -> DisplaySyncResult {
        rememberObservedDisplays()
        let result = displayCoordinator.synchronize()
        knownDisplayUUIDs.formUnion(result.connectedUUIDs)
        refreshProductionSurface()
        return result
    }

    public func route(_ command: CommandRouter.Command) {
        commandRouter.route(command)
        refreshProductionSurface()
    }

    @discardableResult
    public func routeLocalKey(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) -> Bool {
        let handled = commandRouter.routeLocalKeyEvent(
            keyCode: keyCode,
            modifierFlags: modifiers
        )
        refreshProductionSurface()
        return handled
    }

    public func beginGesture(at point: NSPoint, on display: DisplayUUID) throws {
        try canvasView(for: display).beginGesture(at: point)
        refreshProductionSurface()
    }

    public func continueGesture(to point: NSPoint, on display: DisplayUUID) throws {
        try canvasView(for: display).continueGesture(to: point)
        refreshProductionSurface()
    }

    public func endGesture(on display: DisplayUUID) throws {
        try canvasView(for: display).endGesture()
        refreshProductionSurface()
    }

    public func cancelGesture(on display: DisplayUUID) throws {
        try canvasView(for: display).cancelGesture()
        refreshProductionSurface()
    }

    public func snapshot() -> DeterministicInteractionSnapshot {
        let session = displayCoordinator.session
        let orderedOverlays = displayCoordinator.overlays.keys.sorted {
            $0.rawValue < $1.rawValue
        }
        let connectedDisplays = Set(orderedOverlays)
        let knownDisplays = knownDisplayUUIDs.union(connectedDisplays).sorted {
            $0.rawValue < $1.rawValue
        }
        var marksByDisplay: [DisplayUUID: [Mark]] = [:]
        var previewMarksByDisplay: [DisplayUUID: [Mark]] = [:]
        var plans: [(DisplayUUID, RenderPlan)] = []

        for display in knownDisplays {
            marksByDisplay[display] = session.canvas(for: display).marks
            guard let overlay = displayCoordinator.overlays[display] as? OverlayPanel else {
                previewMarksByDisplay[display] = session.previewCanvas(for: display).marks
                continue
            }
            previewMarksByDisplay[display] = overlay.canvasView.session
                .previewCanvas(for: display)
                .marks
            plans.append((display, overlay.canvasView.renderPlan))
        }

        let selectedPlan: RenderPlan? = session.selectedDisplay.flatMap { selectedDisplay in
            guard let selection = session.selection else { return nil }
            return plans.first { display, plan in
                display == selectedDisplay
                    && plan.handles.selection.selectedMarkID == selection
            }?.1
        }
        let activeDraftMarkID: Mark.ID? = plans.compactMap { display, plan in
            guard let overlay = displayCoordinator.overlays[display] as? OverlayPanel,
                  overlay.canvasView.hasActiveGesture,
                  session.hasActiveGesture(on: display)
            else {
                return nil
            }
            let committedIDs = Set(
                overlay.canvasView.session.canvas(for: display).marks.map(\.id)
            )
            let draftCandidates = overlay.canvasView.session
                .previewCanvas(for: display)
                .marks
                .filter { !committedIDs.contains($0.id) }
            guard draftCandidates.count == 1,
                  plan.activeDraft == draftCandidates[0]
            else {
                return nil
            }
            return draftCandidates[0].id
        }.first
        let undoAvailable = knownDisplays.contains {
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
            shortcutID: shortcutController.activePreset?.rawValue,
            shortcutError: shortcutController.registrationError,
            connectedDisplays: connectedDisplays
        )
    }

    public func metadata() -> [ControlMetadata] {
        metadataProvider.metadata()
    }

    private func rememberObservedDisplays() {
        knownDisplayUUIDs.formUnion(
            screenProvider.currentDisplays()
                .map(\.uuid)
                .filter { !$0.rawValue.isEmpty }
        )
    }

    private func refreshProductionSurface() {
        let session = displayCoordinator.session
        palette.refresh(session: session)
        menuBar?.refresh(session: session)
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
