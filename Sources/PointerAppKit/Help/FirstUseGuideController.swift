import AppKit
import PointerCore

@MainActor
internal protocol FirstUseGuidePanel: AnyObject {
    var isVisible: Bool { get }
    func show(in context: GuidePlacementContext, onVisible: @escaping () -> Void)
    func close()
}

@MainActor
public protocol GuideAppearanceProviding: AnyObject {
    var variant: GuideAssetVariant { get }
}

@MainActor
public final class SystemGuideAppearanceProvider: GuideAppearanceProviding {
    public init() {}

    public var variant: GuideAssetVariant {
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return .highContrast
        }
        let appearance = NSApp?.effectiveAppearance
            ?? NSAppearance.currentDrawing()
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark
            : .light
    }
}

@MainActor
internal protocol FirstUseGuideAssetPreparing: AnyObject {
    func setResolvedImages(_ images: [String: NSImage], variant: GuideAssetVariant)
}

internal enum FirstUseGuidePlacementPlan {
    static let margin = 16.0

    static func frame(
        size: DisplayFrame,
        in context: GuidePlacementContext
    ) -> DisplayFrame? {
        guard isValid(context.visibleFrame),
              isValid(context.paletteFrame),
              context.avoidanceFrames.allSatisfy(isValid),
              isValid(size),
              size.width <= context.visibleFrame.width,
              size.height <= context.visibleFrame.height else {
            return nil
        }

        let visible = context.visibleFrame
        let palette = context.paletteFrame
        let candidates = [
            DisplayFrame(
                x: palette.x + palette.width + margin,
                y: palette.y,
                width: size.width,
                height: size.height
            ),
            DisplayFrame(
                x: palette.x - size.width - margin,
                y: palette.y,
                width: size.width,
                height: size.height
            ),
            DisplayFrame(
                x: visible.x + (visible.width - size.width) / 2,
                y: visible.y + visible.height - size.height,
                width: size.width,
                height: size.height
            ),
            DisplayFrame(
                x: visible.x + (visible.width - size.width) / 2,
                y: visible.y,
                width: size.width,
                height: size.height
            ),
        ]
        let obstacles = [palette] + context.avoidanceFrames
        for candidate in candidates {
            let clamped = clamp(candidate, to: visible)
            if obstacles.allSatisfy({ !intersects(clamped, $0) }) {
                return clamped
            }
        }
        return nil
    }

    private static func clamp(_ frame: DisplayFrame, to bounds: DisplayFrame) -> DisplayFrame {
        let x = min(max(frame.x, bounds.x), bounds.x + bounds.width - frame.width)
        let y = min(max(frame.y, bounds.y), bounds.y + bounds.height - frame.height)
        return DisplayFrame(x: x, y: y, width: frame.width, height: frame.height)
    }

    private static func intersects(_ lhs: DisplayFrame, _ rhs: DisplayFrame) -> Bool {
        lhs.x < rhs.x + rhs.width && lhs.x + lhs.width > rhs.x
            && lhs.y < rhs.y + rhs.height && lhs.y + lhs.height > rhs.y
    }

    private static func isValid(_ frame: DisplayFrame) -> Bool {
        frame.x.isFinite && frame.y.isFinite
            && frame.width.isFinite && frame.width > 0
            && frame.height.isFinite && frame.height > 0
    }
}

@MainActor
public final class FirstUseGuideController: FirstUseGuidePresenting {
    public let placementProvider: any GuidePlacementProviding
    public let assetCatalog: any GuideAssetCatalogProviding
    public let appearanceProvider: any GuideAppearanceProviding

    private let stateStore: any FirstUseGuideStateStoring
    private let panelFactory: (GuidePlacementContext) -> any FirstUseGuidePanel
    private var panel: (any FirstUseGuidePanel)?
    private var pendingFirstUse = false
    private var pendingDisplayLossRestore = false

    public var isVisible: Bool {
        panel?.isVisible == true
    }

    public convenience init(
        stateStore: any FirstUseGuideStateStoring,
        placementProvider: any GuidePlacementProviding,
        assetCatalog: any GuideAssetCatalogProviding
    ) {
        let appearanceProvider = SystemGuideAppearanceProvider()
        self.init(
            stateStore: stateStore,
            placementProvider: placementProvider,
            assetCatalog: assetCatalog,
            appearanceProvider: appearanceProvider
        )
    }

    public convenience init(
        stateStore: any FirstUseGuideStateStoring,
        placementProvider: any GuidePlacementProviding,
        assetCatalog: any GuideAssetCatalogProviding,
        appearanceProvider: any GuideAppearanceProviding
    ) {
        self.init(
            stateStore: stateStore,
            placementProvider: placementProvider,
            assetCatalog: assetCatalog,
            appearanceProvider: appearanceProvider,
            panelFactory: { _ in
                FirstUseGuidePanelWindow(
                    assetCatalog: assetCatalog,
                    appearanceProvider: appearanceProvider
                )
            }
        )
    }

    internal init(
        stateStore: any FirstUseGuideStateStoring,
        placementProvider: any GuidePlacementProviding,
        assetCatalog: any GuideAssetCatalogProviding,
        appearanceProvider: any GuideAppearanceProviding,
        panelFactory: @escaping (GuidePlacementContext) -> any FirstUseGuidePanel
    ) {
        self.stateStore = stateStore
        self.placementProvider = placementProvider
        self.assetCatalog = assetCatalog
        self.appearanceProvider = appearanceProvider
        self.panelFactory = panelFactory
        pendingFirstUse = !stateStore.hasDismissedFirstUseGuide
    }

