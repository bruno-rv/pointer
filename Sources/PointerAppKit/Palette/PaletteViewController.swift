import AppKit
import PointerCore

@MainActor
final class PaletteRootView: NSView {
    var onEffectiveAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }
}

private final class PaletteStyleScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 42)
    }
}

private final class PaletteActionStack: NSStackView {
    weak var contextualDelete: NSButton?

    override func layout() {
        super.layout()
        guard let contextualDelete, contextualDelete.isHidden else { return }
        contextualDelete.setFrameSize(.zero)
    }
}

private final class PaletteFocusableButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
}

private final class PaletteFocusablePopup: NSPopUpButton {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
}

private final class PaletteFocusableColorWell: NSColorWell {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
}

private final class PaletteFocusableSlider: NSSlider {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
}

@MainActor
public final class PaletteViewController: NSViewController {
    public struct DisplayOptions: Equatable, Sendable {
        public let reduceTransparency: Bool
        public let increaseContrast: Bool

        public init(reduceTransparency: Bool, increaseContrast: Bool) {
            self.reduceTransparency = reduceTransparency
            self.increaseContrast = increaseContrast
        }

        public static var current: DisplayOptions {
            DisplayOptions(
                reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            )
        }
    }

    public private(set) var controls: [NSControl] = []
    public private(set) var layoutPlan = PaletteLayout.plan(
        availableWidth: PaletteLayout.minimumAllToolsWidth
    )
    public private(set) var deleteButton: NSButton!
    public private(set) var appliedDisplayOptions = DisplayOptions.current
    public private(set) var displayOptionsRefreshCount = 0

    private let router: CommandRouter
    private var toolButtons: [PointerTool: NSButton] = [:]
    private var overflowButton: NSPopUpButton!
    private var emojiPicker: NSPopUpButton!
    private var modeButton: NSButton!
    private var colorWell: NSColorWell!
    private var strokeSlider: NSSlider!
    private var opacitySlider: NSSlider!
    private var radiusSlider: NSSlider!
    private var dimnessSlider: NSSlider!
    private var statusLabel: NSTextField!
    private var undoButton: NSButton!
    private var clearButton: NSButton!
    private var strokeValueLabel: NSTextField!
    private var opacityValueLabel: NSTextField!
    private var radiusValueLabel: NSTextField!
    private var dimnessValueLabel: NSTextField!
    private var visualEffectView: NSVisualEffectView!
    private var styleScrollView: NSScrollView!
    private var currentSession = PointerSession()
    private var configuredButtonTypes: [String: NSButton.ButtonType] = [:]
    private var pendingLayoutWidth: CGFloat?
    private var deleteHitTargetConstraints: [NSLayoutConstraint] = []
    private var renderedOverflowTools: [PointerTool] = []
    private var renderedOverflowActiveTool: PointerTool?
    private let displayOptionsProvider: @MainActor () -> DisplayOptions
    private var displayOptionsObserver: NSObjectProtocol?
    private var shortcutErrorWasDisplayed = false
    private var shortcutSuppressedFeedback: String?

    public init(
        router: CommandRouter,
        displayOptionsProvider: @escaping @MainActor () -> DisplayOptions = { .current }
    ) {
        self.router = router
        self.displayOptionsProvider = displayOptionsProvider
        super.init(nibName: nil, bundle: nil)
        let existingFeedback = router.onFeedback
        router.onFeedback = { [weak self] message in
            existingFeedback?(message)
            self?.showFeedback(message)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PaletteViewController does not support storyboards.")
    }

    public override func loadView() {
        let root = PaletteRootView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: PaletteLayout.minimumAllToolsWidth,
                height: 156
            )
        )
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.separatorColor.cgColor
        view = root

        visualEffectView = NSVisualEffectView(frame: root.bounds)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        root.addSubview(visualEffectView, positioned: .below, relativeTo: nil)
        root.onEffectiveAppearanceChange = { [weak self] in
            self?.applyDisplayOptions()
        }

