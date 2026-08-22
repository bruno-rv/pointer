import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class PointerApplicationControllerTests: XCTestCase {
    func testExplicitShowMovesAndClampsPaletteToPointerDisplay() throws {
        let fixture = ControllerFixture()
        let palette = try XCTUnwrap(fixture.palette)
        let display = fixture.provider.displays[0]

        fixture.controller.start()
        palette.window.setFrameOrigin(NSPoint(x: display.visibleFrame.x + 1_800, y: display.visibleFrame.y + 900))
        fixture.controller.showPalette()

        XCTAssertGreaterThanOrEqual(palette.window.frame.minX, display.visibleFrame.cgRect.minX)
        XCTAssertLessThanOrEqual(palette.window.frame.maxX, display.visibleFrame.cgRect.maxX)
        XCTAssertGreaterThanOrEqual(palette.window.frame.minY, display.visibleFrame.cgRect.minY)
        XCTAssertLessThanOrEqual(palette.window.frame.maxY, display.visibleFrame.cgRect.maxY)
    }

    func testNormalRefreshPreservesManualPaletteDrag() throws {
        let fixture = ControllerFixture()
        let palette = try XCTUnwrap(fixture.palette)

        fixture.controller.start()
        palette.window.setFrameOrigin(NSPoint(x: 240, y: 180))
        let manualOrigin = palette.window.frame.origin

        fixture.controller.refresh()

        XCTAssertEqual(palette.window.frame.origin, manualOrigin)
    }

    func testScreenParameterChangesResynchronizeDisplaysUntilControllerStops() throws {
        let fixture = ControllerFixture()
        fixture.controller.start()
        let uuid = fixture.provider.displays[0].uuid
        let overlay = try XCTUnwrap(fixture.coordinator.overlays[uuid] as? ControllerTestOverlay)
        let changed = DisplayDescriptor(
            uuid: uuid,
            frame: DisplayFrame(x: 40, y: 12, width: 640, height: 480),
            visibleFrame: DisplayFrame(x: 40, y: 24, width: 640, height: 468),
            scaleFactor: 1
        )

        fixture.provider.displays = [changed]
        fixture.notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        XCTAssertEqual(overlay.display, changed)

        fixture.provider.displays = []
        fixture.notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        XCTAssertNil(fixture.coordinator.overlays[uuid])

        fixture.provider.displays = [changed]
        fixture.notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        let reconnected = try XCTUnwrap(
            fixture.coordinator.overlays[uuid] as? ControllerTestOverlay
        )
        XCTAssertEqual(reconnected.display, changed)

        fixture.controller.stop()
        let disconnected = DisplayDescriptor(
            uuid: uuid,
            frame: DisplayFrame(x: 200, y: 12, width: 320, height: 240),
            visibleFrame: DisplayFrame(x: 200, y: 24, width: 320, height: 228),
            scaleFactor: 1
        )
        fixture.provider.displays = [disconnected]
        fixture.notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        XCTAssertEqual(overlay.display, changed)
    }
}

@MainActor
private final class ControllerFixture {
    let notificationCenter = NotificationCenter()
    let provider: ControllerTestScreenProvider
    let coordinator: DisplayCoordinator
    let router: CommandRouter
    let palette: PalettePanel?
    let controller: PointerApplicationController

    init() {
        let uuid = DisplayUUID(rawValue: "display-a")
        let descriptor = DisplayDescriptor(
            uuid: uuid,
            frame: DisplayFrame(x: 0, y: 0, width: 800, height: 600),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 800, height: 576),
            scaleFactor: 2
        )
        provider = ControllerTestScreenProvider(displays: [descriptor])
        coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { ControllerTestOverlay(display: $0) }
        )
        router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        palette = PalettePanel(router: router)
        controller = PointerApplicationController(
            screenProvider: provider,
            displayCoordinator: coordinator,
            commandRouter: router,
            palette: palette,
            menuBar: nil,
            shortcutController: nil,
            notificationCenter: notificationCenter
        )
    }
}

@MainActor
private final class ControllerTestScreenProvider: ScreenProviding {
    var displays: [DisplayDescriptor]

    init(displays: [DisplayDescriptor]) {
        self.displays = displays
    }

    func currentDisplays() -> [DisplayDescriptor] { displays }
    func pointerDisplay() -> DisplayUUID? { displays.first?.uuid }
}

@MainActor
private final class ControllerTestOverlay: OverlayPresenting {
    var display: DisplayDescriptor

    init(display: DisplayDescriptor) { self.display = display }
    func update(display: DisplayDescriptor) { self.display = display }
    func update(session: PointerSession) {}
    func setMode(_ mode: PointerMode) {}
    func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {}
    func close() {}
}