    @discardableResult
    public func showIfNeeded(in context: GuidePlacementContext) -> GuidePresentationResult {
        guard !stateStore.hasDismissedFirstUseGuide else {
            pendingFirstUse = false
            return .notNeeded
        }
        pendingFirstUse = true
        return present(in: context)
    }

    @discardableResult
    public func show(in context: GuidePlacementContext) -> GuidePresentationResult {
        pendingFirstUse = !stateStore.hasDismissedFirstUseGuide
        return present(in: context)
    }

    public func dismiss() {
        pendingFirstUse = false
        pendingDisplayLossRestore = false
        panel?.close()
        panel = nil
    }

    public func hideForDisplayLoss() {
        let hadIntent = isVisible || pendingFirstUse || pendingDisplayLossRestore
        if hadIntent {
            pendingDisplayLossRestore = true
        }
        panel?.close()
        panel = nil
    }

    @discardableResult
    public func restoreAfterDisplayLoss(in context: GuidePlacementContext) -> GuidePresentationResult {
        guard pendingDisplayLossRestore else { return .notNeeded }
        let result = present(in: context)
        if result == .shown || result == .notNeeded {
            pendingDisplayLossRestore = false
            pendingFirstUse = false
        }
        return result
    }

    public func hideForApplicationStop() {
        pendingFirstUse = false
        pendingDisplayLossRestore = false
        panel?.close()
        panel = nil
    }

    public func consumeEscape() -> Bool {
        guard isVisible else { return false }
        dismiss()
        return true
    }

    private func present(in context: GuidePlacementContext) -> GuidePresentationResult {
        guard isValid(context.visibleFrame),
              isValid(context.paletteFrame),
              context.avoidanceFrames.allSatisfy(isValid) else {
            return .failed("Guide placement context is invalid")
        }
        do {
            try GuideAssetCatalog.validateRequiredEntries(assetCatalog.entries)
        } catch {
            return .failed(error.localizedDescription)
        }

        let selectedVariant = appearanceProvider.variant
        var resolvedImages: [String: NSImage] = [:]
        do {
            for example in FirstUseGuideViewController.examples {
                resolvedImages[example.assetIdentifier] = try assetCatalog.image(
                    for: example.assetIdentifier,
                    variant: selectedVariant
                )
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        let guidePanel = panel ?? panelFactory(context)
        panel = guidePanel
        (guidePanel as? FirstUseGuideAssetPreparing)?.setResolvedImages(
            resolvedImages,
            variant: selectedVariant
        )
        var becameVisible = false
        guidePanel.show(in: context) { [weak self] in
            guard let self,
                  self.panel?.isVisible == true else { return }
            becameVisible = true
            if !self.stateStore.hasDismissedFirstUseGuide {
                self.stateStore.markFirstUseGuideDismissed()
            }
            self.pendingFirstUse = false
            self.pendingDisplayLossRestore = false
        }

        guard becameVisible, guidePanel.isVisible else {
            guidePanel.close()
            panel = nil
            return .failed("Guide window did not become visible")
        }
        return .shown
    }

    private func isValid(_ frame: DisplayFrame) -> Bool {
        frame.x.isFinite && frame.y.isFinite
            && frame.width.isFinite && frame.width > 0
            && frame.height.isFinite && frame.height > 0
    }

}

@MainActor
private final class FirstUseGuidePanelWindow: NSPanel, FirstUseGuidePanel, FirstUseGuideAssetPreparing {
    private let guideViewController: FirstUseGuideViewController

    init(
        assetCatalog: any GuideAssetCatalogProviding,
        appearanceProvider: any GuideAppearanceProviding
    ) {
        guideViewController = FirstUseGuideViewController(
            assetCatalog: assetCatalog,
            appearanceProvider: appearanceProvider
        )
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        title = "Learn Pointer"
        isFloatingPanel = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        contentViewController = guideViewController
        setAccessibilityElement(true)
        setAccessibilityLabel("Learn Pointer")
        setAccessibilityHelp("Learn Pointer annotation tools and shortcuts")
        identifier = NSUserInterfaceItemIdentifier("pointer.first-use-guide")
        guideViewController.onDismiss = { [weak self] in
            self?.close()
        }
    }

    func setResolvedImages(_ images: [String: NSImage], variant: GuideAssetVariant) {
        guideViewController.setResolvedImages(images, variant: variant)
    }

    func show(in context: GuidePlacementContext, onVisible: @escaping () -> Void) {
        guideViewController.loadViewIfNeeded()
        initialFirstResponder = guideViewController.doneButton
        let size = preferredPanelSize(in: context.visibleFrame)
        setContentSize(size)
        let sizeFrame = DisplayFrame(x: 0, y: 0, width: size.width, height: size.height)
        guard let placement = FirstUseGuidePlacementPlan.frame(size: sizeFrame, in: context) else {
            close()
            return
        }
        setFrame(placement.cgRect, display: true)
        orderFrontRegardless()
        guard isVisible else { return }
        guideViewController.startAppearanceObservation()
        onVisible()
    }

    override func close() {
        guideViewController.stopAppearanceObservation()
        orderOut(nil)
    }

    private func preferredPanelSize(in visibleFrame: DisplayFrame) -> NSSize {
        let preferred = guideViewController.view.fittingSize
        let width = preferred.width.isFinite && preferred.width > 0 ? preferred.width : 440
        let height = preferred.height.isFinite && preferred.height > 0 ? preferred.height : 560
        return NSSize(
            width: min(CGFloat(visibleFrame.width), width),
            height: min(CGFloat(visibleFrame.height), height)
        )
    }

}
