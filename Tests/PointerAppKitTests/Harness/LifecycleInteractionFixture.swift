import AppKit
import PointerCore
@testable import PointerAppKit

@MainActor
final class LifecycleInteractionFixture {
    let notificationCenter: NotificationCenter
    let displayDescriptors: [DisplayDescriptor]
    let display: DisplayDescriptor
    let provider: DeterministicScreenProvider
    let coordinator: DisplayCoordinator
    let commandRouter: CommandRouter
    let palette: PalettePanel
    let menuBar: MenuBarController
    let guide: GuideTestSpyGuide
    let guideStateStore: GuideTestStateStore
    let registrar: GuideTestHotKeyRegistrar
    let shortcutStore: GuideTestShortcutStore
    let shortcutScheduler: GuideTestShortcutScheduler
    let shortcutController: HotKeyController
    let clock: DeterministicClock
    let controller: PointerApplicationController
    let eventLog: GuideTestEventLog

    var events: [String] {
        get { eventLog.values }
        set { eventLog.values = newValue }
    }

    init(
        displayCount: Int,
        firstUseGuideDismissed: Bool = false,
        guideBecomesVisibleOnShow: Bool = true,
        guideShowIfNeededResult: GuidePresentationResult = .shown,
        guideRestoreAfterDisplayLossResult: GuidePresentationResult = .shown
    ) {
        precondition(displayCount == 1 || displayCount == 2)
        _ = NSApplication.shared

        let descriptors = displayCount == 1
            ? DisplayFixtures.oneDisplay()
            : DisplayFixtures.twoDisplays()
        let notificationCenter = NotificationCenter()
        let provider = DeterministicScreenProvider(
            displays: descriptors,
            pointerUUID: descriptors.first?.uuid
        )
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { descriptor in OverlayPanel(descriptor: descriptor) }
        )
        let registrar = GuideTestHotKeyRegistrar()
        let shortcutStore = GuideTestShortcutStore()
        let shortcutScheduler = GuideTestShortcutScheduler()
        let shortcutController = HotKeyController(
            registrar: registrar,
            store: shortcutStore,
            scheduler: shortcutScheduler
        )
        let router = CommandRouter(
            coordinator: coordinator,
            screenProvider: provider,
            shortcutController: shortcutController
        )
        let eventLog = GuideTestEventLog()
        let placementProvider = GuideTestPlacementProvider(eventLog: eventLog)
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: placementProvider
        )
        let menuBar = MenuBarController(
            router: router,
            shortcutController: shortcutController,
            terminate: {}
        )
        let guideStateStore = GuideTestStateStore()
        guideStateStore.hasDismissedFirstUseGuide = firstUseGuideDismissed
        let guide = GuideTestSpyGuide(
            placementProvider: placementProvider,
            eventLog: eventLog
        )
        guide.leavesVisibleAfterShownResult = guideBecomesVisibleOnShow
        guide.showIfNeededResult = guideShowIfNeededResult
        guide.restoreAfterDisplayLossResult = guideRestoreAfterDisplayLossResult
        guide.onVisible = { [guideStateStore] in
            guideStateStore.markFirstUseGuideDismissed()
        }

        self.notificationCenter = notificationCenter
        displayDescriptors = descriptors
        display = descriptors[0]
        self.provider = provider
        self.coordinator = coordinator
        commandRouter = router
        self.palette = palette
        self.menuBar = menuBar
        self.guide = guide
        self.guideStateStore = guideStateStore
        self.registrar = registrar
        self.shortcutStore = shortcutStore
        self.shortcutScheduler = shortcutScheduler
        self.shortcutController = shortcutController
        clock = DeterministicClock()
        self.eventLog = eventLog
        controller = PointerApplicationController(
            screenProvider: provider,
            displayCoordinator: coordinator,
            commandRouter: router,
            palette: palette,
            menuBar: menuBar,
            shortcutController: shortcutController,
            guide: guide,
            guideStateStore: guideStateStore,
            controlMetadataProvider: ControlMetadataInventory(
                palette: palette,
                menuBar: menuBar
            ),
            guidePlacementProvider: placementProvider,
            notificationCenter: notificationCenter
        )
    }

    func start() {
        controller.start()
    }

    func stop() {
        controller.stop()
    }

    func postScreenChange() {
        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
}
