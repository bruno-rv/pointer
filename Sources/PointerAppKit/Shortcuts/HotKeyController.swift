import Foundation

@MainActor
public final class HotKeyController {
    public static let deliveryTimeout: TimeInterval = 5

    public private(set) var activePreset: ShortcutPreset?
    public private(set) var activeToken: HotKeyToken?
    public private(set) var pendingPreset: ShortcutPreset?
    public private(set) var pendingToken: HotKeyToken?
    public private(set) var registrationError: String?
    public var onToggle: (() -> Void)?
    public var onStateChange: (() -> Void)?

    public let registrar: any HotKeyRegistering
    public let store: any ShortcutStoring
    public let scheduler: any ShortcutScheduling
    private let timeout: TimeInterval
    private var timeoutToken: ShortcutScheduleToken?
    private var started = false

    public init(
        registrar: any HotKeyRegistering,
        store: any ShortcutStoring,
        scheduler: any ShortcutScheduling,
        timeout: TimeInterval = 5
    ) {
        self.registrar = registrar
        self.store = store
        self.scheduler = scheduler
        self.timeout = timeout
    }

    public var isEnabled: Bool {
        activeToken != nil
    }

    public func start() {
        guard !started else { return }
        started = true
        registrar.onEvent = { [weak self] token in
            self?.receive(token)
        }

        let stored = store.load()
        if let stored, registerImmediately(stored) {
            onStateChange?()
            return
        }

        if stored != ShortcutPreset.defaultPreset,
           registerImmediately(.defaultPreset) {
            registrationError = nil
            onStateChange?()
            return
        }

        registrationError = "No global shortcut could be registered."
        onStateChange?()
    }

    public func setShortcut(_ preset: ShortcutPreset) {
        if !started {
            start()
        }

        if activePreset == preset {
            cancelPending()
            registrationError = nil
            onStateChange?()
            return
        }

        if pendingPreset == preset {
            return
        }

        cancelPending()

        do {
            let token = try registrar.register(preset)
            pendingPreset = preset
            pendingToken = token
            timeoutToken = scheduler.schedule(after: timeout) { [weak self] in
                self?.candidateTimedOut(token: token)
            }
            registrationError = nil
            onStateChange?()
        } catch {
            registrationError =
                "Unable to register \(preset.displayName) for the five-second delivery window: "
                + String(describing: error)
            onStateChange?()
        }
    }

    public func stop() {
        cancelPending()
        if let activeToken {
            registrar.unregister(activeToken)
        }
        activeToken = nil
        activePreset = nil
        registrar.onEvent = nil
        onToggle = nil
        started = false
        onStateChange?()
    }

    private func registerImmediately(_ preset: ShortcutPreset) -> Bool {
        do {
            activeToken = try registrar.register(preset)
            activePreset = preset
            registrationError = nil
            return true
        } catch {
            return false
        }
    }

    private func receive(_ token: HotKeyToken) {
        if token == pendingToken, let candidate = pendingPreset {
            if let timeoutToken {
                scheduler.cancel(timeoutToken)
            }
            timeoutToken = nil
            pendingToken = nil
            pendingPreset = nil

            store.save(candidate)
            if let activeToken {
                registrar.unregister(activeToken)
            }
            activeToken = token
            activePreset = candidate
            registrationError = nil
            onToggle?()
            onStateChange?()
            return
        }

        guard token == activeToken else { return }
        onToggle?()
    }

    private func candidateTimedOut(token: HotKeyToken) {
        guard token == pendingToken, let candidate = pendingPreset else { return }
        pendingToken = nil
        pendingPreset = nil
        timeoutToken = nil
        registrar.unregister(token)
        registrationError = candidate.displayName + " was not delivered within five seconds."
        onStateChange?()
    }

    private func cancelPending() {
        if let timeoutToken {
            scheduler.cancel(timeoutToken)
        }
        timeoutToken = nil
        if let pendingToken {
            registrar.unregister(pendingToken)
        }
        pendingToken = nil
        pendingPreset = nil
    }
}
