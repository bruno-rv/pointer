import AppKit
import PointerCore

@MainActor
public protocol MenuBarPresenting: AnyObject {
    func install()
    func refresh(session: PointerSession)
    func remove()
}

@MainActor
public final class MenuBarController: NSObject, MenuBarPresenting {
    public var onShowPalette: (() -> Void)?

    public private(set) var statusItem: NSStatusItem?
    public private(set) var menu: NSMenu?

    private let router: CommandRouter
    private weak var shortcutController: HotKeyController?
    private let terminate: () -> Void
    private var modeItem: NSMenuItem?
    private var undoClearAllItem: NSMenuItem?
    private var shortcutItems: [ShortcutPreset: NSMenuItem] = [:]

    public init(
        router: CommandRouter,
        shortcutController: HotKeyController? = nil,
        terminate: @escaping @MainActor () -> Void = { @MainActor in NSApp.terminate(nil) }
    ) {
        self.router = router
        self.shortcutController = shortcutController
        self.terminate = terminate
        super.init()
        router.onClearAllRequested = { [weak self] in
            self?.presentClearAllConfirmation()
        }
    }

    public func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "◉"
        item.button?.setAccessibilityElement(true)
        item.button?.setAccessibilityLabel("Pointer menu")
        item.button?.setAccessibilityHelp("Open Pointer controls")
        item.button?.identifier = NSUserInterfaceItemIdentifier("pointer.menu-bar")

        let menu = NSMenu(title: "Pointer")
        menu.autoenablesItems = false
        menu.addItem(itemWithTitle("Show Palette", action: #selector(showPalette), identifier: "menu.show-palette"))
        modeItem = itemWithTitle(
            "Enter Annotation",
            action: #selector(toggleMode),
            identifier: "menu.toggle-mode"
        )
        menu.addItem(modeItem!)
        menu.addItem(.separator())

        let shortcuts = NSMenuItem(title: "Shortcut", action: nil, keyEquivalent: "")
        shortcuts.identifier = NSUserInterfaceItemIdentifier("menu.shortcut")
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

        menu.addItem(.separator())
        menu.addItem(itemWithTitle("Clear All Displays…", action: #selector(clearAll), identifier: "menu.clear-all"))
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
        modeItem?.title = session.mode == .annotation ? "Exit Annotation" : "Enter Annotation"
        undoClearAllItem?.isEnabled = router.canUndoClearAll
        for preset in ShortcutPreset.allCases {
            shortcutItems[preset]?.state = shortcutController?.activePreset == preset ? .on : .off
        }
        if let error = shortcutController?.registrationError {
            statusItem?.button?.toolTip = "Pointer shortcut unavailable: \(error)"
        } else {
            statusItem?.button?.toolTip = "Pointer controls"
        }
    }

    public func remove() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        menu = nil
    }

    @objc private func showPalette() {
        onShowPalette?()
    }

    @objc private func toggleMode() {
        router.route(.toggleMode)
    }

    @objc private func selectShortcut(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let preset = ShortcutPreset(rawValue: rawValue) else {
            return
        }
        router.route(.setShortcut(preset))
    }

    @objc private func clearAll() {
        router.route(.clearAll)
    }

    @objc private func undoClearAll() {
        router.route(.undoClearAll)
    }

    @objc private func quit() {
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
        return item
    }
}
