import AppKit
import PointerCore

@MainActor
internal protocol FirstUseGuidePanel: AnyObject {
    var isVisible: Bool { get }
    func show(in context: GuidePlacementContext, onVisible: @escaping () -> Void)
    func close()
}

@MainActor
public final class FirstUseGuideController: FirstUseGuidePresenting {
    public let placementProvider: any GuidePlacementProviding
    public let assetCatalog: any GuideAssetCatalogProviding

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
        self.init(
            stateStore: stateStore,
            placementProvider: placementProvider,
            assetCatalog: assetCatalog,
            panelFactory: { _ in
                FirstUseGuidePanelWindow(assetCatalog: assetCatalog)
            }
        )
    }

    internal init(
        stateStore: any FirstUseGuideStateStoring,
        placementProvider: any GuidePlacementProviding,
        assetCatalog: any GuideAssetCatalogProviding,
        panelFactory: @escaping (GuidePlacementContext) -> any FirstUseGuidePanel
    ) {
        self.stateStore = stateStore
        self.placementProvider = placementProvider
        self.assetCatalog = assetCatalog
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
            for example in FirstUseGuideViewController.examples {
                _ = try assetCatalog.image(for: example.assetIdentifier, variant: .light)
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        let guidePanel = panel ?? panelFactory(context)
        panel = guidePanel
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
private final class FirstUseGuidePanelWindow: NSPanel, FirstUseGuidePanel {
    private let guideViewController: FirstUseGuideViewController

    init(assetCatalog: any GuideAssetCatalogProviding) {
        guideViewController = FirstUseGuideViewController(assetCatalog: assetCatalog)
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
            self?.orderOut(nil)
        }
    }

    func show(in context: GuidePlacementContext, onVisible: @escaping () -> Void) {
        guideViewController.loadViewIfNeeded()
        let size = preferredPanelSize(in: context.visibleFrame)
        setContentSize(size)
        let frame = placement(for: size, in: context)
        setFrame(frame, display: true)
        orderFrontRegardless()
        guard isVisible else { return }
        onVisible()
    }

    override func close() {
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

    private func placement(
        for size: NSSize,
        in context: GuidePlacementContext
    ) -> NSRect {
        let visible = context.visibleFrame.cgRect
        let palette = context.paletteFrame.cgRect
        let candidates = [
            NSRect(
                x: palette.maxX + 16,
                y: palette.minY,
                width: size.width,
                height: size.height
            ),
            NSRect(
                x: palette.minX - size.width - 16,
                y: palette.minY,
                width: size.width,
                height: size.height
            ),
            NSRect(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height,
                width: size.width,
                height: size.height
            ),
            NSRect(
                x: visible.midX - size.width / 2,
                y: visible.minY,
                width: size.width,
                height: size.height
            ),
        ]
        let avoidance = context.avoidanceFrames.map(\.cgRect)
        for candidate in candidates {
            let clamped = clamp(candidate, to: visible)
            if avoidance.allSatisfy({ !$0.intersects(clamped) }) {
                return clamped
            }
        }
        return clamp(candidates[0], to: visible)
    }

    private func clamp(_ rect: NSRect, to bounds: NSRect) -> NSRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
