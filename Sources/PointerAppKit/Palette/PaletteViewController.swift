import AppKit
import PointerCore

private final class PaletteStyleScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 42)
    }
}

@MainActor
public final class PaletteViewController: NSViewController {
    public private(set) var controls: [NSControl] = []
    public private(set) var layoutPlan = PaletteLayout.plan(availableWidth: 760)
    public private(set) var deleteButton: NSButton!

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

    public init(router: CommandRouter) {
        self.router = router
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
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 156))
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

        buildControls()
        layoutControls()
        refresh(session: currentSession)
        applyDisplayOptions()
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
        let style = session.toolState.style
        colorWell.color = nsColor(from: style.color)
        colorWell.setAccessibilityValue(
            "RGBA \(style.color.red), \(style.color.green), \(style.color.blue)"
        )
        strokeSlider.doubleValue = style.strokeWidth
        opacitySlider.doubleValue = style.opacity
        radiusSlider.doubleValue = session.toolState.spotlightRadius
        dimnessSlider.doubleValue = session.toolState.spotlightDimness
        emojiPicker.selectItem(withTitle: session.toolState.emoji)
        emojiPicker.setAccessibilityValue(session.toolState.emoji)
        strokeSlider.setAccessibilityValue(formattedStroke(style.strokeWidth))
        opacitySlider.setAccessibilityValue(formattedPercent(style.opacity))
        radiusSlider.setAccessibilityValue(formattedPercent(session.toolState.spotlightRadius))
        dimnessSlider.setAccessibilityValue(formattedPercent(session.toolState.spotlightDimness))
        strokeValueLabel?.stringValue = formattedStroke(style.strokeWidth)
        opacityValueLabel?.stringValue = formattedPercent(style.opacity)
        radiusValueLabel?.stringValue = formattedPercent(session.toolState.spotlightRadius)
        dimnessValueLabel?.stringValue = formattedPercent(session.toolState.spotlightDimness)
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
            statusLabel.stringValue = "Shortcut unavailable: \(error)"
        } else if let feedback = router.feedbackMessage {
            statusLabel.stringValue = feedback
        } else {
            let modeStatus = session.mode == .annotation
                ? "Annotation enabled"
                : "Standby — overlays are click-through"
            statusLabel.stringValue = router.activeShortcutID.map {
                "\(modeStatus) · Shortcut: \($0)"
            } ?? modeStatus
        }
        statusLabel.setAccessibilityValue(statusLabel.stringValue)
        updateLayout(for: view.bounds.width > 0 ? view.bounds.width : 760)
    }

    public var preferredSize: NSSize {
        NSSize(width: 760, height: 156)
    }

    public var statusMessage: String {
        statusLabel?.stringValue ?? ""
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
                title: title(for: tool),
                identifier: "palette.tool.\(tool.identifier)",
                label: title(for: tool),
                help: "Choose the \(tool.displayName) annotation tool"
            )
            button.image = NSImage(
                systemSymbolName: symbolName(for: tool),
                accessibilityDescription: title(for: tool)
            )
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
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
        overflowButton.addItems(withTitles: PointerTool.allCases.map(\.displayName))
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

        let actionStack = NSStackView(views: [undoButton, clearButton, deleteButton])
        actionStack.orientation = .horizontal
        actionStack.spacing = 6
        actionStack.alignment = .centerY
        actionStack.distribution = .fillEqually
        actionStack.detachesHiddenViews = false
        for action in actionStack.arrangedSubviews {
            action.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            action.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        }

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
        overflowButton.menu?.removeAllItems()
        for tool in plan.overflowTools {
            overflowButton.menu?.addItem(withTitle: tool.displayName, action: nil, keyEquivalent: "")
        }
        overflowButton.title = "More Tools"
        overflowButton.setAccessibilityValue(
            plan.overflowTools.isEmpty
                ? "No hidden tools"
                : plan.overflowTools.map(\.displayName).joined(separator: ", ")
        )
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

    private func selectedGeometry(in session: PointerSession) -> MarkGeometry? {
        guard let selection = session.selection,
              let display = session.selectedDisplay
        else {
            return nil
        }
        return session.canvas(for: display).marks.first { $0.id == selection }?.geometry
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
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if reduceTransparency {
            visualEffectView.isHidden = true
            view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        } else {
            visualEffectView.isHidden = false
            view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.84).cgColor
        }
        view.layer?.borderWidth = increaseContrast ? 2 : 1
        view.layer?.borderColor = (increaseContrast ? NSColor.labelColor : NSColor.separatorColor).cgColor
    }

    private func showFeedback(_ message: String) {
        guard isViewLoaded else { return }
        statusLabel.stringValue = message
    }

    @objc private func toggleMode() {
        router.route(.toggleMode)
    }

    @objc private func selectTool(_ sender: NSButton) {
        guard sender.tag < PointerTool.allCases.count else { return }
        router.route(.setTool(PointerTool.allCases[sender.tag]))
    }

    @objc private func selectOverflowTool(_ sender: NSPopUpButton) {
        let title = sender.titleOfSelectedItem ?? ""
        guard let tool = PointerTool.allCases.first(where: { $0.displayName == title }) else { return }
        router.route(.setTool(tool))
    }

    @objc private func selectEmoji(_ sender: NSPopUpButton) {
        guard let emoji = sender.titleOfSelectedItem else { return }
        router.route(.setEmoji(emoji))
    }

    @objc private func changeColor(_ sender: NSColorWell) {
        guard let color = rgbaColor(from: sender.color) else { return }
        let old = currentSession.toolState.style
        router.route(.setStyle(MarkStyle(color: color, strokeWidth: old.strokeWidth, opacity: old.opacity)))
    }

    @objc private func changeStroke(_ sender: NSSlider) {
        let old = currentSession.toolState.style
        router.route(.setStyle(MarkStyle(color: old.color, strokeWidth: sender.doubleValue, opacity: old.opacity)))
    }

    @objc private func changeOpacity(_ sender: NSSlider) {
        let old = currentSession.toolState.style
        router.route(.setStyle(MarkStyle(color: old.color, strokeWidth: old.strokeWidth, opacity: sender.doubleValue)))
    }

    @objc private func changeSpotlight(_ sender: NSSlider) {
        let radius = sender === radiusSlider ? sender.doubleValue : currentSession.toolState.spotlightRadius
        let dimness = sender === dimnessSlider ? sender.doubleValue : currentSession.toolState.spotlightDimness
        router.route(.setSpotlight(radius: radius, dimness: dimness))
    }

    @objc private func undo() {
        router.route(.undo)
    }

    @objc private func clear() {
        router.route(.clear)
    }

    @objc private func delete() {
        router.route(.delete)
    }

    private func makeButton(
        title: String,
        identifier: String,
        label: String,
        help: String,
        buttonType: NSButton.ButtonType = .toggle
    ) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        configure(button, identifier: identifier, label: label, help: help)
        button.bezelStyle = .rounded
        button.setButtonType(buttonType)
        configuredButtonTypes[identifier] = buttonType
        return button
    }

    private func makePopup(title: String, identifier: String, label: String, help: String) -> NSPopUpButton {
        let popup = NSPopUpButton(title: title, target: nil, action: nil)
        configure(popup, identifier: identifier, label: label, help: help)
        return popup
    }

    private func makeColorWell(identifier: String, label: String, help: String) -> NSColorWell {
        let well = NSColorWell(frame: .zero)
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
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: nil, action: nil)
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

    private func title(for tool: PointerTool) -> String {
        switch tool {
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

private extension PointerTool {
    var identifier: String {
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
