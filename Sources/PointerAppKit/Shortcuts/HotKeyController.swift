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

    private let registrar: any HotKeyRegistering
    private let store: any ShortcutStoring
    private let scheduler: any ShortcutScheduling
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
        registrar.onEvent = { [weak self] token in
            self?.receive(token)
        }
    }

    public convenience init(
        registrar: any HotKeyRegistering,
        store: any ShortcutStoring
    ) {
        self.init(
            registrar: registrar,
            store: store,
            scheduler: DispatchShortcutScheduler()
        )
    }

    public var isEnabled: Bool {
        activeToken != nil
    }

    public func start() {
        guard !started else { return }
        started = true

        let stored = store.load()
        if let stored, registerImmediately(stored) {
            return
        }

        if stored != ShortcutPreset.defaultPreset,
           registerImmediately(.defaultPreset) {
            registrationError = nil
            return
        }

        registrationError = "No global shortcut could be registered."
    }

    public func setShortcut(_ preset: ShortcutPreset) {
        if !started {
            start()
        }

        if activePreset == preset {
            cancelPending()
            registrationError = nil
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
        } catch {
            registrationError = "Unable to register " + preset.displayName + ": " + String(describing: error)
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
        started = false
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
