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
    func refresh(session: PointerSession)
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

    @discardableResult
    public func show(on display: DisplayDescriptor) -> PaletteShowResult {
        guard isValid(display.visibleFrame) else {
            return .noDisplay
        }

        paletteViewController.loadViewIfNeeded()
        let size = paletteViewController.preferredSize
        let width = min(
            size.width,
            CGFloat(display.visibleFrame.width) - (Self.placementMargin * 2)
        )
        guard width.isFinite, width > 0, size.height.isFinite, size.height > 0 else {
            orderOut(nil)
            return .failed("Palette layout produced an invalid size")
        }
        paletteViewController.applyLayout(for: width)
        guard width >= Self.minimumNativeWidth,
              CGFloat(display.visibleFrame.height) >= size.height + (Self.placementMargin * 2)
        else {
            orderOut(nil)
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
        setFrameOrigin(NSPoint(x: placement.x, y: placement.y))
        orderFrontRegardless()

        guard isVisible else {
            orderOut(nil)
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
            orderOut(nil)
            return .failed("Palette placement produced an invalid frame")
        }
        return .shown(context)
    }

    public func hide() {
        orderOut(nil)
    }

    public override func close() {
        orderOut(nil)
        super.close()
    }

    private func isValid(_ frame: DisplayFrame) -> Bool {
        frame.x.isFinite && frame.y.isFinite
            && frame.width.isFinite && frame.width > 0
            && frame.height.isFinite && frame.height > 0
    }
}
