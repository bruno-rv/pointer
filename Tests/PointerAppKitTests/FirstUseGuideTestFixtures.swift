import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class FirstUseGuideTestStateStore: FirstUseGuideStateStoring {
    var hasDismissedFirstUseGuide: Bool
    private(set) var markCount = 0

    init(hasDismissedFirstUseGuide: Bool = false) {
        self.hasDismissedFirstUseGuide = hasDismissedFirstUseGuide
    }

    func markFirstUseGuideDismissed() {
        markCount += 1
        hasDismissedFirstUseGuide = true
    }
}

@MainActor
final class FirstUseGuideTestCatalog: GuideAssetCatalogProviding {
    let entries: [GuideAssetDescriptor]
    private(set) var imageRequests: [(String, GuideAssetVariant)] = []
    private(set) var providedImages: [(String, GuideAssetVariant, NSImage)] = []
    var imageError: Error?
    var failingVariants: Set<GuideAssetVariant> = []

    init(entries: [GuideAssetDescriptor]? = nil) {
        self.entries = entries ?? Self.defaultEntries
    }

    func image(for identifier: String, variant: GuideAssetVariant) throws -> NSImage {
        imageRequests.append((identifier, variant))
        if let imageError, failingVariants.isEmpty || failingVariants.contains(variant) {
            throw imageError
        }
        let image = NSImage(size: NSSize(width: 48, height: 48))
        providedImages.append((identifier, variant, image))
        return image
    }

    func resetImageRequests() {
        imageRequests.removeAll()
        providedImages.removeAll()
    }

    static let defaultEntries: [GuideAssetDescriptor] = [
        "arrow", "rectangle", "ellipse", "pen", "spotlight", "emoji", "select", "eraser"
    ].map { id in
        GuideAssetDescriptor(
            id: id,
            accessibleName: "\(id.capitalized) example",
            accessibleDescription: "\(id.capitalized) example description",
            isDecorative: false,
            variants: GuideAssetVariant.allCases.map { variant in
                GuideAssetVariantDescriptor(
                    variant: variant,
                    assetIdentifier: id,
                    sourceSHA256: String(repeating: "a", count: 64)
                )
            }
        )
    }
}

@MainActor
final class FirstUseGuideTestAppearanceProvider: GuideAppearanceProviding {
    var variant: GuideAssetVariant

    init(variant: GuideAssetVariant = .light) {
        self.variant = variant
    }
}

@MainActor
final class FirstUseGuideTestPanel: FirstUseGuidePanel, FirstUseGuideAssetPreparing {
    let expectedDisplay: DisplayDescriptor
    let viewController: FirstUseGuideViewController?
    private(set) var showContexts: [GuidePlacementContext] = []
    private(set) var events: [String] = []
    private var visibleCallback: (() -> Void)?
    var isVisible = false
    var becomesVisibleOnShow = true
    var invokesVisibleCallbackOnShow = true

    init(
        expectedDisplay: DisplayDescriptor,
        viewController: FirstUseGuideViewController? = nil
    ) {
        self.expectedDisplay = expectedDisplay
        self.viewController = viewController
    }

    func setResolvedImages(_ images: [String: NSImage], variant: GuideAssetVariant) {
        viewController?.setResolvedImages(images, variant: variant)
    }

    func show(in context: GuidePlacementContext, onVisible: @escaping () -> Void) {
        XCTAssertEqual(context.display, expectedDisplay)
        viewController?.loadViewIfNeeded()
        showContexts.append(context)
        events.append("show")
        visibleCallback = onVisible
        if becomesVisibleOnShow {
            isVisible = true
        }
        if invokesVisibleCallbackOnShow {
            triggerVisibleCallback()
        }
    }

    func close() {
        events.append("close")
        isVisible = false
        visibleCallback = nil
    }

    func triggerVisibleCallback() {
        guard let visibleCallback else { return }
        events.append("visible")
        visibleCallback()
    }
}

@MainActor
final class FirstUseGuideTestPlacementProvider: GuidePlacementProviding {
    private(set) var contexts: [GuidePlacementContext] = []

    func context(
        for display: DisplayDescriptor,
        paletteFrame: DisplayFrame
    ) -> GuidePlacementContext? {
        let context = GuidePlacementContext(
            display: display,
            visibleFrame: display.visibleFrame,
            paletteFrame: paletteFrame,
            avoidanceFrames: [paletteFrame]
        )
        contexts.append(context)
        return context
    }
}

@MainActor
final class FirstUseGuideTestFixture {
    static let defaultDisplay = DisplayDescriptor(
        uuid: DisplayUUID(rawValue: "guide-test-display"),
        frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
        visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
        scaleFactor: 2
    )

    private let suiteName: String
    let defaults: UserDefaults
    let stateStore: FirstUseGuideTestStateStore
    let placementProvider: FirstUseGuideTestPlacementProvider
    let catalog: FirstUseGuideTestCatalog
    let panel: FirstUseGuideTestPanel
    let controller: FirstUseGuideController
    let display: DisplayDescriptor
    let context: GuidePlacementContext
    let appearanceProvider: FirstUseGuideTestAppearanceProvider

    init(
        hasDismissedFirstUseGuide: Bool = false,
        appearanceVariant: GuideAssetVariant = .light
    ) {
        suiteName = "pointer.first-use-guide.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        stateStore = FirstUseGuideTestStateStore(
            hasDismissedFirstUseGuide: hasDismissedFirstUseGuide
        )
        placementProvider = FirstUseGuideTestPlacementProvider()
        catalog = FirstUseGuideTestCatalog()
        appearanceProvider = FirstUseGuideTestAppearanceProvider(variant: appearanceVariant)
        display = Self.defaultDisplay
        let paletteFrame = DisplayFrame(x: 1_300, y: 800, width: 420, height: 156)
        context = GuidePlacementContext(
            display: display,
            visibleFrame: display.visibleFrame,
            paletteFrame: paletteFrame,
            avoidanceFrames: [paletteFrame, DisplayFrame(x: 0, y: 24, width: 200, height: 200)]
        )
        let guideViewController = FirstUseGuideViewController(
            assetCatalog: catalog,
            appearanceProvider: appearanceProvider
        )
        let panel = FirstUseGuideTestPanel(
            expectedDisplay: display,
            viewController: guideViewController
        )
        self.panel = panel
        controller = FirstUseGuideController(
            stateStore: stateStore,
            placementProvider: placementProvider,
            assetCatalog: catalog,
            appearanceProvider: appearanceProvider,
            panelFactory: { _ in panel }
        )
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
