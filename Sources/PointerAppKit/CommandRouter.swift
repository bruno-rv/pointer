import AppKit
import PointerCore

@MainActor
public final class CommandRouter {
    public enum Command {
        case escape
        case delete
        case undo
        case clear
        case clearAll
        case undoClearAll
        case setTool(PointerTool)
        case setStyle(MarkStyle)
        case setEmoji(String)
        case setSpotlight(radius: Double, dimness: Double)
        case setMode(PointerMode)
        case toggleMode
        case setShortcut(ShortcutPreset)
    }

    public var onStateChange: ((PointerSession) -> Void)?
    public var onClearAllRequested: (() -> Void)?
    public var onAnnotationEntry: (() -> Void)?
    public var onFeedback: ((String) -> Void)?

    public private(set) var feedbackMessage: String?

    public private(set) var lastHandledCommand: Command?

    private let coordinator: DisplayCoordinator
    private let screenProvider: any ScreenProviding
    private weak var shortcutController: HotKeyController?
    private var acceptedDisplayState: DisplaySyncResult?
    private var lastObservedSession: PointerSession?
    private var pendingSelectionClearID: Mark.ID?

    public init(
        coordinator: DisplayCoordinator,
        screenProvider: any ScreenProviding,
        shortcutController: HotKeyController? = nil
    ) {
        self.coordinator = coordinator
        self.screenProvider = screenProvider
        self.shortcutController = shortcutController
        self.lastObservedSession = coordinator.session
        let existingDisplaySync = coordinator.onDisplaySync
        coordinator.onSessionUpdate = { [weak self] session in
            self?.observeSession(session)
            self?.onStateChange?(session)
        }
        coordinator.onDisplaySync = { [weak self] result in
            self?.updateDisplayState(result)
            existingDisplaySync?(result)
        }
        shortcutController?.onStateChange = { [weak self] in
            guard let self else { return }
            self.onStateChange?(self.session)
        }
    }

    public var session: PointerSession {
        coordinator.session
    }

    public var canUndoClearAll: Bool {
        coordinator.session.canUndoClearAll
    }

    public var pointerDisplay: DisplayUUID? {
        acceptedPointerDisplay
    }

    public var activeShortcutID: String? {
        shortcutController?.activePreset?.rawValue
    }

    public var shortcutError: String? {
        shortcutController?.registrationError
    }

    @discardableResult
    public func bindCallbacks(
        onStateChange: ((PointerSession) -> Void)?,
        onClearAllRequested: (() -> Void)?,
        onAnnotationEntry: (() -> Void)?
    ) -> Int {
        self.onStateChange = onStateChange
        self.onClearAllRequested = onClearAllRequested
        self.onAnnotationEntry = onAnnotationEntry
        return (onStateChange == nil ? 0 : 1)
            + (onClearAllRequested == nil ? 0 : 1)
            + (onAnnotationEntry == nil ? 0 : 1)
    }

    public func clearCallbacks() {
        onStateChange = nil
        onClearAllRequested = nil
        onAnnotationEntry = nil
    }

    public func updateDisplayState(_ result: DisplaySyncResult) {
        acceptedDisplayState = result
        if acceptedPointerDisplay == nil {
            pendingSelectionClearID = nil
        }
    }

    public func route(_ command: Command) {
        lastHandledCommand = command

        switch command {
        case .escape:
            clearFeedback()
            coordinator.cancelActiveGestures()
            coordinator.apply(.setMode(.standby), cancellingActiveGestures: false)
        case .delete:
            guard session.selection != nil else {
                publishFeedback("Select a mark to delete")
                return
            }
            clearFeedback()
            coordinator.apply(.deleteSelected)
        case .undo:
            guard let display = pointerDisplay, session.canUndo(on: display) else {
                publishFeedback("Nothing to undo")
                return
            }
            clearFeedback()
            coordinator.apply(.undo(on: display))
        case .clear:
            guard let display = pointerDisplay,
                  !session.canvas(for: display).marks.isEmpty
            else {
                publishFeedback("Nothing to clear")
                return
            }
            clearFeedback()
            coordinator.apply(.clear(display))
        case .clearAll:
            clearFeedback()
            onClearAllRequested?()
        case .undoClearAll:
            guard coordinator.session.canUndoClearAll else { return }
            clearFeedback()
            coordinator.apply(.undoClearAll)
        case let .setTool(tool):
            guard requirePointerDisplayForAnnotation() else { return }
            clearFeedback()
            coordinator.apply(.setTool(tool))
            if session.mode != .annotation {
                coordinator.apply(.setMode(.annotation))
            }
            onAnnotationEntry?()
        case let .setStyle(style):
            clearFeedback()
            coordinator.apply(.setStyle(style))
        case let .setEmoji(emoji):
            clearFeedback()
            coordinator.apply(.setEmoji(emoji))
        case let .setSpotlight(radius, dimness):
            clearFeedback()
            coordinator.apply(.setSpotlight(radius: radius, dimness: dimness))
        case let .setMode(mode):
            if mode == .annotation {
                guard requirePointerDisplayForAnnotation() else { return }
                clearFeedback()
                coordinator.apply(.setMode(mode))
                onAnnotationEntry?()
            } else {
                clearFeedback()
                coordinator.apply(.setMode(mode))
            }
        case .toggleMode:
            let nextMode: PointerMode = session.mode == .annotation ? .standby : .annotation
            if nextMode == .annotation {
                guard requirePointerDisplayForAnnotation() else { return }
                clearFeedback()
                coordinator.apply(.setMode(nextMode))
                onAnnotationEntry?()
            } else {
                clearFeedback()
                coordinator.apply(.setMode(nextMode))
            }
        case let .setShortcut(preset):
            clearFeedback()
            shortcutController?.setShortcut(preset)
        }
    }

