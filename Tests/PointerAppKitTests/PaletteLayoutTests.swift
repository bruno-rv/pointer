import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class PaletteLayoutTests: XCTestCase {
    func testNarrowLayoutKeepsAllEightToolsReachableThroughOverflow() {
        let plan = PaletteLayout.plan(availableWidth: 220)

        let visibleTools = Set(plan.rows.flatMap { row in
            row.compactMap { item -> PointerTool? in
                guard case let .tool(tool) = item else { return nil }
                return tool
            }
        })
        let reachableTools = visibleTools.union(plan.overflowTools)

        XCTAssertTrue(plan.usesOverflow)
        XCTAssertEqual(reachableTools, Set(PointerTool.allCases))
        XCTAssertFalse(plan.overflowTools.isEmpty)
    }

    func testWideLayoutUsesTwoRowsWithoutOverflow() {
        let plan = PaletteLayout.plan(availableWidth: 760)

        XCTAssertEqual(plan.rows.count, 2)
        XCTAssertFalse(plan.usesOverflow)
        XCTAssertEqual(
            Set(plan.rows.flatMap { $0 }.compactMap { item -> PointerTool? in
                guard case let .tool(tool) = item else { return nil }
                return tool
            }),
            Set(PointerTool.allCases)
        )
    }

    func testEveryPaletteControlHasLabelHelpIdentifierAndEnabledState() {
        let router = makeRouter()
        let viewController = PaletteViewController(router: router)
        viewController.loadViewIfNeeded()

        XCTAssertFalse(viewController.controls.isEmpty)
        for control in viewController.controls {
            XCTAssertTrue(control.isAccessibilityElement())
            XCTAssertFalse((control.accessibilityLabel() ?? "").isEmpty)
            XCTAssertFalse((control.accessibilityHelp() ?? "").isEmpty)
            XCTAssertFalse(control.identifier?.rawValue.isEmpty ?? true)
            _ = control.isEnabled
        }
    }

    func testUndoAndClearAreMomentaryCommandButtons() {
        let viewController = PaletteViewController(router: makeRouter())
        viewController.loadViewIfNeeded()

        for identifier in ["palette.undo", "palette.clear"] {
            let button = viewController.controls
                .compactMap { $0 as? NSButton }
                .first { $0.identifier?.rawValue == identifier }
            XCTAssertNotNil(button, identifier)
            XCTAssertEqual(viewController.buttonType(for: identifier), .momentaryPushIn, identifier)
            XCTAssertEqual(button?.accessibilityLabel(), identifier == "palette.undo"
                ? "Undo last pointer-display change"
                : "Clear pointer display", identifier)
        }
    }

    @MainActor
    func testPaletteRecomputesLayoutAfterNarrowContentWidth() {
        let router = makeRouter()
        let placementProvider = GuidePlacementProvider()
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: placementProvider
        )
        XCTAssertTrue(palette.guidePlacementProvider === placementProvider)
        let descriptor = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "display-a"),
            frame: DisplayFrame(x: 0, y: 0, width: 220, height: 600),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 220, height: 576),
            scaleFactor: 2
        )

        palette.show(on: descriptor)
        palette.window.contentView?.layoutSubtreeIfNeeded()

        let plan = palette.paletteViewController.layoutPlan
        let visibleTools = plan.rows.flatMap { $0 }.compactMap { item -> PointerTool? in
            guard case let .tool(tool) = item else { return nil }
            return tool
        }
        XCTAssertTrue(plan.usesOverflow)
        XCTAssertEqual(Set(visibleTools).union(plan.overflowTools), Set(PointerTool.allCases))
    }

    func testPaletteWindowStaysAboveInteractiveOverlayAfterBothAreShown() {
        let descriptor = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "display-a"),
            frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
            scaleFactor: 2
        )
        let overlay = OverlayPanel(descriptor: descriptor)
        let placementProvider = GuidePlacementProvider()
        let palette = PalettePanel(
            router: makeRouter(),
            guidePlacementProvider: placementProvider
        )
        XCTAssertTrue(palette.guidePlacementProvider === placementProvider)
        defer {
            palette.close()
            overlay.close()
        }

        overlay.show()
        palette.show(on: descriptor)

        XCTAssertGreaterThan(palette.level.rawValue, overlay.level.rawValue)
    }

    private func makeRouter() -> CommandRouter {
        let uuid = DisplayUUID(rawValue: "display-a")
        let descriptor = DisplayDescriptor(
            uuid: uuid,
            frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
            scaleFactor: 2
        )
        let provider = PaletteTestScreenProvider(displays: [descriptor])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteTestOverlay(display: $0) }
        )
        return CommandRouter(coordinator: coordinator, screenProvider: provider)
    }
}

@MainActor
private final class PaletteTestScreenProvider: ScreenProviding {
    let displays: [DisplayDescriptor]

    init(displays: [DisplayDescriptor]) {
        self.displays = displays
    }

    func currentDisplays() -> [DisplayDescriptor] { displays }
    func pointerDisplay() -> DisplayUUID? { displays.first?.uuid }
}

@MainActor
private final class PaletteTestOverlay: OverlayPresenting {
    var display: DisplayDescriptor

    init(display: DisplayDescriptor) {
        self.display = display
    }

    func update(display: DisplayDescriptor) { self.display = display }
    func update(session: PointerSession) {}
    func setMode(_ mode: PointerMode) {}
    func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {}
    func close() {}
}
