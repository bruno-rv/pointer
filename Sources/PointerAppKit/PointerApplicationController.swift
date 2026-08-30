import AppKit
import PointerCore

/// A snapshot of active resources owned by a started application controller.
///
/// Counts describe bounded lifecycle resources that `stop()` must release:
/// visible windows and guides, status items, notification observers, bound
/// lifecycle callbacks, scheduled timer actions, and active overlays. They
/// intentionally exclude permanent object-lifetime wiring such as the
/// palette's feedback closure and the coordinator's session-update closure.
public struct PointerResourceCheckpoint: Equatable, Sendable {
    public let paletteCount: Int
    public let menuCount: Int
    public let screenObserverCount: Int
    public let appearanceObserverCount: Int
    public let shortcutWiringCount: Int
    public let overlayCount: Int
    public let callbackCount: Int
    public let timerCount: Int
    public let guideCount: Int

    public init(
        paletteCount: Int,
        menuCount: Int,
        screenObserverCount: Int,
        appearanceObserverCount: Int,
        shortcutWiringCount: Int,
        overlayCount: Int,
        callbackCount: Int,
        timerCount: Int,
        guideCount: Int
    ) {
        self.paletteCount = paletteCount
        self.menuCount = menuCount
        self.screenObserverCount = screenObserverCount
        self.appearanceObserverCount = appearanceObserverCount
        self.shortcutWiringCount = shortcutWiringCount
        self.overlayCount = overlayCount
        self.callbackCount = callbackCount
        self.timerCount = timerCount
        self.guideCount = guideCount
    }
}

@MainActor
public final class PointerApplicationController: NSObject, NSApplicationDelegate {
    public let screenProvider: any ScreenProviding
    public let displayCoordinator: DisplayCoordinator
    public let commandRouter: CommandRouter
    public let palette: any PalettePresenting
    public let menuBar: (any MenuBarPresenting)?
    public let shortcutController: HotKeyController
    public let shortcutStore: any ShortcutStoring
    public let hotKeyRegistrar: any HotKeyRegistering
    public let shortcutScheduler: any ShortcutScheduling
    public let guide: any FirstUseGuidePresenting
    public let guideStateStore: any FirstUseGuideStateStoring
    public let controlMetadataProvider: any ControlMetadataProviding
    public let guidePlacementProvider: any GuidePlacementProviding
    public let notificationCenter: NotificationCenter
    public private(set) var lastDisplayStopResult: DisplayStopResult?
    public private(set) var lifecycleErrorMessage: String?

    public var resourceCheckpoint: PointerResourceCheckpoint {
        let commandCallbackCount = [
            commandRouter.onStateChange != nil,
            commandRouter.onAnnotationEntry != nil,
        ].filter { $0 }.count
        let displayCallbackCount = displayCoordinator.onDisplaySync == nil ? 0 : 1
        return PointerResourceCheckpoint(
            paletteCount: palette.window.isVisible ? 1 : 0,
            menuCount: menuBar?.menuResourceCount ?? 0,
            screenObserverCount: screenParametersObserver == nil ? 0 : 1,
            appearanceObserverCount: palette.appearanceObserverCount,
            shortcutWiringCount: shortcutController.registrar.onEvent != nil
                && shortcutController.onToggle != nil ? 1 : 0,
            overlayCount: displayCoordinator.overlays.count,
            callbackCount: commandCallbackCount
                + (menuBar?.callbackBindingCount ?? 0)
                + displayCallbackCount
                + (shortcutController.onStateChange == nil ? 0 : 1),
            timerCount: shortcutController.scheduler.activeTimerCount,
            guideCount: guide.isVisible ? 1 : 0
        )
    }

    private var started = false
    private var pendingInitialPalettePresentation = false
    private var pendingFirstUseAttempt = false
    private var pendingPaletteRestore = false
    private var pendingDisplayLossRestore = false
    private var paletteEverPresented = false
    private var lastPaletteContext: GuidePlacementContext?
    private var screenParametersObserver: NSObjectProtocol?

