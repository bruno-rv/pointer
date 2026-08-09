import AppKit
import Carbon

private struct ShortcutCandidate: Equatable {
    let id: String
    let title: String
    let display: String
    let keyCode: UInt32?
    let modifiers: UInt32

    static let choices: [ShortcutCandidate] = [
        .init(
            id: "default",
            title: "Default — Control–Option–Command–P",
            display: "⌃⌥⌘P",
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        ),
        .init(
            id: "alternate",
            title: "Alternate — Control–Option–Command–O",
            display: "⌃⌥⌘O",
            keyCode: UInt32(kVK_ANSI_O),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        ),
        .init(
            id: "option-shift",
            title: "Compatibility probe — Option–Shift–P",
            display: "⌥⇧P",
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(optionKey | shiftKey)
        ),
        .init(
            id: "command-space",
            title: "System-reserved probe — Command–Space",
            display: "⌘Space",
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey)
        ),
        .init(
            id: "modifier-only",
            title: "Invalid probe — modifiers without a key",
            display: "⌃⌥⌘",
            keyCode: nil,
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        )
    ]

    static func candidate(id: String?) -> ShortcutCandidate {
        choices.first(where: { $0.id == id }) ?? choices[0]
    }
}

private enum RegistrationState {
    case registered(shortcut: ShortcutCandidate, status: OSStatus)
    case failed(candidate: ShortcutCandidate, status: OSStatus, restored: ShortcutCandidate?)

    var description: String {
        switch self {
        case let .registered(shortcut, status):
            return "registered \(shortcut.display) · OSStatus \(status)"
        case let .failed(candidate, status, restored):
            let fallback = restored.map { " · kept \($0.display) active" } ?? " · no active shortcut"
            return "FAILED \(candidate.display) · OSStatus \(status)\(fallback)"
        }
    }
}

private let hotKeySignature: OSType = 0x5054_5253 // PTRS
private let hotKeyIdentifier: UInt32 = 1
private let preferencesSuite = "dev.pointer.global-shortcut-prototype.PROTOTYPE-WIPE-ME"
private let persistedShortcutKey = "shortcut-id"

