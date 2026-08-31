import AppKit
import PointerCore

public enum PaletteShowResult: Equatable, Sendable {
    case noDisplay
    case failed(String)
    case shown(GuidePlacementContext)
}

@MainActor
public protocol PalettePresenting: AnyObject {
    var window: NSWindow { get }
    var guidePlacementProvider: any GuidePlacementProviding { get }
    var appearanceObserverCount: Int { get }
    func refresh(session: PointerSession)
    func startAppearanceObservation()
    func stopAppearanceObservation()
    @discardableResult
    func show(on display: DisplayDescriptor) -> PaletteShowResult
    func hide()
}

@MainActor
public final class PalettePanel: NSPanel, PalettePresenting {
    private static let placementMargin: CGFloat = 16
    private static let minimumNativeWidth = CGFloat(
        PaletteLayout.minimumSupportedWidth
    )

    public let paletteViewController: PaletteViewController
    public let guidePlacementProvider: any GuidePlacementProviding

    public var window: NSWindow { self }
    public var appearanceObserverCount: Int {
        paletteViewController.appearanceObserverCount
    }

    public init(
        router: CommandRouter,
        guidePlacementProvider: any GuidePlacementProviding
    ) {
        self.guidePlacementProvider = guidePlacementProvider
        paletteViewController = PaletteViewController(router: router)
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PaletteLayout.minimumAllToolsWidth,
                height: 156
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        contentViewController = paletteViewController
        setAccessibilityElement(true)
        setAccessibilityLabel("Pointer annotation palette")
        setAccessibilityHelp("Choose tools, styles, and pointer display commands")
        identifier = NSUserInterfaceItemIdentifier("pointer.palette")
    }

    public func refresh(session: PointerSession) {
        paletteViewController.refresh(session: session)
    }

    public func startAppearanceObservation() {
        paletteViewController.startAppearanceObservation()
    }

    public func stopAppearanceObservation() {
        paletteViewController.stopAppearanceObservation()
    }

    @discardableResult
    public func show(on display: DisplayDescriptor) -> PaletteShowResult {
        guard isValid(display.visibleFrame) else {
            hide()
            return .noDisplay
        }

        paletteViewController.loadViewIfNeeded()
        let size = paletteViewController.preferredSize
        let width = min(
            size.width,
            CGFloat(display.visibleFrame.width) - (Self.placementMargin * 2)
        )
        guard width.isFinite, width > 0, size.height.isFinite, size.height > 0 else {
            hide()
            return .failed("Palette layout produced an invalid size")
        }
        paletteViewController.applyLayout(for: width)
        guard width >= Self.minimumNativeWidth,
              CGFloat(display.visibleFrame.height) >= size.height + (Self.placementMargin * 2)
        else {
            hide()
            return .failed("Palette display is too small for native layout")
        }
        contentMinSize = NSSize(width: Self.minimumNativeWidth, height: size.height)
        setContentSize(NSSize(width: width, height: size.height))
        paletteViewController.view.layoutSubtreeIfNeeded()
        if frame.width > width {
            setContentSize(NSSize(width: width, height: size.height))
        }
        let placement = PalettePlacement.nearTopCenter(
            paletteSize: DenormalizedSize(width: width, height: size.height),
            in: DenormalizedRect(
                x: display.visibleFrame.x,
                y: display.visibleFrame.y,
                width: display.visibleFrame.width,
                height: display.visibleFrame.height
            )
        )
        if paletteViewController.appearanceObserverCount == 0 {
            paletteViewController.startAppearanceObservation()
        }
        setFrameOrigin(NSPoint(x: placement.x, y: placement.y))
        orderFrontRegardless()

        guard Self.isFinalLayoutContained(
            frame: frame,
            contentFrame: contentView?.frame,
            requestedSize: NSSize(width: width, height: size.height),
            visibleFrame: display.visibleFrame,
            margin: Self.placementMargin
        ) else {
            hide()
            return .failed("Palette layout exceeded the requested display bounds; try a wider display")
        }

        guard isVisible else {
            hide()
            return .failed("Palette window did not become visible")
        }
        let paletteFrame = DisplayFrame(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
        guard let context = guidePlacementProvider.context(
            for: display,
            paletteFrame: paletteFrame
        ) else {
            hide()
            return .failed("Palette placement produced an invalid frame")
        }
        return .shown(context)
    }

    public func hide() {
        orderOut(nil)
        stopAppearanceObservation()
    }

    public override func close() {
        hide()
        super.close()
    }

    private func isValid(_ frame: DisplayFrame) -> Bool {
        frame.x.isFinite && frame.y.isFinite
            && frame.width.isFinite && frame.width > 0
            && frame.height.isFinite && frame.height > 0
    }

    static func isFinalLayoutContained(
        frame: NSRect,
        contentFrame: NSRect?,
        requestedSize: NSSize,
        visibleFrame: DisplayFrame,
        margin: CGFloat
    ) -> Bool {
        let tolerance: CGFloat = 0.5
        guard requestedSize.width.isFinite, requestedSize.width > 0,
              requestedSize.height.isFinite, requestedSize.height > 0,
              margin.isFinite, margin >= 0,
              isFinite(frame),
              frame.width <= requestedSize.width + tolerance,
              frame.height <= requestedSize.height + tolerance,
              frame.minX >= CGFloat(visibleFrame.x) + margin - tolerance,
              frame.maxX <= CGFloat(visibleFrame.x + visibleFrame.width)
                  - margin + tolerance,
              frame.minY >= CGFloat(visibleFrame.y) + margin - tolerance,
              frame.maxY <= CGFloat(visibleFrame.y + visibleFrame.height)
                  - margin + tolerance,
              let contentFrame,
              isFinite(contentFrame),
              contentFrame.minX >= -tolerance,
              contentFrame.minY >= -tolerance,
              contentFrame.maxX <= requestedSize.width + tolerance,
              contentFrame.maxY <= requestedSize.height + tolerance
        else {
            return false
        }
        return true
    }

    private static func isFinite(_ rect: NSRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.width > 0
            && rect.height.isFinite && rect.height > 0
    }
}
