import AppKit
import Foundation
import PointerCore
import XCTest
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

@MainActor
final class IntegratedRealGuideLifecycleFixture {
    let notificationCenter: NotificationCenter
    let displayDescriptors: [DisplayDescriptor]
    let display: DisplayDescriptor
    let provider: DeterministicScreenProvider
    let coordinator: DisplayCoordinator
    let commandRouter: CommandRouter
    let palette: PalettePanel
    let menuBar: MenuBarController
    let guide: FirstUseGuideController
    let guideStateStore: GuideTestStateStore
    let appearanceProvider: FirstUseGuideTestAppearanceProvider
    let catalog: GuideAssetCatalog
    let registrar: GuideTestHotKeyRegistrar
    let shortcutStore: GuideTestShortcutStore
    let shortcutScheduler: GuideTestShortcutScheduler
    let shortcutController: HotKeyController
    let controller: PointerApplicationController

    private let bundleURL: URL

    var visibleGuidePanel: NSWindow? {
        NSApp.windows.reversed().first {
            $0.identifier?.rawValue == "pointer.first-use-guide" && $0.isVisible
        }
    }

    init(displayCount: Int = 1, firstUseGuideDismissed: Bool = false) throws {
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
        let (catalog, bundleURL) = try Self.makeTrackedGuideCatalog()
        let appearanceProvider = FirstUseGuideTestAppearanceProvider()
        let guide = FirstUseGuideController(
            stateStore: guideStateStore,
            placementProvider: placementProvider,
            assetCatalog: catalog,
            appearanceProvider: appearanceProvider
        )

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
        self.appearanceProvider = appearanceProvider
        self.catalog = catalog
        self.registrar = registrar
        self.shortcutStore = shortcutStore
        self.shortcutScheduler = shortcutScheduler
        self.shortcutController = shortcutController
        self.bundleURL = bundleURL
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

    func cleanup() {
        controller.stop()
        try? FileManager.default.removeItem(at: bundleURL)
    }

    private static func makeTrackedGuideCatalog() throws -> (GuideAssetCatalog, URL) {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = repositoryRoot.appendingPathComponent("Bundle/GuideAssetIdentity.json")
        let envelope = try JSONDecoder().decode(
            GuideAssetCatalogEnvelope.self,
            from: Data(contentsOf: manifestURL)
        )
        let sourceRoot = repositoryRoot.appendingPathComponent(
            "Bundle/Assets.xcassets/FirstUseGuide"
        )
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PointerGuideAssets-\(UUID().uuidString).bundle")

        do {
            try FileManager.default.createDirectory(
                at: bundleURL,
                withIntermediateDirectories: true
            )
            try Data(
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict></dict></plist>".utf8
            ).write(to: bundleURL.appendingPathComponent("Info.plist"))

            for entry in envelope.entries {
                for variant in entry.variants {
                    let sourcePath = GuideAssetSourceMapping.sourcePath(
                        for: variant.assetIdentifier,
                        variant: variant.variant
                    )
                    let sourceURL = try XCTUnwrap(
                        FileManager.default
                            .subpaths(atPath: sourceRoot.path)?
                            .map(sourceRoot.appendingPathComponent)
                            .first { $0.lastPathComponent == sourcePath }
                    )
                    try FileManager.default.copyItem(
                        at: sourceURL,
                        to: bundleURL.appendingPathComponent(sourcePath)
                    )
                }
            }

            let bundle = try XCTUnwrap(Bundle(url: bundleURL))
            let catalog = try GuideAssetCatalog(envelope: envelope, bundle: bundle)
            return (catalog, bundleURL)
        } catch {
            try? FileManager.default.removeItem(at: bundleURL)
            throw error
        }
    }

    func postScreenChange() {
        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
}
