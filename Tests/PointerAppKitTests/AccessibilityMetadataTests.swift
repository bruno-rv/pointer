import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class AccessibilityMetadataTests: XCTestCase {
    func testPaletteAndMenuMetadataIsCompleteAndKeyboardReachable() throws {
        let provider = AccessibilityScreenProvider()
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { OverlayPanel(descriptor: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: GuidePlacementProvider()
        )
        let menuBar = MenuBarController(router: router)
        menuBar.install()
        defer { menuBar.remove() }

        _ = coordinator.synchronize()
        coordinator.apply(.append(
            Mark(
                geometry: .arrow(
                    start: NormalizedPoint(x: 0.1, y: 0.1),
                    end: NormalizedPoint(x: 0.8, y: 0.8)
                ),
                style: .default
            ),
            to: provider.displayUUID
        ))
        palette.paletteViewController.loadViewIfNeeded()
        palette.refresh(session: coordinator.session)
        let metadata = ControlMetadataInventory(palette: palette, menuBar: menuBar).metadata()

        XCTAssertEqual(metadata.first?.identifier, "palette.mode")
        XCTAssertTrue(metadata.allSatisfy {
            !$0.identifier.isEmpty
                && !$0.accessibleName.isEmpty
                && $0.help?.isEmpty == false
                && !$0.role.isEmpty
        })

        let paletteMetadata = metadata.filter { $0.identifier.hasPrefix("palette.") }
        let keyboardPaletteMetadata = paletteMetadata.filter(\.isKeyboardReachable)
        XCTAssertEqual(keyboardPaletteMetadata.first?.identifier, "palette.mode")
        XCTAssertTrue(keyboardPaletteMetadata.contains { $0.identifier == "palette.tool.arrow" })
        XCTAssertTrue(keyboardPaletteMetadata.contains { $0.identifier == "palette.style.opacity" })
        XCTAssertTrue(keyboardPaletteMetadata.contains { $0.identifier == "palette.undo" })
        XCTAssertTrue(keyboardPaletteMetadata.contains { $0.identifier == "palette.clear" })
        for identifier in [
            "palette.mode",
            "palette.tool.arrow",
            "palette.style.stroke-width",
            "palette.style.opacity",
            "palette.spotlight.radius",
            "palette.tools.overflow",
        ] {
            let row = try XCTUnwrap(metadata.first { $0.identifier == identifier })
            XCTAssertNotNil(row.value, identifier)
        }

        let menuMetadata = metadata.filter { $0.identifier.hasPrefix("menu.") }
        XCTAssertFalse(menuMetadata.isEmpty)
        XCTAssertTrue(
            menuMetadata.filter(\.isEnabled).allSatisfy(\.isKeyboardReachable),
            "Unexpected menu keyboard metadata: \(menuMetadata)"
        )

        let controls = palette.paletteViewController.controls
        XCTAssertEqual(
            Set(controls.compactMap { $0.identifier?.rawValue }).count,
            controls.count
        )
        XCTAssertTrue(controls.allSatisfy { $0.focusRingType != .none })
        XCTAssertTrue(controls.allSatisfy { $0.isAccessibilityElement() })
        XCTAssertEqual(
            controls.filter { $0.identifier?.rawValue == "palette.mode" }.count,
            1
        )
    }

    func testSelectedDisabledAndErrorStatesHaveNonColorAccessibleCues() throws {
        let provider = AccessibilityScreenProvider()
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { OverlayPanel(descriptor: $0) }
        )
        let shortcutController = HotKeyController(
            registrar: AccessibilityFailingHotKeyRegistrar(),
            store: AccessibilityShortcutStore(),
            scheduler: AccessibilityShortcutScheduler()
        )
        let router = CommandRouter(
            coordinator: coordinator,
            screenProvider: provider,
            shortcutController: shortcutController
        )
        let controller = PaletteViewController(router: router)
        controller.loadViewIfNeeded()

        var session = router.session
        session.apply(.setMode(.annotation))
        session.apply(.setTool(.arrow))
        controller.refresh(session: session)

        let mode = controller.control(identifier: "palette.mode")
        let arrow = controller.control(identifier: "palette.tool.arrow")
        let spotlight = controller.control(identifier: "palette.spotlight.radius")
        XCTAssertEqual(mode.accessibilityValue() as? String, "On")
        XCTAssertEqual(arrow.accessibilityValue() as? String, "Selected")
        XCTAssertFalse(spotlight.isEnabled)
        XCTAssertTrue((spotlight.accessibilityHelp() ?? "").contains("Spotlight"))

        shortcutController.start()
        controller.refresh(session: router.session)
        XCTAssertTrue(controller.statusMessage.hasPrefix("Shortcut unavailable:"))
    }
}

@MainActor
private final class AccessibilityScreenProvider: ScreenProviding {
    let displayUUID = DisplayUUID(rawValue: "accessibility-display")
    private let display = DisplayDescriptor(
        uuid: DisplayUUID(rawValue: "accessibility-display"),
        frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
        visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
        scaleFactor: 2
    )

    func currentDisplays() -> [DisplayDescriptor] { [display] }
    func pointerDisplay() -> DisplayUUID? { display.uuid }
}

@MainActor
private final class AccessibilityFailingHotKeyRegistrar: HotKeyRegistering {
    var onEvent: ((HotKeyToken) -> Void)?

    func register(_ preset: ShortcutPreset) throws -> HotKeyToken {
        throw AccessibilityHotKeyError.registrationFailed
    }

    func unregister(_ token: HotKeyToken) {}
}

private enum AccessibilityHotKeyError: Error {
    case registrationFailed
}

@MainActor
private final class AccessibilityShortcutStore: ShortcutStoring {
    func load() -> ShortcutPreset? { nil }
    func save(_ preset: ShortcutPreset) {}
}

@MainActor
private final class AccessibilityShortcutScheduler: ShortcutScheduling {
    var activeTimerCount: Int { 0 }

    @discardableResult
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> ShortcutScheduleToken {
        fatalError("A failed shortcut registration does not schedule a timer")
    }

    func cancel(_ token: ShortcutScheduleToken) {}
}