        buildControls()
        layoutControls()
        refresh(session: currentSession)
        applyDisplayOptions()
    }

    private func installDisplayOptionsObserver() {
        guard displayOptionsObserver == nil else { return }
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.applyDisplayOptions()
            }
        }
    }

    deinit {
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
        }
    }

    public func refresh(session: PointerSession) {
        currentSession = session
        guard isViewLoaded else { return }

        modeButton.title = session.mode == .annotation ? "Annotation" : "Standby"
        modeButton.state = session.mode == .annotation ? .on : .off
        modeButton.setAccessibilityValue(session.mode == .annotation ? "On" : "Off")
        for (tool, button) in toolButtons {
            button.state = session.toolState.tool == tool ? .on : .off
            button.isEnabled = true
            button.setAccessibilityValue(session.toolState.tool == tool ? "Selected" : "Not selected")
        }
        let selectedMark = selectedMark(in: session)
        let style = compatibleStyle(for: selectedMark) ?? session.toolState.style
        colorWell.color = nsColor(from: style.color)
        colorWell.setAccessibilityValue(
            "RGBA \(style.color.red), \(style.color.green), \(style.color.blue)"
        )
        strokeSlider.doubleValue = style.strokeWidth
        opacitySlider.doubleValue = style.opacity
        let spotlight = spotlightValues(for: selectedMark)
        radiusSlider.doubleValue = spotlight?.radius ?? session.toolState.spotlightRadius
        dimnessSlider.doubleValue = spotlight?.dimness ?? session.toolState.spotlightDimness
        let emoji = emojiValue(for: selectedMark) ?? session.toolState.emoji
        emojiPicker.selectItem(withTitle: emoji)
        emojiPicker.setAccessibilityValue(emoji)
        strokeSlider.setAccessibilityValue(formattedStroke(style.strokeWidth))
        opacitySlider.setAccessibilityValue(formattedPercent(style.opacity))
        radiusSlider.setAccessibilityValue(formattedPercent(spotlight?.radius ?? session.toolState.spotlightRadius))
        dimnessSlider.setAccessibilityValue(formattedPercent(spotlight?.dimness ?? session.toolState.spotlightDimness))
        strokeValueLabel?.stringValue = formattedStroke(style.strokeWidth)
        opacityValueLabel?.stringValue = formattedPercent(style.opacity)
        radiusValueLabel?.stringValue = formattedPercent(spotlight?.radius ?? session.toolState.spotlightRadius)
        dimnessValueLabel?.stringValue = formattedPercent(spotlight?.dimness ?? session.toolState.spotlightDimness)
        updateContextualState(
            session: session,
            selectionGeometry: selectedGeometry(in: session)
        )
        let pointerDisplay = router.pointerDisplay
        undoButton.isEnabled = pointerDisplay.map(session.canUndo(on:)) ?? false
        clearButton.isEnabled = pointerDisplay.map {
            !session.canvas(for: $0).marks.isEmpty
        } ?? false
        undoButton.setAccessibilityValue(undoButton.isEnabled ? "Available" : "Unavailable")
        clearButton.setAccessibilityValue(clearButton.isEnabled ? "Available" : "Unavailable")
        if let error = router.shortcutError {
            shortcutErrorWasDisplayed = true
            if let feedback = router.feedbackMessage {
                shortcutSuppressedFeedback = feedback
            }
            statusLabel.stringValue = "Shortcut unavailable: \(error)"
        } else if let guidance = router.pendingShortcutGuidance {
            shortcutErrorWasDisplayed = false
            if let feedback = router.feedbackMessage {
                shortcutSuppressedFeedback = feedback
            } else {
                shortcutSuppressedFeedback = nil
            }
            statusLabel.stringValue = guidance
        } else if shortcutErrorWasDisplayed {
            shortcutErrorWasDisplayed = false
            statusLabel.stringValue = shouldSuppressCurrentFeedback()
                ? normalStatusMessage(for: session)
                : router.feedbackMessage ?? normalStatusMessage(for: session)
        } else if shouldSuppressCurrentFeedback() {
            statusLabel.stringValue = normalStatusMessage(for: session)
        } else if let feedback = router.feedbackMessage {
            statusLabel.stringValue = feedback
        } else if let guidance = router.pendingShortcutGuidance {
            statusLabel.stringValue = guidance
        } else {
            statusLabel.stringValue = normalStatusMessage(for: session)
        }
        statusLabel.setAccessibilityValue(statusLabel.stringValue)
        updateLayout(
            for: view.bounds.width > 0 ? view.bounds.width : PaletteLayout.minimumAllToolsWidth
        )
    }

    public var preferredSize: NSSize {
        NSSize(width: PaletteLayout.minimumAllToolsWidth, height: 156)
    }

    public var statusMessage: String {
        statusLabel?.stringValue ?? ""
    }

    public var isVisualEffectHidden: Bool {
        visualEffectView?.isHidden ?? true
    }

    public var appliedBorderWidth: CGFloat {
        viewIfLoaded?.layer?.borderWidth ?? 0
    }

    public var appearanceObserverCount: Int {
        displayOptionsObserver == nil ? 0 : 1
    }

    public func startAppearanceObservation() {
        if !isViewLoaded {
            loadViewIfNeeded()
        }
        applyDisplayOptions()
        installDisplayOptionsObserver()
    }

    public func stopAppearanceObservation() {
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
            self.displayOptionsObserver = nil
        }
    }

    public func control(identifier: String) -> NSControl {
        loadViewIfNeeded()
        guard let control = controls.first(where: { $0.identifier?.rawValue == identifier }) else {
            preconditionFailure("Unknown palette control: \(identifier)")
        }
        return control
    }

    public func applyLayout(for width: CGFloat) {
        pendingLayoutWidth = width
        updateLayout(for: width)
    }

    public func buttonType(for identifier: String) -> NSButton.ButtonType? {
        configuredButtonTypes[identifier]
    }

    public override func viewDidLayout() {
        super.viewDidLayout()
        guard view.bounds.width > 0 else { return }
        let width = pendingLayoutWidth ?? view.bounds.width
        updateLayout(for: width)
        if let pendingLayoutWidth, view.bounds.width <= pendingLayoutWidth + 1 {
            self.pendingLayoutWidth = nil
        }
        collapseHiddenDelete()
    }

    private func buildControls() {
        modeButton = makeButton(
            title: "Standby",
            identifier: "palette.mode",
            label: "Toggle annotation mode",
            help: "Enter or exit annotation mode"
        )
        modeButton.target = self
        modeButton.action = #selector(toggleMode)

        for tool in PointerTool.allCases {
            let button = makeButton(
                title: tool.displayName,
                identifier: "palette.tool.\(tool.identifier)",
                label: tool.displayName,
                help: "Choose the \(tool.displayName) annotation tool"
            )
            button.image = NSImage(
                systemSymbolName: symbolName(for: tool),
                accessibilityDescription: tool.displayName
            )
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: PaletteLayout.width(for: tool)).isActive = true
            button.tag = PointerTool.allCases.firstIndex(of: tool) ?? 0
            button.target = self
            button.action = #selector(selectTool(_:))
            toolButtons[tool] = button
        }

        overflowButton = makePopup(
            title: "More",
            identifier: "palette.tools.overflow",
            label: "More annotation tools",
            help: "Choose an annotation tool from the compact overflow menu"
        )
        overflowButton.pullsDown = true
        overflowButton.target = self
        overflowButton.action = #selector(selectOverflowTool(_:))

        emojiPicker = makePopup(
            title: "👉",
            identifier: "palette.emoji",
            label: "Emoji preset",
            help: "Choose the emoji used by future emoji stamps and the selected emoji mark"
        )
        emojiPicker.addItems(withTitles: ["👉", "⭐️", "✅", "❗️", "❤️", "🎯"])
        emojiPicker.target = self
        emojiPicker.action = #selector(selectEmoji(_:))

        colorWell = makeColorWell(
            identifier: "palette.style.color",
            label: "Annotation color",
            help: "Choose the color for compatible annotation marks"
        )
        colorWell.target = self
        colorWell.action = #selector(changeColor(_:))

        strokeSlider = makeSlider(
            identifier: "palette.style.stroke-width",
            label: "Stroke width",
            help: "Set the stroke width for compatible annotation marks",
            min: 1,
            max: 24,
            value: 4
        )
        strokeSlider.target = self
        strokeSlider.action = #selector(changeStroke(_:))

        opacitySlider = makeSlider(
            identifier: "palette.style.opacity",
            label: "Annotation opacity",
            help: "Set annotation opacity",
            min: 0,
            max: 1,
            value: 1
        )
        opacitySlider.target = self
        opacitySlider.action = #selector(changeOpacity(_:))

        radiusSlider = makeSlider(
            identifier: "palette.spotlight.radius",
            label: "Spotlight radius",
            help: "Set the spotlight radius",
            min: 0,
            max: 1,
            value: 0.15
        )
        radiusSlider.target = self
        radiusSlider.action = #selector(changeSpotlight(_:))

        strokeValueLabel = valueLabel()
        opacityValueLabel = valueLabel()
        radiusValueLabel = valueLabel()
        dimnessValueLabel = valueLabel()

        dimnessSlider = makeSlider(
            identifier: "palette.spotlight.dimness",
            label: "Spotlight dimness",
            help: "Set the dimness outside the spotlight",
            min: 0,
            max: 1,
            value: 0.5
        )
        dimnessSlider.target = self
        dimnessSlider.action = #selector(changeSpotlight(_:))

        undoButton = makeButton(
            title: "Undo",
            identifier: "palette.undo",
            label: "Undo last pointer-display change",
            help: "Undo the last change on the pointer display",
            buttonType: .momentaryPushIn
        )
        undoButton.target = self
        undoButton.action = #selector(undo)

        clearButton = makeButton(
            title: "Clear",
            identifier: "palette.clear",
            label: "Clear pointer display",
            help: "Clear every mark on the pointer display",
            buttonType: .momentaryPushIn
        )
        clearButton.target = self
        clearButton.action = #selector(clear)

        deleteButton = makeButton(
            title: "Delete",
            identifier: "palette.delete",
            label: "Delete selected mark",
            help: "Delete the selected mark",
            buttonType: .momentaryPushIn
        )
        deleteButton.target = self
        deleteButton.action = #selector(delete)

        statusLabel = NSTextField(labelWithString: "Standby — overlays are click-through")
        configure(
            statusLabel,
            identifier: "palette.status",
            label: "Pointer status",
            help: "Current annotation mode and shortcut status"
        )
        statusLabel.isSelectable = false
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        controls += [modeButton]
        controls += PointerTool.allCases.compactMap { toolButtons[$0] }
        controls += [overflowButton, emojiPicker, colorWell, strokeSlider, opacitySlider, radiusSlider, dimnessSlider]
        controls += [undoButton, clearButton, deleteButton, statusLabel]
    }

    private func layoutControls() {
        let firstRow = NSStackView(views: [modeButton] + PointerTool.allCases.compactMap { toolButtons[$0] } + [overflowButton])
        firstRow.orientation = .horizontal
        firstRow.spacing = 6
        firstRow.distribution = .fillEqually
        firstRow.detachesHiddenViews = true
        firstRow.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        firstRow.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for arrangedSubview in firstRow.arrangedSubviews {
            arrangedSubview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            arrangedSubview.setContentHuggingPriority(.defaultLow, for: .horizontal)
            arrangedSubview.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            arrangedSubview.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        }
        modeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: PaletteLayout.modeWidth).isActive = true
        overflowButton.widthAnchor.constraint(greaterThanOrEqualToConstant: PaletteLayout.overflowWidth).isActive = true
        modeButton.bezelStyle = .texturedRounded

        let styleRow = NSStackView(views: [
            labeled("Color", colorWell),
            labeled("Emoji", emojiPicker),
            labeled("Stroke", strokeSlider, valueLabel: strokeValueLabel),
            labeled("Opacity", opacitySlider, valueLabel: opacityValueLabel),
            labeled("Radius", radiusSlider, valueLabel: radiusValueLabel),
            labeled("Dimness", dimnessSlider, valueLabel: dimnessValueLabel),
        ])
        styleRow.orientation = .horizontal
        styleRow.spacing = 8
        styleRow.alignment = .centerY
        styleRow.distribution = .fill
        for arrangedSubview in styleRow.arrangedSubviews {
            arrangedSubview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            arrangedSubview.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        let actionStack = PaletteActionStack(views: [undoButton, clearButton, deleteButton])
        actionStack.contextualDelete = deleteButton
        actionStack.orientation = .horizontal
        actionStack.spacing = 6
        actionStack.alignment = .centerY
        actionStack.distribution = .fillEqually
        actionStack.detachesHiddenViews = true
        for action in [undoButton!, clearButton!] {
            action.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            action.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        }
        deleteHitTargetConstraints = [
            deleteButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            deleteButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
        ]

        styleScrollView = PaletteStyleScrollView()
        styleScrollView.drawsBackground = false
        styleScrollView.hasVerticalScroller = false
        styleScrollView.hasHorizontalScroller = true
        styleScrollView.horizontalScrollElasticity = .none
        styleScrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        styleScrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        styleScrollView.documentView = styleRow
        styleRow.translatesAutoresizingMaskIntoConstraints = true
        styleRow.frame = NSRect(
            origin: .zero,
            size: NSSize(width: styleRow.fittingSize.width, height: 42)
        )

        let styleAndActions = NSStackView(views: [styleScrollView, actionStack])
        styleAndActions.orientation = .horizontal
        styleAndActions.spacing = 8
        styleAndActions.alignment = .centerY
        styleAndActions.distribution = .fill
        styleScrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        styleScrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [firstRow, styleAndActions, statusLabel])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            firstRow.heightAnchor.constraint(equalToConstant: 34),
            styleAndActions.heightAnchor.constraint(equalToConstant: 42),
        ])
    }

    private func updateLayout(for width: CGFloat) {
        let plan = PaletteLayout.plan(availableWidth: Double(width))
        if plan != layoutPlan {
            layoutPlan = plan
        }
        let visibleTools = Set(plan.rows.flatMap { row in
            row.compactMap { item -> PointerTool? in
                guard case let .tool(tool) = item else { return nil }
                return tool
            }
        })
        for (tool, button) in toolButtons {
            button.isHidden = !visibleTools.contains(tool)
        }
        overflowButton.isHidden = !plan.usesOverflow
        let hasActiveOverflowTool = plan.overflowTools.contains(currentSession.toolState.tool)
        let activeOverflowTool = hasActiveOverflowTool ? currentSession.toolState.tool : nil
        if renderedOverflowTools != plan.overflowTools
            || renderedOverflowActiveTool != activeOverflowTool
        {
            renderOverflowMenu(
                tools: plan.overflowTools,
                activeTool: activeOverflowTool
            )
            renderedOverflowTools = plan.overflowTools
            renderedOverflowActiveTool = activeOverflowTool
        }
        overflowButton.setAccessibilityValue(
            plan.overflowTools.isEmpty
                ? "No hidden tools"
                : "Active tool: \(currentSession.toolState.tool.displayName). Hidden tools: "
                    + plan.overflowTools.map(\.displayName).joined(separator: ", ")
        )
        updateKeyViewLoop()
    }

    private func renderOverflowMenu(
        tools: [PointerTool],
        activeTool: PointerTool?
    ) {
        overflowButton.menu?.removeAllItems()
        let headerTitle = activeTool.map {
            "More · \(overflowActiveTitle(for: $0))"
        } ?? "More Tools"
        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.identifier = NSUserInterfaceItemIdentifier("palette.overflow.header")
        header.setAccessibilityElement(true)
        header.setAccessibilityLabel(
            activeTool.map {
                "More annotation tools; active tool \($0.displayName)"
            } ?? "More annotation tools"
        )
        header.setAccessibilityHelp("Choose an annotation tool from the compact overflow menu")
        header.setAccessibilityValue(activeTool?.displayName ?? "No active hidden tool")
        header.isEnabled = false
        overflowButton.menu?.addItem(header)
        for tool in tools {
            let item = NSMenuItem(
                title: tool.displayName,
                action: #selector(selectOverflowMenuItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.identifier = NSUserInterfaceItemIdentifier(
                "palette.overflow.tool.\(tool.identifier)"
            )
            item.representedObject = tool.identifier
            item.state = activeTool == tool ? .on : .off
            item.setAccessibilityElement(true)
            item.setAccessibilityLabel(tool.displayName)
            item.setAccessibilityHelp("Select the \(tool.displayName) annotation tool")
            item.setAccessibilityValue(activeTool == tool ? "Selected" : "Not selected")
            item.setAccessibilityRoleDescription("menu item")
            overflowButton.menu?.addItem(item)
        }
        overflowButton.selectItem(at: 0)
        overflowButton.title = headerTitle
        overflowButton.image = nil
        overflowButton.setAccessibilityLabel(header.accessibilityLabel() ?? "More annotation tools")
    }

    private func overflowActiveTitle(for tool: PointerTool) -> String {
        switch tool {
        case .rectangle: return "Rect"
        case .ellipse: return "Oval"
        case .spotlight: return "Spot"
        case .eraser: return "Erase"
        default: return tool.displayName
        }
    }

    private func updateKeyViewLoop() {
        for control in controls {
            control.nextKeyView = nil
        }
        let reachable = controls.filter { control in
            control.identifier?.rawValue != "palette.status"
                && control.isEnabled
                && !control.isHidden
                && control.acceptsFirstResponder
                && !(control.identifier?.rawValue.isEmpty ?? true)
        }
        guard reachable.count > 1 else { return }
        for (index, control) in reachable.enumerated() {
            control.nextKeyView = reachable[(index + 1) % reachable.count]
        }
    }

    private func updateContextualState(
        session: PointerSession,
        selectionGeometry: MarkGeometry?
    ) {
        let styleEnabled = styleApplies(
            to: session.toolState.tool,
            selectionGeometry: selectionGeometry
        )
        setEnabled(
            colorWell,
            enabled: styleEnabled,
            help: styleEnabled
                ? "Choose the color for compatible annotation marks"
                : "Annotation color applies to arrows, rectangles, ellipses, and pen marks"
        )
        setEnabled(
            strokeSlider,
            enabled: styleEnabled,
            help: styleEnabled
                ? "Set the stroke width for compatible annotation marks"
                : "Stroke width applies to arrows, rectangles, ellipses, and pen marks"
        )
        setEnabled(
            opacitySlider,
            enabled: styleEnabled,
            help: styleEnabled
                ? "Set annotation opacity"
                : "Opacity applies to arrows, rectangles, ellipses, and pen marks"
        )

        let emojiEnabled = session.toolState.tool == .emoji || isEmoji(selectionGeometry)
        setEnabled(
            emojiPicker,
            enabled: emojiEnabled,
            help: emojiEnabled
                ? "Choose the emoji used by future emoji stamps and the selected emoji mark"
                : "Emoji is available only for the Emoji tool or a selected Emoji mark"
        )

        let spotlightEnabled = session.toolState.tool == .spotlight || isSpotlight(selectionGeometry)
        setEnabled(
            radiusSlider,
            enabled: spotlightEnabled,
            help: spotlightEnabled
                ? "Set the spotlight radius"
                : "Spotlight radius is available only for the Spotlight tool or a selected Spotlight mark"
        )
        setEnabled(
            dimnessSlider,
            enabled: spotlightEnabled,
            help: spotlightEnabled
                ? "Set the dimness outside the spotlight"
                : "Spotlight dimness is available only for the Spotlight tool or a selected Spotlight mark"
        )

        let canDelete = session.mode == .annotation && session.selection != nil
        deleteButton.isEnabled = canDelete
        deleteButton.isHidden = !canDelete
        if canDelete {
            NSLayoutConstraint.activate(deleteHitTargetConstraints)
        } else {
            NSLayoutConstraint.deactivate(deleteHitTargetConstraints)
            collapseHiddenDelete()
        }
        deleteButton.setAccessibilityHelp(
            canDelete
                ? "Delete the selected mark"
                : "Delete is available only for an explicitly selected mark in annotation mode"
        )
    }

    private func setEnabled(
        _ control: NSControl,
        enabled: Bool,
        help: String
    ) {
        control.isEnabled = enabled
        control.setAccessibilityHelp(help)
    }

    private func collapseHiddenDelete() {
        guard deleteButton?.isHidden == true else { return }
        deleteButton.setFrameSize(.zero)
    }

    private func selectedMark(in session: PointerSession) -> Mark? {
        guard let selection = session.selection,
              let display = session.selectedDisplay
        else {
            return nil
        }
        return session.canvas(for: display).marks.first { $0.id == selection }
    }

    private func selectedGeometry(in session: PointerSession) -> MarkGeometry? {
        selectedMark(in: session)?.geometry
    }

    private func compatibleStyle(for mark: Mark?) -> MarkStyle? {
        guard let mark else { return nil }
        switch mark.geometry {
        case .arrow, .rectangle, .ellipse, .freehand:
            return mark.style
        case .emoji, .spotlight:
            return nil
        }
    }

    private func emojiValue(for mark: Mark?) -> String? {
        guard let mark else { return nil }
        if case let .emoji(text, _) = mark.geometry { return text }
        return nil
    }

    private func spotlightValues(for mark: Mark?) -> (radius: Double, dimness: Double)? {
        guard let mark else { return nil }
        if case let .spotlight(_, radius, dimness) = mark.geometry {
            return (radius, dimness)
        }
        return nil
    }

    private func styleBaseline() -> MarkStyle {
        compatibleStyle(for: selectedMark(in: currentSession)) ?? currentSession.toolState.style
    }

    private func spotlightBaseline() -> (radius: Double, dimness: Double) {
        spotlightValues(for: selectedMark(in: currentSession))
            ?? (
                currentSession.toolState.spotlightRadius,
                currentSession.toolState.spotlightDimness
            )
    }

    private func styleApplies(
        to tool: PointerTool,
        selectionGeometry: MarkGeometry?
    ) -> Bool {
        switch tool {
        case .arrow, .rectangle, .ellipse, .pen:
            return true
        case .select, .eraser, .emoji, .spotlight:
            return styleGeometryIsCompatible(selectionGeometry)
        }
    }

    private func styleGeometryIsCompatible(_ geometry: MarkGeometry?) -> Bool {
        guard let geometry else { return false }
        switch geometry {
        case .arrow, .rectangle, .ellipse, .freehand:
            return true
        case .emoji, .spotlight:
            return false
        }
    }

    private func isEmoji(_ geometry: MarkGeometry?) -> Bool {
        guard let geometry else { return false }
        if case .emoji = geometry { return true }
        return false
    }

    private func isSpotlight(_ geometry: MarkGeometry?) -> Bool {
        guard let geometry else { return false }
        if case .spotlight = geometry { return true }
        return false
    }

    private func applyDisplayOptions() {
        let options = displayOptionsProvider()
        appliedDisplayOptions = options
        displayOptionsRefreshCount += 1
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            if options.reduceTransparency {
                visualEffectView.isHidden = true
                view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            } else {
                visualEffectView.isHidden = false
                view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.84).cgColor
            }
            view.layer?.borderWidth = options.increaseContrast ? 2 : 1
            view.layer?.borderColor = (options.increaseContrast ? NSColor.labelColor : NSColor.separatorColor).cgColor
        }
    }

    private func showFeedback(_ message: String) {
        guard isViewLoaded else { return }
        if let error = router.shortcutError {
            shortcutErrorWasDisplayed = true
            shortcutSuppressedFeedback = message
            statusLabel.stringValue = "Shortcut unavailable: \(error)"
            statusLabel.setAccessibilityValue(statusLabel.stringValue)
            return
        }
        if let guidance = router.pendingShortcutGuidance {
            shortcutErrorWasDisplayed = false
            shortcutSuppressedFeedback = message
            statusLabel.stringValue = guidance
            statusLabel.setAccessibilityValue(guidance)
            return
        }
        if shortcutSuppressedFeedback == message {
            statusLabel.stringValue = normalStatusMessage(for: currentSession)
            statusLabel.setAccessibilityValue(statusLabel.stringValue)
            return
        }
        shortcutSuppressedFeedback = nil
        statusLabel.stringValue = message
        statusLabel.setAccessibilityValue(message)
    }

    private func normalStatusMessage(for session: PointerSession) -> String {
        let modeStatus = session.mode == .annotation
            ? "Annotation enabled"
            : "Standby — overlays are click-through"
        return router.activeShortcutID.map {
            "\(modeStatus) · Shortcut: \($0)"
        } ?? modeStatus
    }

    private func shouldSuppressCurrentFeedback() -> Bool {
        guard let suppressed = shortcutSuppressedFeedback else { return false }
        guard let feedback = router.feedbackMessage else {
            shortcutSuppressedFeedback = nil
            return false
        }
        guard feedback == suppressed else {
            shortcutSuppressedFeedback = nil
            return false
        }
        return true
    }

    @objc private func toggleMode() {
        route(.toggleMode)
    }

    @objc private func selectTool(_ sender: NSButton) {
        guard sender.tag < PointerTool.allCases.count else { return }
        route(.setTool(PointerTool.allCases[sender.tag]))
    }

    @objc private func selectOverflowTool(_ sender: NSPopUpButton) {
        let rawIdentifier = sender.selectedItem?.representedObject as? String
        guard let tool = PointerTool.allCases.first(where: { $0.identifier == rawIdentifier }) else { return }
        route(.setTool(tool))
    }

    @objc private func selectOverflowMenuItem(_ sender: NSMenuItem) {
        let rawIdentifier = sender.representedObject as? String
        guard let tool = PointerTool.allCases.first(where: { $0.identifier == rawIdentifier }) else { return }
        route(.setTool(tool))
    }

    @objc private func selectEmoji(_ sender: NSPopUpButton) {
        guard let emoji = sender.titleOfSelectedItem else { return }
        route(.setEmoji(emoji))
    }

    @objc private func changeColor(_ sender: NSColorWell) {
        guard let color = rgbaColor(from: sender.color) else { return }
        let old = styleBaseline()
        route(.setStyle(MarkStyle(color: color, strokeWidth: old.strokeWidth, opacity: old.opacity)))
    }

    @objc private func changeStroke(_ sender: NSSlider) {
        let old = styleBaseline()
        route(.setStyle(MarkStyle(color: old.color, strokeWidth: sender.doubleValue, opacity: old.opacity)))
    }

    @objc private func changeOpacity(_ sender: NSSlider) {
        let old = styleBaseline()
        route(.setStyle(MarkStyle(color: old.color, strokeWidth: old.strokeWidth, opacity: sender.doubleValue)))
    }

    @objc private func changeSpotlight(_ sender: NSSlider) {
        let old = spotlightBaseline()
        let radius = sender === radiusSlider ? sender.doubleValue : old.radius
        let dimness = sender === dimnessSlider ? sender.doubleValue : old.dimness
        route(.setSpotlight(radius: radius, dimness: dimness))
    }

    @objc private func undo() {
        route(.undo)
    }

    @objc private func clear() {
        route(.clear)
    }

    @objc private func delete() {
        route(.delete)
    }

    private func route(_ command: CommandRouter.Command) {
        router.route(command)
        currentSession = router.session
    }

    private func makeButton(
        title: String,
        identifier: String,
        label: String,
        help: String,
        buttonType: NSButton.ButtonType = .toggle
    ) -> NSButton {
        let button = PaletteFocusableButton(title: title, target: nil, action: nil)
        configure(button, identifier: identifier, label: label, help: help)
        button.bezelStyle = .rounded
        button.setButtonType(buttonType)
        configuredButtonTypes[identifier] = buttonType
        return button
    }

    private func makePopup(title: String, identifier: String, label: String, help: String) -> NSPopUpButton {
        let popup = PaletteFocusablePopup(title: title, target: nil, action: nil)
        configure(popup, identifier: identifier, label: label, help: help)
        return popup
    }

    private func makeColorWell(identifier: String, label: String, help: String) -> NSColorWell {
        let well = PaletteFocusableColorWell(frame: .zero)
        configure(well, identifier: identifier, label: label, help: help)
        return well
    }

    private func makeSlider(
        identifier: String,
        label: String,
        help: String,
        min: Double,
        max: Double,
        value: Double
    ) -> NSSlider {
        let slider = PaletteFocusableSlider(value: value, minValue: min, maxValue: max, target: nil, action: nil)
        configure(slider, identifier: identifier, label: label, help: help)
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        slider.isContinuous = true
        return slider
    }

    private func configure(_ control: NSControl, identifier: String, label: String, help: String) {
        control.setAccessibilityElement(true)
        control.setAccessibilityLabel(label)
        control.setAccessibilityHelp(help)
        control.identifier = NSUserInterfaceItemIdentifier(identifier)
        control.focusRingType = .exterior
        control.isEnabled = true
        control.setAccessibilityRoleDescription(roleDescription(for: control))
    }

    private func roleDescription(for control: NSControl) -> String {
        switch control {
        case is NSPopUpButton:
            return "popup button"
        case is NSColorWell:
            return "color well"
        case is NSSlider:
            return "slider"
        case is NSTextField:
            return "status"
        default:
            return "button"
        }
    }

    private func valueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private func labeled(
        _ title: String,
        _ control: NSControl,
        valueLabel: NSTextField? = nil
    ) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11)
        let caption = NSStackView(views: valueLabel.map { [label, $0] } ?? [label])
        caption.orientation = .horizontal
        caption.alignment = .centerY
        caption.spacing = 4
        caption.distribution = .fill
        let stack = NSStackView(views: [caption, control])
        stack.orientation = .vertical
        stack.spacing = 2
        return stack
    }

    private func symbolName(for tool: PointerTool) -> String {
        switch tool {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .pen: return "pencil.tip"
        case .eraser: return "eraser"
        case .emoji: return "face.smiling"
        case .spotlight: return "flashlight.on.fill"
        }
    }

    private func formattedStroke(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func formattedPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func nsColor(from color: RGBAColor) -> NSColor {
        NSColor(
            calibratedRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
    }

    private func rgbaColor(from color: NSColor) -> RGBAColor? {
        guard let converted = color.usingColorSpace(.deviceRGB) else { return nil }
        return RGBAColor(
            red: converted.redComponent,
            green: converted.greenComponent,
            blue: converted.blueComponent,
            alpha: converted.alphaComponent
        )
    }
}

extension PointerTool {
    fileprivate var identifier: String {
        switch self {
        case .select: return "select"
        case .arrow: return "arrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "ellipse"
        case .pen: return "pen"
        case .eraser: return "eraser"
        case .emoji: return "emoji"
        case .spotlight: return "spotlight"
        }
    }
}

extension PointerTool {
    var displayName: String {
        switch self {
        case .select: return "Select"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .pen: return "Pen"
        case .eraser: return "Eraser"
        case .emoji: return "Emoji"
        case .spotlight: return "Spotlight"
        }
    }
}
