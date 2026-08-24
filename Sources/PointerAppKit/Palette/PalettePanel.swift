import AppKit
import PointerCore

public struct GuidePlacementContext: Equatable, Sendable {
    public let display: DisplayDescriptor
    public let visibleFrame: DisplayFrame
    public let paletteFrame: DisplayFrame
    public let avoidanceFrames: [DisplayFrame]

    public init(
        display: DisplayDescriptor,
        visibleFrame: DisplayFrame,
        paletteFrame: DisplayFrame,
        avoidanceFrames: [DisplayFrame]
    ) {
        self.display = display
        self.visibleFrame = visibleFrame
        self.paletteFrame = paletteFrame
        self.avoidanceFrames = avoidanceFrames
    }
}

@MainActor
public protocol GuidePlacementProviding: AnyObject {
    func context(
        for display: DisplayDescriptor,
        paletteFrame: DisplayFrame
    ) -> GuidePlacementContext?
}

@MainActor
public final class GuidePlacementProvider: GuidePlacementProviding {
    public init() {}

    public func context(
        for display: DisplayDescriptor,
        paletteFrame: DisplayFrame
    ) -> GuidePlacementContext? {
        guard isValid(display.visibleFrame),
              !display.uuid.rawValue.isEmpty,
              isValid(paletteFrame)
        else {
            return nil
        }

        return GuidePlacementContext(
            display: display,
            visibleFrame: display.visibleFrame,
            paletteFrame: paletteFrame,
            avoidanceFrames: [paletteFrame]
        )
    }

    private func isValid(_ frame: DisplayFrame) -> Bool {
        frame.x.isFinite && frame.y.isFinite
            && frame.width.isFinite && frame.width > 0
            && frame.height.isFinite && frame.height > 0
    }
}

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
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 156),
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

    @available(*, deprecated, message: "Inject one GuidePlacementProviding instance; remove this seam in C Task 3.")
    internal convenience init(router: CommandRouter) {
        self.init(router: router, guidePlacementProvider: GuidePlacementProvider())
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
        let width = max(1, min(size.width, CGFloat(display.visibleFrame.width - 32)))
        guard width.isFinite, width > 0, size.height.isFinite, size.height > 0 else {
            return .failed("Palette layout produced an invalid size")
        }
        paletteViewController.applyLayout(for: width)
        contentMinSize = NSSize(width: 1, height: size.height)
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
