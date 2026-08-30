import AppKit
import PointerCore

@MainActor
public protocol MenuBarPresenting: AnyObject {
    var menuResourceCount: Int { get }
    var callbackBindingCount: Int { get }
    func install()
    func refresh(session: PointerSession)
    func remove()
    @discardableResult
    func bindCallbacks(onShowPalette: (() -> Void)?, onLearnPointer: (() -> Void)?) -> Int
    func clearCallbacks()
}

public extension MenuBarPresenting {
    var menuResourceCount: Int { 0 }
    var callbackBindingCount: Int { 0 }
}

@MainActor
public final class MenuBarController: NSObject, MenuBarPresenting {
    public var onShowPalette: (() -> Void)?
    public var onLearnPointer: (() -> Void)?

    public private(set) var statusItem: NSStatusItem?
    public private(set) var menu: NSMenu?
    public var menuResourceCount: Int { statusItem == nil ? 0 : 1 }
    public var callbackBindingCount: Int { callbacksBound ? 1 : 0 }

    private let router: CommandRouter
    private weak var shortcutController: HotKeyController?
    private let terminate: () -> Void
    private static let noDisplayFeedback = "No presentation display connected"
    private static let noDisplayUnavailable = "Unavailable — no presentation display connected"
    private var modeItem: NSMenuItem?
    private var clearAllItem: NSMenuItem?
    private var undoClearAllItem: NSMenuItem?
    private var shortcutMenuItem: NSMenuItem?
    private var shortcutItems: [ShortcutPreset: NSMenuItem] = [:]
    private var callbacksBound = false

    public init(
        router: CommandRouter,
        shortcutController: HotKeyController? = nil,
        terminate: @escaping @MainActor () -> Void = { @MainActor in NSApp.terminate(nil) }
    ) {
        self.router = router
        self.shortcutController = shortcutController
        self.terminate = terminate
        super.init()
    }

    @discardableResult
    public func bindCallbacks(
        onShowPalette: (() -> Void)?,
        onLearnPointer: (() -> Void)?
    ) -> Int {
        self.onShowPalette = onShowPalette
        self.onLearnPointer = onLearnPointer
        callbacksBound = true
        router.onClearAllRequested = { [weak self] in
            guard let self, self.callbacksBound else { return }
            self.presentClearAllConfirmation()
        }
        return (onShowPalette == nil ? 0 : 1)
            + (onLearnPointer == nil ? 0 : 1)
    }

    public func clearCallbacks() {
        callbacksBound = false
        onShowPalette = nil
        onLearnPointer = nil
        router.onClearAllRequested = nil
    }

    public func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "◉"
        item.button?.setAccessibilityElement(true)
        item.button?.setAccessibilityLabel("Pointer menu")
        item.button?.setAccessibilityHelp("Open Pointer controls")
        item.button?.setAccessibilityRoleDescription("menu bar item")
        item.button?.focusRingType = .exterior
        item.button?.identifier = NSUserInterfaceItemIdentifier("pointer.menu-bar")

