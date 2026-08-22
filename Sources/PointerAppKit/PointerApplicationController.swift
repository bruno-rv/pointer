import AppKit
import PointerCore

@MainActor
public final class PointerApplicationController: NSObject, NSApplicationDelegate {
    public let screenProvider: any ScreenProviding
    public let displayCoordinator: DisplayCoordinator
    public let commandRouter: CommandRouter
    public let palette: any PalettePresenting
    public let menuBar: (any MenuBarPresenting)?
    public let shortcutController: HotKeyController?

    private var started = false
    private let notificationCenter: NotificationCenter
    private var screenParametersObserver: NSObjectProtocol?

    public init(
        screenProvider: any ScreenProviding,
        displayCoordinator: DisplayCoordinator? = nil,
        commandRouter: CommandRouter? = nil,
        palette: (any PalettePresenting)? = nil,
        menuBar: (any MenuBarPresenting)? = nil,
        shortcutController: HotKeyController? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.screenProvider = screenProvider
        let coordinator = displayCoordinator ?? DisplayCoordinator(screenProvider: screenProvider)
        self.displayCoordinator = coordinator
        let router = commandRouter ?? CommandRouter(
            coordinator: coordinator,
            screenProvider: screenProvider,
            shortcutController: shortcutController
        )
        self.commandRouter = router
        self.palette = palette ?? PalettePanel(router: router)
        self.menuBar = menuBar
        self.shortcutController = shortcutController
        self.notificationCenter = notificationCenter
        super.init()

        router.onStateChange = { [weak self] session in
            self?.refresh(session: session)
        }
    }

    public convenience override init() {
        let provider = NSScreenProvider()
        let coordinator = DisplayCoordinator(screenProvider: provider)
        let shortcut = HotKeyController(
            registrar: CarbonHotKeyRegistrar(),
            store: UserDefaultsShortcutStore()
        )
        let router = CommandRouter(
            coordinator: coordinator,
            screenProvider: provider,
            shortcutController: shortcut
        )
        let palette = PalettePanel(router: router)
        let menu = MenuBarController(router: router, shortcutController: shortcut)
        self.init(
            screenProvider: provider,
            displayCoordinator: coordinator,
            commandRouter: router,
            palette: palette,
            menuBar: menu,
            shortcutController: shortcut
        )
    }

    public func start() {
        guard !started else { return }
        started = true

        shortcutController?.onToggle = { [weak self] in
            self?.commandRouter.route(.toggleMode)
        }
        shortcutController?.start()
        screenParametersObserver = notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.displayCoordinator.synchronize()
                self.refresh(session: self.displayCoordinator.session)
            }
        }
        menuBar?.install()
        if let menuBar = menuBar as? MenuBarController {
            menuBar.onShowPalette = { [weak self] in
                self?.showPalette()
            }
        }

        displayCoordinator.synchronize()
        refresh(session: displayCoordinator.session)
        showPalette()
    }

    public func stop() {
        guard started else { return }
        started = false
        if let screenParametersObserver {
            notificationCenter.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
        shortcutController?.stop()
        palette.hide()
        menuBar?.remove()
    }

    public func refresh() {
        refresh(session: displayCoordinator.session)
    }

    public func showPalette() {
        let displays = screenProvider.currentDisplays()
        guard !displays.isEmpty else { return }
        let pointer = screenProvider.pointerDisplay()
        let descriptor = displays.first { $0.uuid == pointer } ?? displays[0]
        palette.show(on: descriptor)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stop()
        return .terminateNow
    }

    private func refresh(session: PointerSession) {
        palette.refresh(session: session)
        menuBar?.refresh(session: session)
    }
}
