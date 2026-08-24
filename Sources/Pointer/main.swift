import Darwin
import Foundation
import PointerAppKit

@MainActor
private final class LauncherFirstUseGuideStateStore: FirstUseGuideStateStoring {
    var hasDismissedFirstUseGuide: Bool { false }

    func markFirstUseGuideDismissed() {}
}

@MainActor
private final class LauncherFirstUseGuide: FirstUseGuidePresenting {
    let placementProvider: any GuidePlacementProviding

    init(placementProvider: any GuidePlacementProviding) {
        self.placementProvider = placementProvider
    }

    var isVisible: Bool { false }

    func showIfNeeded(in _: GuidePlacementContext) {}
    func show(in _: GuidePlacementContext) {}
    func dismiss() {}
    func hideForDisplayLoss() {}
    func restoreAfterDisplayLoss(in _: GuidePlacementContext) {}
    func hideForApplicationStop() {}

    func consumeEscape() -> Bool { false }
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--benchmark-gestures") {
    guard arguments == ["--benchmark-gestures", "--format", "json"] else {
        fputs("Pointer: usage: Pointer --benchmark-gestures --format json\n", stderr)
        exit(EXIT_FAILURE)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
        let data = try encoder.encode(GestureBenchmark.run())
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    } catch {
        fputs("Pointer: could not encode gesture benchmark report: \(error)\n", stderr)
        exit(EXIT_FAILURE)
    }
} else if arguments.contains("--smoke") {
    let formatIndex = arguments.firstIndex(of: "--format")
    guard let formatIndex,
          formatIndex + 1 < arguments.count,
          arguments[formatIndex + 1] == "json" else {
        fputs("Pointer: smoke mode requires --format json\n", stderr)
        exit(EXIT_FAILURE)
    }

    var displays: [SmokeRunner.Display] = []
    var index = 0
    while index < arguments.count {
        if arguments[index] == "--display" {
            let valueIndex = index + 1
            guard valueIndex < arguments.count,
                  let display = SmokeRunner.Display(rawValue: arguments[valueIndex]) else {
                fputs("Pointer: --display requires built-in or external\n", stderr)
                exit(EXIT_FAILURE)
            }
            displays.append(display)
            index += 2
        } else {
            index += 1
        }
    }
    if displays.isEmpty {
        displays = SmokeRunner.defaultDisplays
    }

    do {
        let data = try SmokeRunner.json(displays: displays)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    } catch {
        fputs("Pointer: could not encode smoke report: \(error)\n", stderr)
        exit(EXIT_FAILURE)
    }
} else {
    MainActor.assumeIsolated {
        let application = PointerApplication.shared as! PointerApplication
        // Temporary bootstrap: F's composition root replaces this after D's concrete guide lands.
        let screenProvider = NSScreenProvider()
        let displayCoordinator = DisplayCoordinator(screenProvider: screenProvider)
        let hotKeyRegistrar = CarbonHotKeyRegistrar()
        let shortcutStore = UserDefaultsShortcutStore(
            userDefaults: UserDefaults.standard,
            key: "pointer.shortcut-preset"
        )
        let shortcutScheduler = DispatchShortcutScheduler()
        let shortcutController = HotKeyController(
            registrar: hotKeyRegistrar,
            store: shortcutStore,
            scheduler: shortcutScheduler
        )
        let commandRouter = CommandRouter(
            coordinator: displayCoordinator,
            screenProvider: screenProvider,
            shortcutController: shortcutController
        )
        let guidePlacementProvider = GuidePlacementProvider()
        let palette = PalettePanel(
            router: commandRouter,
            guidePlacementProvider: guidePlacementProvider
        )
        let menuBar = MenuBarController(
            router: commandRouter,
            shortcutController: shortcutController
        )
        let controlMetadataProvider = ControlMetadataInventory(
            palette: palette,
            menuBar: menuBar
        )
        let guideStateStore = LauncherFirstUseGuideStateStore()
        let guide = LauncherFirstUseGuide(
            placementProvider: guidePlacementProvider
        )
        let controller = PointerApplicationController(
            screenProvider: screenProvider,
            displayCoordinator: displayCoordinator,
            commandRouter: commandRouter,
            palette: palette,
            menuBar: menuBar,
            shortcutController: shortcutController,
            guide: guide,
            guideStateStore: guideStateStore,
            controlMetadataProvider: controlMetadataProvider,
            guidePlacementProvider: guidePlacementProvider,
            notificationCenter: NotificationCenter.default
        )
        application.commandRouter = commandRouter
        application.localKeyRouter = commandRouter
        application.firstUseGuide = guide
        application.delegate = controller
        application.setActivationPolicy(.accessory)
        let retainedObjects: [AnyObject] = [
            screenProvider,
            displayCoordinator,
            hotKeyRegistrar,
            shortcutStore,
            shortcutScheduler,
            shortcutController,
            commandRouter,
            guidePlacementProvider,
            palette,
            menuBar,
            controlMetadataProvider,
            guideStateStore,
            guide,
            controller
        ]
        withExtendedLifetime(retainedObjects) {
            application.run()
        }
    }
}