        let menu = NSMenu(title: "Pointer")
        menu.autoenablesItems = false
        menu.addItem(itemWithTitle("Show Palette", action: #selector(showPalette), identifier: "menu.show-palette"))
        menu.addItem(itemWithTitle("Learn Pointer", action: #selector(learnPointer), identifier: "menu.learn-pointer"))
        modeItem = itemWithTitle(
            "Enter Annotation",
            action: #selector(toggleMode),
            identifier: "menu.toggle-mode"
        )
        menu.addItem(modeItem!)
        menu.addItem(.separator())

        let shortcuts = NSMenuItem(title: "Shortcut", action: nil, keyEquivalent: "")
        shortcuts.identifier = NSUserInterfaceItemIdentifier("menu.shortcut")
        shortcuts.isEnabled = true
        shortcuts.setAccessibilityElement(true)
        shortcuts.setAccessibilityLabel("Shortcut")
        shortcuts.setAccessibilityHelp("Choose the active global shortcut preset")
        shortcuts.setAccessibilityRoleDescription("menu")
        let shortcutMenu = NSMenu(title: "Shortcut")
        for preset in ShortcutPreset.allCases {
            let shortcutItem = itemWithTitle(
                preset.displayName,
                action: #selector(selectShortcut(_:)),
                identifier: "menu.shortcut.\(preset.rawValue)"
            )
            shortcutItem.representedObject = preset.rawValue
            shortcutItems[preset] = shortcutItem
            shortcutMenu.addItem(shortcutItem)
        }
        shortcuts.submenu = shortcutMenu
        menu.addItem(shortcuts)
        shortcutMenuItem = shortcuts

        menu.addItem(.separator())
        clearAllItem = itemWithTitle(
            "Clear All Displays…",
            action: #selector(clearAll),
            identifier: "menu.clear-all"
        )
        menu.addItem(clearAllItem!)
        undoClearAllItem = itemWithTitle(
            "Undo Clear All",
            action: #selector(undoClearAll),
            identifier: "menu.undo-clear-all"
        )
        menu.addItem(undoClearAllItem!)
        menu.addItem(.separator())
        menu.addItem(itemWithTitle("Quit Pointer", action: #selector(quit), identifier: "menu.quit"))

        item.menu = menu
        statusItem = item
        self.menu = menu
        refresh(session: router.session)
    }

    public func refresh(session: PointerSession) {
        if let modeItem {
            let hasDisplay = router.pointerDisplay != nil
            modeItem.isEnabled = hasDisplay
            modeItem.title = hasDisplay && session.mode == .annotation
                ? "Exit Annotation"
                : "Enter Annotation"
            modeItem.setAccessibilityLabel(modeItem.title)
            if hasDisplay {
                modeItem.setAccessibilityHelp("Toggle annotation mode")
                modeItem.setAccessibilityValue(session.mode == .annotation ? "Selected" : "Not selected")
            } else {
                modeItem.setAccessibilityHelp(Self.noDisplayUnavailable)
                modeItem.setAccessibilityValue(Self.noDisplayUnavailable)
            }
        }
        let canClearAll = router.canClearAll
        clearAllItem?.isEnabled = canClearAll
        clearAllItem?.setAccessibilityValue(
            canClearAll ? "Available" : "Unavailable — no marks to clear"
        )
        clearAllItem?.setAccessibilityHelp(
            canClearAll
                ? "Clear all marks on connected displays"
                : "Unavailable — no marks to clear"
        )
        undoClearAllItem?.isEnabled = router.canUndoClearAll
        undoClearAllItem?.setAccessibilityValue(router.canUndoClearAll ? "Available" : "Unavailable")
        for preset in ShortcutPreset.allCases {
            let isSelected = shortcutController?.activePreset == preset
            let isPending = shortcutController?.pendingPreset == preset
            shortcutItems[preset]?.state = isSelected ? .on : (isPending ? .mixed : .off)
            shortcutItems[preset]?.setAccessibilityValue(
                isSelected ? "Selected" : (isPending ? "Pending" : "Not selected")
            )
            if isPending, let guidance = router.pendingShortcutGuidance {
                shortcutItems[preset]?.setAccessibilityHelp(guidance)
            } else {
                shortcutItems[preset]?.setAccessibilityHelp("Pointer command: \(preset.displayName)")
            }
        }
        if let guidance = router.pendingShortcutGuidance {
            shortcutMenuItem?.setAccessibilityHelp(guidance)
            shortcutMenuItem?.setAccessibilityValue(guidance)
        } else if let error = shortcutController?.registrationError {
            let message = "Shortcut unavailable: \(error)"
            shortcutMenuItem?.setAccessibilityHelp(message)
            shortcutMenuItem?.setAccessibilityValue(message)
        } else {
            shortcutMenuItem?.setAccessibilityHelp("Choose the active global shortcut preset")
            shortcutMenuItem?.setAccessibilityValue(
                shortcutController?.activePreset.map { "Active: \($0.displayName)" }
                    ?? "No active shortcut"
            )
        }
        if router.pointerDisplay == nil {
            let button = statusItem?.button
            button?.title = ""
            button?.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: Self.noDisplayFeedback
            )
            button?.toolTip = Self.noDisplayFeedback
            button?.setAccessibilityHelp(Self.noDisplayFeedback)
            button?.setAccessibilityValue(Self.noDisplayFeedback)
        } else if let error = shortcutController?.registrationError {
            statusItem?.button?.title = "◉"
            statusItem?.button?.image = nil
            statusItem?.button?.toolTip = "Pointer shortcut unavailable: \(error)"
            statusItem?.button?.setAccessibilityHelp("Pointer shortcut unavailable: \(error)")
            statusItem?.button?.setAccessibilityValue("Shortcut unavailable: \(error)")
        } else if let guidance = router.pendingShortcutGuidance {
            statusItem?.button?.title = "◉"
            statusItem?.button?.image = nil
            statusItem?.button?.toolTip = guidance
            statusItem?.button?.setAccessibilityHelp(guidance)
            statusItem?.button?.setAccessibilityValue(guidance)
        } else {
            statusItem?.button?.title = "◉"
            statusItem?.button?.image = nil
            statusItem?.button?.toolTip = "Pointer controls"
            statusItem?.button?.setAccessibilityHelp("Open Pointer controls")
            statusItem?.button?.setAccessibilityValue("Pointer controls")
        }
    }

    public func remove() {
        clearCallbacks()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        menu = nil
    }

    @objc private func showPalette() {
        guard callbacksBound else { return }
        onShowPalette?()
    }

    @objc private func learnPointer() {
        guard callbacksBound else { return }
        onLearnPointer?()
    }

    @objc private func toggleMode() {
        guard callbacksBound else { return }
        router.route(.toggleMode)
    }

    @objc private func selectShortcut(_ sender: NSMenuItem) {
        guard callbacksBound else { return }
        guard let rawValue = sender.representedObject as? String,
              let preset = ShortcutPreset(rawValue: rawValue) else {
            return
        }
        router.route(.setShortcut(preset))
    }

    @objc private func clearAll() {
        guard callbacksBound else { return }
        router.route(.clearAll)
    }

    @objc private func undoClearAll() {
        guard callbacksBound else { return }
        router.route(.undoClearAll)
    }

    @objc private func quit() {
        guard callbacksBound else { return }
        terminate()
    }

    private func presentClearAllConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Clear all displays?"
        alert.informativeText = "Every pointer mark on every connected display will be removed. You can undo this from the menu."
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            router.confirmClearAll()
        }
    }

    private func itemWithTitle(
        _ title: String,
        action: Selector?,
        identifier: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.identifier = NSUserInterfaceItemIdentifier(identifier)
        item.setAccessibilityElement(true)
        item.setAccessibilityLabel(title)
        item.setAccessibilityHelp("Pointer command: \(title)")
        item.setAccessibilityRoleDescription("menu item")
        return item
    }
}