    public func confirmClearAll() {
        clearFeedback()
        coordinator.apply(.clearAll)
    }

    public func routeLocalKeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        return routeLocalKeyEvent(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
    }

    @discardableResult
    public func routeLocalKeyEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> Bool {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        if keyCode == 53, flags.isEmpty {
            route(.escape)
            return true
        }
        if (keyCode == 51 || keyCode == 117), flags.isEmpty {
            route(.delete)
            return true
        }
        if keyCode == 6, flags == [.command] {
            route(.undo)
            return true
        }
        return false
    }

    private func requirePointerDisplayForAnnotation() -> Bool {
        guard acceptedPointerDisplay != nil
        else {
            publishFeedback("No presentation display connected")
            return false
        }
        return true
    }

    private func publishFeedback(_ message: String) {
        feedbackMessage = message
        onFeedback?(message)
    }

    private func clearFeedback() {
        feedbackMessage = nil
    }

    private var acceptedPointerDisplay: DisplayUUID? {
        guard let acceptedDisplayState,
              acceptedDisplayState.hasConnectedDisplays,
              let pointerDisplay = acceptedDisplayState.pointerDisplay,
              !pointerDisplay.rawValue.isEmpty,
              acceptedDisplayState.connectedUUIDs.contains(pointerDisplay),
              !acceptedDisplayState.connectedUUIDs.isEmpty,
              !acceptedDisplayState.connectedUUIDs.contains(where: { $0.rawValue.isEmpty })
        else {
            return nil
        }
        return pointerDisplay
    }

    private func observeSession(_ session: PointerSession) {
        defer { lastObservedSession = session }

        if let pendingSelectionClearID {
            guard session.mode == .annotation,
                  session.selection == nil,
                  acceptedSelectionMarkExists(pendingSelectionClearID, in: session)
            else {
                self.pendingSelectionClearID = nil
                return
            }

            guard acceptedDisplayHasActiveGesture(in: session) else {
                self.pendingSelectionClearID = nil
                publishFeedback("Selection cleared")
                return
            }
            return
        }

        guard let previous = lastObservedSession,
              previous.mode == .annotation,
              session.mode == .annotation,
              let selectedID = previous.selection,
              session.selection == nil,
              acceptedSelectionMarkExists(selectedID, in: session),
              acceptedDisplayHasActiveGesture(in: session)
        else {
            return
        }
        self.pendingSelectionClearID = selectedID
    }

    private func acceptedSelectionMarkExists(
        _ selectionID: Mark.ID,
        in session: PointerSession
    ) -> Bool {
        guard let acceptedDisplayState,
              acceptedDisplayState.hasConnectedDisplays,
              !acceptedDisplayState.connectedUUIDs.isEmpty,
              !acceptedDisplayState.connectedUUIDs.contains(where: { $0.rawValue.isEmpty })
        else {
            return false
        }
        return acceptedDisplayState.connectedUUIDs.contains { display in
            session.canvas(for: display).marks.contains { $0.id == selectionID }
        }
    }

    private func acceptedDisplayHasActiveGesture(in session: PointerSession) -> Bool {
        guard let acceptedDisplayState,
              acceptedDisplayState.hasConnectedDisplays,
              !acceptedDisplayState.connectedUUIDs.isEmpty,
              !acceptedDisplayState.connectedUUIDs.contains(where: { $0.rawValue.isEmpty })
        else {
            return false
        }
        return acceptedDisplayState.connectedUUIDs.contains {
            session.hasActiveGesture(on: $0)
        }
    }
}