private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr,
          identifier.signature == hotKeySignature,
          identifier.id == hotKeyIdentifier else {
        return OSStatus(eventNotHandledErr)
    }

    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        delegate.receivedHotKey()
    }
    return noErr
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = UserDefaults(suiteName: preferencesSuite)!
    private var statusItem: NSStatusItem?
    private var diagnosticsWindow: NSWindow?
    private var proofPalette: NSPanel?
    private weak var candidatePicker: NSPopUpButton?
    private weak var stateLabel: NSTextField?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var activeShortcut: ShortcutCandidate?
    private var registrationState: RegistrationState?
    private var receivedCount = 0
    private var proofPaletteVisible = false
    private var verificationTimer: Timer?
    private var verificationStartCount: Int?
    private var verificationState = "not started"
    private var lastAction = "Prototype launched"

    func applicationDidFinishLaunching(_ notification: Notification) {
        installHotKeyEventHandler()
        makeStatusItem()
        makeProofPalette()
        makeDiagnosticsWindow()

        let persisted = ShortcutCandidate.candidate(
            id: preferences.string(forKey: persistedShortcutKey)
        )
        apply(persisted, persistOnSuccess: true)
        showDiagnostics()
    }

    func applicationWillTerminate(_ notification: Notification) {
        verificationTimer?.invalidate()
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func installHotKeyEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            context,
            &eventHandler
        )
        guard status == noErr else {
            registrationState = .failed(
                candidate: ShortcutCandidate.choices[0],
                status: status,
                restored: nil
            )
            log("event handler installation failed with OSStatus \(status)")
            return
        }
        log("Carbon application hot-key event handler installed")
    }

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "keyboard.badge.ellipsis",
            accessibilityDescription: "Pointer shortcut prototype"
        )
        item.button?.toolTip = "Pointer Shortcut PROTOTYPE"

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Diagnostics", action: #selector(showDiagnostics), keyEquivalent: "")
        menu.addItem(withTitle: "Show Proof Palette", action: #selector(showProofPalette), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Prototype", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func makeProofPalette() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 112),
            styleMask: [.titled, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Pointer activation proof"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let label = NSTextField(wrappingLabelWithString: "Global shortcut received. This palette was toggled without activating Pointer first.")
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
        panel.contentView = content
        proofPalette = panel
    }

    private func makeDiagnosticsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pointer — Global Shortcut PROTOTYPE"
        window.isReleasedWhenClosed = false

        let badge = NSTextField(labelWithString: "PROTOTYPE · Global shortcut contract")
        badge.font = .systemFont(ofSize: 12, weight: .bold)
        badge.textColor = .systemOrange

        let question = NSTextField(
            wrappingLabelWithString: "Can Pointer register, change, persist, and receive a global shortcut from another app without privacy permissions?"
        )
        question.font = .systemFont(ofSize: 17, weight: .semibold)

        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        for candidate in ShortcutCandidate.choices {
            picker.addItem(withTitle: candidate.title)
            picker.lastItem?.representedObject = candidate.id
        }
        candidatePicker = picker

        let applyButton = NSButton(title: "Apply candidate", target: self, action: #selector(applySelectedCandidate))
        let verifyButton = NSButton(title: "Start 5-second delivery test", target: self, action: #selector(startDeliveryTest))
        let hideButton = NSButton(title: "Hide proof palette", target: self, action: #selector(hideProofPalette))
        let buttons = NSStackView(views: [applyButton, verifyButton, hideButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let instructions = NSTextField(
            wrappingLabelWithString: "To prove global delivery: start the test, focus another application, and press the active chord. The small proof palette should toggle. A timeout means registration succeeded but delivery was not observed."
        )
        instructions.textColor = .secondaryLabelColor

        let state = NSTextField(wrappingLabelWithString: "")
        state.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        state.textColor = .secondaryLabelColor
        stateLabel = state

        let privacy = NSTextField(
            wrappingLabelWithString: "Prototype route: RegisterEventHotKey only — no AX, global event monitor, event tap, input synthesis, or screen capture."
        )
        privacy.font = .systemFont(ofSize: 12, weight: .medium)
        privacy.textColor = .systemGreen

        let stack = NSStackView(views: [badge, question, picker, buttons, instructions, state, privacy])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
            picker.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            instructions.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            state.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            privacy.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40)
        ])

        window.contentView = root
        window.center()
        diagnosticsWindow = window
    }

    private func selectedCandidate() -> ShortcutCandidate {
        let id = candidatePicker?.selectedItem?.representedObject as? String
        return ShortcutCandidate.candidate(id: id)
    }

    private func apply(_ candidate: ShortcutCandidate, persistOnSuccess: Bool) {
        verificationTimer?.invalidate()
        verificationState = "not started"

        guard let keyCode = candidate.keyCode else {
            registrationState = .failed(candidate: candidate, status: OSStatus(eventHotKeyInvalidErr), restored: activeShortcut)
            lastAction = "Rejected candidate before registration: a non-modifier key is required"
            log(lastAction)
            updateState()
            return
        }

        let previous = activeShortcut
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
            activeShortcut = nil
        }

        let attempt = register(keyCode: keyCode, modifiers: candidate.modifiers)
        if attempt.status == noErr, let reference = attempt.reference {
            hotKeyRef = reference
            activeShortcut = candidate
            registrationState = .registered(shortcut: candidate, status: attempt.status)
            lastAction = "Applied \(candidate.display)"
            if persistOnSuccess {
                preferences.set(candidate.id, forKey: persistedShortcutKey)
            }
            log("registered \(candidate.display) with OSStatus \(attempt.status)")
        } else {
            var restored: ShortcutCandidate?
            if let previous, let previousKeyCode = previous.keyCode {
                let rollback = register(keyCode: previousKeyCode, modifiers: previous.modifiers)
                if rollback.status == noErr, let reference = rollback.reference {
                    hotKeyRef = reference
                    activeShortcut = previous
                    restored = previous
                }
            }
            registrationState = .failed(candidate: candidate, status: attempt.status, restored: restored)
            lastAction = "Candidate registration failed; rollback attempted"
            log("registration failed for \(candidate.display) with OSStatus \(attempt.status); restored=\(restored?.display ?? "none")")
        }
        updateState()
    }

    private func register(keyCode: UInt32, modifiers: UInt32) -> (status: OSStatus, reference: EventHotKeyRef?) {
        let identifier = EventHotKeyID(signature: hotKeySignature, id: hotKeyIdentifier)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyNoOptions),
            &reference
        )
        return (status, reference)
    }

    func receivedHotKey() {
        receivedCount += 1
        verificationTimer?.invalidate()
        verificationTimer = nil
        verificationStartCount = nil
        verificationState = "DELIVERED at \(Date().formatted(date: .omitted, time: .standard))"
        lastAction = "Received global shortcut event #\(receivedCount)"
        toggleProofPalette()
        log(lastAction)
        updateState()
    }

    private func toggleProofPalette() {
        proofPaletteVisible.toggle()
        if proofPaletteVisible {
            showProofPalette()
        } else {
            hideProofPalette()
        }
    }

    private func updateState() {
        if let activeShortcut,
           let index = ShortcutCandidate.choices.firstIndex(of: activeShortcut) {
            candidatePicker?.selectItem(at: index)
        }
        let persisted = ShortcutCandidate.candidate(id: preferences.string(forKey: persistedShortcutKey))
        stateLabel?.stringValue = """
        active shortcut: \(activeShortcut?.display ?? "none")
        registration: \(registrationState?.description ?? "not attempted")
        delivery test: \(verificationState)
        received events: \(receivedCount)
        proof palette: \(proofPaletteVisible ? "visible" : "hidden")
        persisted shortcut: \(persisted.display)
        last: \(lastAction)
        """
    }

    private func log(_ message: String) {
        print("[GlobalShortcutPrototype] \(message)")
        fflush(stdout)
    }

    @objc private func applySelectedCandidate() {
        apply(selectedCandidate(), persistOnSuccess: true)
    }

    @objc private func startDeliveryTest() {
        guard let activeShortcut else {
            verificationState = "cannot test: no active shortcut"
            updateState()
            return
        }

        verificationTimer?.invalidate()
        verificationStartCount = receivedCount
        verificationState = "WAITING 5 seconds for \(activeShortcut.display)"
        lastAction = "Delivery test started; focus another app and press \(activeShortcut.display)"
        log(lastAction)
        updateState()

        verificationTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.receivedCount == self.verificationStartCount {
                    self.verificationState = "NO EVENT within 5 seconds — chord may be reserved or unavailable"
                    self.lastAction = "Delivery test timed out"
                    self.log(self.lastAction)
                    self.updateState()
                }
                self.verificationStartCount = nil
                self.verificationTimer = nil
            }
        }
    }

    @objc private func showDiagnostics() {
        diagnosticsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateState()
    }

    @objc private func showProofPalette() {
        proofPaletteVisible = true
        proofPalette?.center()
        proofPalette?.orderFrontRegardless()
        updateState()
    }

    @objc private func hideProofPalette() {
        proofPaletteVisible = false
        proofPalette?.orderOut(nil)
        updateState()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@main
@MainActor
private enum GlobalShortcutPrototype {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        _ = delegate
    }
}
