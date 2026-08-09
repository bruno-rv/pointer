import AppKit

private enum PlacementPolicy: Int, CaseIterable {
    case pointerOnShow
    case rememberDrag
    case mainDisplay

    static let labels = ["Pointer on show", "Remember drag", "Main display"]

    var description: String {
        switch self {
        case .pointerOnShow:
            return "Pointer on show (recommended)"
        case .rememberDrag:
            return "Remember last drag"
        case .mainDisplay:
            return "Main display only"
        }
    }
}

private struct DiagnosticMark {
    let normalizedPoint: NSPoint
}

@MainActor
private final class OverlayView: NSView {
    var displayName: String
    var marks: [DiagnosticMark] = [] {
        didSet { needsDisplay = true }
    }

    init(displayName: String) {
        self.displayName = displayName
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemTeal.withAlphaComponent(0.75).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 3, dy: 3))
        border.lineWidth = 6
        border.stroke()

        let label = "PROTOTYPE · Annotation available · \(displayName)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let labelSize = (label as NSString).size(withAttributes: attributes)
        let labelRect = NSRect(
            x: 18,
            y: bounds.maxY - labelSize.height - 34,
            width: labelSize.width + 24,
            height: labelSize.height + 14
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 8, yRadius: 8).fill()
        (label as NSString).draw(
            at: NSPoint(x: labelRect.minX + 12, y: labelRect.minY + 7),
            withAttributes: attributes
        )

        for mark in marks {
            let point = NSPoint(
                x: mark.normalizedPoint.x * bounds.width,
                y: mark.normalizedPoint.y * bounds.height
            )
            let outer = NSRect(x: point.x - 15, y: point.y - 15, width: 30, height: 30)
            NSColor.systemPink.withAlphaComponent(0.95).setStroke()
            let ring = NSBezierPath(ovalIn: outer)
            ring.lineWidth = 7
            ring.stroke()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct Overlay {
        let panel: NSPanel
        let view: OverlayView
    }

    private var overlays: [CGDirectDisplayID: Overlay] = [:]
    private var marksByDisplay: [CGDirectDisplayID: [DiagnosticMark]] = [:]
    private var palette: NSPanel?
    private var statusItem: NSStatusItem?
    private var policyControl: NSSegmentedControl?
    private var stateLabel: NSTextField?
    private var placementPolicy: PlacementPolicy = .pointerOnShow
    private var rememberedFrame: NSRect?
    private var isPositioningPalette = false
    private var lastAction = "Prototype launched"

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeStatusItem()
        reconcileOverlays()
        makePalette()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        if let palette {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(paletteDidMove),
                name: NSWindow.didMoveNotification,
                object: palette
            )
        }

        showPalette()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "cursorarrow.rays",
            accessibilityDescription: "Pointer prototype"
        )
        item.button?.toolTip = "Pointer Palette PROTOTYPE"

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Palette", action: #selector(showPaletteFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Add Test Mark at Pointer", action: #selector(addTestMark), keyEquivalent: "")
        menu.addItem(withTitle: "Clear Test Marks", action: #selector(clearMarks), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Prototype", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func makePalette() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 250),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Pointer Palette — PLACEMENT PROTOTYPE"
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]

        let badge = NSTextField(labelWithString: "PROTOTYPE · Palette placement")
        badge.font = .systemFont(ofSize: 12, weight: .bold)
        badge.textColor = .systemOrange

        let question = NSTextField(
            wrappingLabelWithString: "Where should the single draggable palette appear when it is shown again?"
        )
        question.font = .systemFont(ofSize: 16, weight: .semibold)

        let policy = NSSegmentedControl(
            labels: PlacementPolicy.labels,
            trackingMode: .selectOne,
            target: self,
            action: #selector(changePolicy(_:))
        )
        policy.selectedSegment = PlacementPolicy.pointerOnShow.rawValue
        policyControl = policy

        let showButton = NSButton(title: "🎯 Show at policy destination", target: self, action: #selector(showPaletteFromButton))
        let markButton = NSButton(title: "📍 Add mark at pointer", target: self, action: #selector(addTestMark))
        let clearButton = NSButton(title: "🧹 Clear marks", target: self, action: #selector(clearMarks))
        let hideButton = NSButton(title: "Hide palette", target: self, action: #selector(hidePalette))
        let buttons = NSStackView(views: [showButton, markButton, clearButton, hideButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let state = NSTextField(wrappingLabelWithString: "")
        state.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        state.textColor = .secondaryLabelColor
        stateLabel = state

        let stack = NSStackView(views: [badge, question, policy, buttons, state])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
            policy.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36)
        ])

        panel.contentView = root
        palette = panel
    }

    private func reconcileOverlays() {
        let screensByID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            displayID(for: screen).map { ($0, screen) }
        })

        for (displayID, overlay) in overlays where screensByID[displayID] == nil {
            overlay.panel.orderOut(nil)
            overlay.panel.close()
            overlays.removeValue(forKey: displayID)
        }

        for (displayID, screen) in screensByID {
            if let overlay = overlays[displayID] {
                overlay.panel.setFrame(screen.frame, display: true)
                overlay.view.displayName = screen.localizedName
                overlay.view.marks = marksByDisplay[displayID] ?? []
                overlay.panel.orderFrontRegardless()
            } else {
                let view = OverlayView(displayName: screen.localizedName)
                view.marks = marksByDisplay[displayID] ?? []
                let panel = NSPanel(
                    contentRect: screen.frame,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false,
                    screen: screen
                )
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                panel.ignoresMouseEvents = true
                panel.hidesOnDeactivate = false
                panel.level = .screenSaver
                panel.collectionBehavior = [
                    .canJoinAllSpaces,
                    .canJoinAllApplications,
                    .stationary,
                    .ignoresCycle,
                    .fullScreenAuxiliary
                ]
                panel.contentView = view
                panel.orderFrontRegardless()
                overlays[displayID] = Overlay(panel: panel, view: view)
            }
        }
        palette?.orderFrontRegardless()
        updateState()
    }

    private func showPalette() {
        guard let palette, let destination = destinationScreen() else { return }

        let targetFrame: NSRect
        if placementPolicy == .rememberDrag,
           let rememberedFrame,
           NSScreen.screens.contains(where: { $0.frame.intersects(rememberedFrame) }) {
            targetFrame = rememberedFrame
        } else {
            let visible = destination.visibleFrame
            targetFrame = NSRect(
                x: visible.midX - palette.frame.width / 2,
                y: visible.maxY - palette.frame.height - 22,
                width: palette.frame.width,
                height: palette.frame.height
            )
        }

        isPositioningPalette = true
        palette.setFrame(clamped(targetFrame, to: destination.visibleFrame), display: true)
        isPositioningPalette = false
        palette.orderFrontRegardless()
        rememberedFrame = palette.frame
        updateState()
    }

    private func destinationScreen() -> NSScreen? {
        switch placementPolicy {
        case .pointerOnShow:
            return screenContainingPointer() ?? NSScreen.main
        case .rememberDrag:
            if let rememberedFrame {
                return screen(containingMostOf: rememberedFrame) ?? screenContainingPointer() ?? NSScreen.main
            }
            return screenContainingPointer() ?? NSScreen.main
        case .mainDisplay:
            return NSScreen.screens.first
        }
    }

    private func screenContainingPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) })
    }

    private func screen(containingMostOf frame: NSRect) -> NSScreen? {
        NSScreen.screens.max {
            $0.frame.intersection(frame).area < $1.frame.intersection(frame).area
        }
    }

    private func clamped(_ frame: NSRect, to bounds: NSRect) -> NSRect {
        let x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
        let y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
        return NSRect(origin: NSPoint(x: x, y: y), size: frame.size)
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map {
            CGDirectDisplayID($0.uint32Value)
        }
    }

    private func displayDescription(_ screen: NSScreen?) -> String {
        guard let screen else { return "none" }
        let id = displayID(for: screen).map(String.init) ?? "unknown"
        return "\(screen.localizedName) [\(id)]"
    }

    private func updateState() {
        let pointerScreen = screenContainingPointer()
        let paletteScreen = palette.map { screen(containingMostOf: $0.frame) } ?? nil
        let totalMarks = marksByDisplay.values.reduce(0) { $0 + $1.count }
        stateLabel?.stringValue = """
        policy: \(placementPolicy.description)
        pointer display: \(displayDescription(pointerScreen))
        palette display: \(displayDescription(paletteScreen))
        connected overlays: \(overlays.count) · test marks: \(totalMarks)
        last: \(lastAction)
        """
    }

    @objc private func changePolicy(_ sender: NSSegmentedControl) {
        guard let policy = PlacementPolicy(rawValue: sender.selectedSegment) else { return }
        placementPolicy = policy
        lastAction = "Changed placement policy to \(policy.description)"
        showPalette()
    }

    @objc private func showPaletteFromMenu() {
        lastAction = "Reactivated from the menu-bar item"
        showPalette()
    }

    @objc private func showPaletteFromButton() {
        lastAction = "Repositioned using the active placement policy"
        showPalette()
    }

    @objc private func hidePalette() {
        rememberedFrame = palette?.frame
        palette?.orderOut(nil)
        lastAction = "Palette hidden; display overlays remain available"
        updateState()
    }

    @objc private func addTestMark() {
        let point = NSEvent.mouseLocation
        guard let screen = screenContainingPointer(), let displayID = displayID(for: screen) else { return }
        let normalized = NSPoint(
            x: (point.x - screen.frame.minX) / screen.frame.width,
            y: (point.y - screen.frame.minY) / screen.frame.height
        )
        marksByDisplay[displayID, default: []].append(DiagnosticMark(normalizedPoint: normalized))
        overlays[displayID]?.view.marks = marksByDisplay[displayID] ?? []
        lastAction = "Added a test mark to \(screen.localizedName) independently of palette placement"
        palette?.orderFrontRegardless()
        updateState()
    }

    @objc private func clearMarks() {
        marksByDisplay.removeAll()
        overlays.values.forEach { $0.view.marks = [] }
        lastAction = "Cleared test marks on every display"
        updateState()
    }

    @objc private func paletteDidMove() {
        guard !isPositioningPalette, let palette, palette.isVisible else { return }
        rememberedFrame = palette.frame
        lastAction = "Palette manually dragged to \(displayDescription(screen(containingMostOf: palette.frame)))"
        updateState()
    }

    @objc private func screenParametersChanged() {
        reconcileOverlays()
        if let palette,
           !NSScreen.screens.contains(where: { $0.frame.intersects(palette.frame) }) {
            rememberedFrame = nil
            lastAction = "Palette display disconnected; moved to the pointer display"
            showPalette()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension NSRect {
    var area: CGFloat { width * height }
}

@main
@MainActor
private enum PalettePlacementPrototype {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        _ = delegate
    }
}