    public init(
        screenProvider: any ScreenProviding,
        displayCoordinator: DisplayCoordinator,
        commandRouter: CommandRouter,
        palette: any PalettePresenting,
        menuBar: (any MenuBarPresenting)?,
        shortcutController: HotKeyController,
        guide: any FirstUseGuidePresenting,
        guideStateStore: any FirstUseGuideStateStoring,
        controlMetadataProvider: any ControlMetadataProviding,
        guidePlacementProvider: any GuidePlacementProviding,
        notificationCenter: NotificationCenter
    ) {
        self.screenProvider = screenProvider
        self.displayCoordinator = displayCoordinator
        self.commandRouter = commandRouter
        self.palette = palette
        self.menuBar = menuBar
        self.shortcutController = shortcutController
        self.shortcutStore = shortcutController.store
        self.hotKeyRegistrar = shortcutController.registrar
        self.shortcutScheduler = shortcutController.scheduler
        self.guide = guide
        self.guideStateStore = guideStateStore
        self.controlMetadataProvider = controlMetadataProvider
        self.guidePlacementProvider = guidePlacementProvider
        self.notificationCenter = notificationCenter
        precondition(
            palette.guidePlacementProvider === guidePlacementProvider,
            "Palette and controller must share the injected guide placement provider"
        )
        precondition(
            guide.placementProvider === guidePlacementProvider,
            "Guide and controller must share the injected guide placement provider"
        )
        super.init()
    }

