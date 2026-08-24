import AppKit
import PointerCore

@MainActor
public final class PointerApplicationController: NSObject, NSApplicationDelegate {
    public let screenProvider: any ScreenProviding
    public let displayCoordinator: DisplayCoordinator
    public let commandRouter: CommandRouter
    public let palette: any PalettePresenting
    public let menuBar: (any MenuBarPresenting)?
    public let shortcutController: HotKeyController
    public let guide: any FirstUseGuidePresenting
    public let guideStateStore: any FirstUseGuideStateStoring
    public let controlMetadataProvider: any ControlMetadataProviding
    public let guidePlacementProvider: any GuidePlacementProviding
    public let notificationCenter: NotificationCenter
    public private(set) var lastDisplayStopResult: DisplayStopResult?
    public private(set) var lifecycleErrorMessage: String?

    private var started = false
    private var pendingFirstUseAttempt = false
    private var pendingDisplayLossRestore = false
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
        pendingFirstUseAttempt = !guideStateStore.hasDismissedFirstUseGuide
        pendingDisplayLossRestore = false

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
        shortcutController.onToggle = nil
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
        _ = palette.show(on: display)
    }

    public func showGuide() {
        guard let display = currentPointerDisplay() else { return }
        guard case let .shown(context) = palette.show(on: display) else { return }
        guide.show(in: context)
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
            if result.enteredZeroDisplayState, guide.isVisible {
                pendingDisplayLossRestore = true
                pendingFirstUseAttempt = false
                guide.hideForDisplayLoss()
            } else if result.enteredZeroDisplayState,
                      pendingFirstUseAttempt,
                      !guideStateStore.hasDismissedFirstUseGuide {
                pendingDisplayLossRestore = true
                pendingFirstUseAttempt = false
                guide.hideForDisplayLoss()
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
            pendingFirstUseAttempt = true
            return
        }

        if pendingDisplayLossRestore {
            switch palette.show(on: display) {
            case let .shown(context):
                guide.restoreAfterDisplayLoss(in: context)
                pendingFirstUseAttempt = false
                pendingDisplayLossRestore = false
            case .noDisplay, .failed:
                break
            }
            return
        }

        switch palette.show(on: display) {
        case let .shown(context):
            if pendingFirstUseAttempt {
                guide.showIfNeeded(in: context)
                pendingFirstUseAttempt = false
            }
        case .noDisplay, .failed:
            pendingFirstUseAttempt = !guideStateStore.hasDismissedFirstUseGuide
                && !guide.isVisible
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
