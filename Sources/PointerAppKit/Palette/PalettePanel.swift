import AppKit
import PointerCore

@MainActor
public protocol PalettePresenting: AnyObject {
    var window: NSWindow { get }
    func refresh(session: PointerSession)
    func show(on display: DisplayDescriptor)
    func hide()
}

@MainActor
public final class PalettePanel: NSPanel, PalettePresenting {
    public let paletteViewController: PaletteViewController

    public var window: NSWindow { self }

    public init(router: CommandRouter) {
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
        level = .floating
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

    public func show(on display: DisplayDescriptor) {
        let size = paletteViewController.preferredSize
        let width = max(1, min(size.width, CGFloat(display.visibleFrame.width - 32)))
        setContentSize(NSSize(width: width, height: size.height))
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
    }

    public func hide() {
        orderOut(nil)
    }

    public override func close() {
        orderOut(nil)
        super.close()
    }
}
