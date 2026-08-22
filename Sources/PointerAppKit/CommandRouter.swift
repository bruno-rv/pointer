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

    public private(set) var lastHandledCommand: Command?

    private let coordinator: DisplayCoordinator
    private let screenProvider: any ScreenProviding
    private weak var shortcutController: HotKeyController?

    public init(
        coordinator: DisplayCoordinator,
        screenProvider: any ScreenProviding,
        shortcutController: HotKeyController? = nil
    ) {
        self.coordinator = coordinator
        self.screenProvider = screenProvider
        self.shortcutController = shortcutController
        coordinator.onSessionUpdate = { [weak self] session in
            self?.onStateChange?(session)
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
        screenProvider.pointerDisplay()
    }

    public var shortcutError: String? {
        shortcutController?.registrationError
    }

    public func route(_ command: Command) {
        lastHandledCommand = command

        switch command {
        case .escape:
            coordinator.cancelActiveGestures()
            coordinator.apply(.setMode(.standby))
        case .delete:
            coordinator.apply(.deleteSelected)
        case .undo:
            applyToPointerDisplay { .undo(on: $0) }
        case .clear:
            applyToPointerDisplay { .clear($0) }
        case .clearAll:
            onClearAllRequested?()
        case .undoClearAll:
            guard coordinator.session.canUndoClearAll else { return }
            coordinator.apply(.undoClearAll)
        case let .setTool(tool):
            coordinator.apply(.setTool(tool))
            coordinator.apply(.setMode(.annotation))
        case let .setStyle(style):
            coordinator.apply(.setStyle(style))
        case let .setEmoji(emoji):
            coordinator.apply(.setEmoji(emoji))
        case let .setSpotlight(radius, dimness):
            coordinator.apply(.setSpotlight(radius: radius, dimness: dimness))
        case let .setMode(mode):
            coordinator.apply(.setMode(mode))
        case .toggleMode:
            let nextMode: PointerMode = session.mode == .annotation ? .standby : .annotation
            coordinator.apply(.setMode(nextMode))
        case let .setShortcut(preset):
            shortcutController?.setShortcut(preset)
        }
    }

    public func confirmClearAll() {
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

    private func applyToPointerDisplay(
        _ command: (DisplayUUID) -> SessionCommand
    ) {
        guard let display = screenProvider.pointerDisplay() else { return }
        coordinator.apply(command(display))
    }
}