    public func start() {
        guard !started else { return }
        started = true
        pendingInitialPalettePresentation = true
        pendingFirstUseAttempt = !guideStateStore.hasDismissedFirstUseGuide
        pendingPaletteRestore = false
        pendingDisplayLossRestore = false
        paletteEverPresented = false
        lastPaletteContext = nil

        palette.startAppearanceObservation()

        commandRouter.bindCallbacks(
            onStateChange: { [weak self] session in
                self?.refresh(session: session)
            },
            onClearAllRequested: nil,
            onAnnotationEntry: { [weak self] in
                self?.guide.dismiss()
            }
        )

        menuBar?.install()
        menuBar?.bindCallbacks(
            onShowPalette: { [weak self] in
                self?.showPalette()
            },
            onLearnPointer: { [weak self] in
                self?.showGuide()
            }
        )

        shortcutController.onToggle = { [weak self] in
            self?.commandRouter.route(.toggleMode)
        }
        shortcutController.onStateChange = { [weak self] in
            guard let self else { return }
            self.commandRouter.onStateChange?(self.commandRouter.session)
        }
        shortcutController.start()

        screenParametersObserver = notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.displayCoordinator.synchronize()
            }
        }

        displayCoordinator.onDisplaySync = { [weak self] result in
            self?.consumeDisplaySync(result)
        }
        displayCoordinator.synchronize()
    }

    public func stop() {
        guard started else { return }
        started = false

        if let screenParametersObserver {
            notificationCenter.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
        displayCoordinator.onDisplaySync = nil
        commandRouter.clearCallbacks()
        menuBar?.clearCallbacks()
        palette.stopAppearanceObservation()
        shortcutController.onToggle = nil
        shortcutController.onStateChange = nil
        shortcutController.stop()
        let stopResult = displayCoordinator.stop()
        lastDisplayStopResult = stopResult
        if stopResult.remainingOverlayCount == 0,
           stopResult.boundHandlerCount == 0 {
            lifecycleErrorMessage = nil
        } else {
            lifecycleErrorMessage =
                "Display stop cleanup incomplete: remainingOverlayCount=\(stopResult.remainingOverlayCount), boundHandlerCount=\(stopResult.boundHandlerCount)"
        }
        palette.hide()
        guide.hideForApplicationStop()
        menuBar?.remove()
        pendingInitialPalettePresentation = false
        pendingPaletteRestore = false
        lastPaletteContext = nil
        pendingFirstUseAttempt = false
        pendingDisplayLossRestore = false
    }

    public func refresh() {
        refresh(session: displayCoordinator.session)
    }

    public func showPalette() {
        guard let display = currentPointerDisplay() else {
            palette.hide()
            return
        }
        guard case let .shown(context) = palette.show(on: display) else { return }
        paletteEverPresented = true
        pendingInitialPalettePresentation = false
        pendingPaletteRestore = false
        lastPaletteContext = context
        consumePendingGuide(in: context)
    }

    @discardableResult
    public func showGuide() -> GuidePresentationResult? {
        guard let display = currentPointerDisplay() else { return nil }
        guard case let .shown(context) = palette.show(on: display) else { return nil }
        paletteEverPresented = true
        pendingInitialPalettePresentation = false
        pendingPaletteRestore = false
        lastPaletteContext = context
        return guide.show(in: context)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stop()
        return .terminateNow
    }

    private func consumeDisplaySync(_ result: DisplaySyncResult) {
        commandRouter.updateDisplayState(result)
        refresh()

        guard result.hasConnectedDisplays else {
            if result.enteredZeroDisplayState {
                let shouldRestorePalette = palette.window.isVisible
                    || (pendingInitialPalettePresentation && !paletteEverPresented)
                pendingPaletteRestore = shouldRestorePalette
                if guide.isVisible {
                    pendingDisplayLossRestore = shouldRestorePalette
                    pendingFirstUseAttempt = false
                    guide.hideForDisplayLoss()
                } else if pendingFirstUseAttempt,
                          !guideStateStore.hasDismissedFirstUseGuide {
                    pendingDisplayLossRestore = shouldRestorePalette
                    pendingFirstUseAttempt = false
                    guide.hideForDisplayLoss()
                } else if guideStateStore.hasDismissedFirstUseGuide {
                    pendingFirstUseAttempt = false
                }
            } else if pendingInitialPalettePresentation && !paletteEverPresented {
                pendingPaletteRestore = true
            } else if guideStateStore.hasDismissedFirstUseGuide {
                pendingFirstUseAttempt = false
            }
            palette.hide()
            return
        }

        if guideStateStore.hasDismissedFirstUseGuide {
            pendingFirstUseAttempt = false
        }

        guard let display = display(for: result.pointerDisplay) else {
            palette.hide()
            return
        }

        if pendingInitialPalettePresentation || pendingPaletteRestore {
            guard case let .shown(context) = palette.show(on: display) else { return }
            paletteEverPresented = true
            pendingInitialPalettePresentation = false
            pendingPaletteRestore = false
            lastPaletteContext = context
            consumePendingGuide(in: context)
            return
        }

        if pendingDisplayLossRestore {
            guard palette.window.isVisible, let context = lastPaletteContext else {
                pendingDisplayLossRestore = false
                return
            }
            consumePendingGuide(in: context)
            return
        }

        if pendingFirstUseAttempt {
            guard palette.window.isVisible, let context = lastPaletteContext else { return }
            consumePendingGuide(in: context)
        }
    }

    private func consumePendingGuide(in context: GuidePlacementContext) {
        if pendingDisplayLossRestore {
            let result = guide.restoreAfterDisplayLoss(in: context)
            if guideResultConsumed(result) {
                pendingDisplayLossRestore = false
            }
            return
        }

        guard pendingFirstUseAttempt else { return }
        let result = guide.showIfNeeded(in: context)
        if guideResultConsumed(result) {
            pendingFirstUseAttempt = false
        }
    }

    private func guideResultConsumed(_ result: GuidePresentationResult) -> Bool {
        switch result {
        case .notNeeded:
            return true
        case .shown:
            return guide.isVisible
        case .failed:
            return false
        }
    }

    private func currentPointerDisplay() -> DisplayDescriptor? {
        let displays = screenProvider.currentDisplays()
        guard !displays.isEmpty else { return nil }
        if let pointer = screenProvider.pointerDisplay(),
           let display = displays.first(where: { $0.uuid == pointer }) {
            return display
        }
        return displays[0]
    }

    private func display(for uuid: DisplayUUID?) -> DisplayDescriptor? {
        guard let uuid else { return nil }
        return screenProvider.currentDisplays().first { $0.uuid == uuid }
    }

    private func refresh(session: PointerSession) {
        palette.refresh(session: session)
        menuBar?.refresh(session: session)
    }
}
