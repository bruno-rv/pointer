import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class PointerApplicationControllerTests: XCTestCase {
    func testExplicitShowMovesAndClampsPaletteToPointerDisplay() throws {
        let fixture = ControllerFixture()
        let palette = fixture.palette
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
        let palette = fixture.palette

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

    func testStopClearsControllerCallbacksAndRestartRebindsEachOnce() {
        let fixture = ControllerFixture()

        fixture.controller.start()
        XCTAssertNotNil(fixture.coordinator.onDisplaySync)
        XCTAssertNotNil(fixture.router.onStateChange)

        fixture.controller.stop()
        XCTAssertNil(fixture.coordinator.onDisplaySync)
        XCTAssertNil(fixture.router.onStateChange)

        fixture.controller.start()
        XCTAssertNotNil(fixture.coordinator.onDisplaySync)
        XCTAssertNotNil(fixture.router.onStateChange)
    }

    func testClearAllCallbackRunsOnceBeforeAndAfterRestartAndNotWhileStopped() throws {
        let fixture = ControllerFixture { router in
            ControllerTestMenuBar(router: router)
        }
        let menuBar = try XCTUnwrap(fixture.menuBar as? ControllerTestMenuBar)

        fixture.controller.start()
        menuBar.requestClearAll()
        XCTAssertEqual(menuBar.confirmationCount, 1)
        XCTAssertEqual(menuBar.commandCount, 1)

        fixture.controller.stop()
        menuBar.requestClearAll()
        XCTAssertEqual(menuBar.confirmationCount, 1)
        XCTAssertEqual(menuBar.commandCount, 1)

        fixture.controller.start()
        menuBar.requestClearAll()
        XCTAssertEqual(menuBar.confirmationCount, 2)
        XCTAssertEqual(menuBar.commandCount, 2)
    }

    func testSelectionFeedbackCallbackSurvivesControllerStopAndRestart() throws {
        let fixture = SelectionControllerFixture()
        var feedback: [String] = []
        let existingFeedback = fixture.router.onFeedback
        fixture.router.onFeedback = { message in
            feedback.append(message)
            existingFeedback?(message)
        }

        fixture.controller.start()
        try fixture.selectAndClear()
        fixture.controller.stop()
        fixture.controller.start()
        try fixture.selectAndClear()

        XCTAssertEqual(feedback, ["Selection cleared", "Selection cleared"])
    }
}

@MainActor
private final class ControllerFixture {
    let notificationCenter = NotificationCenter()
    let provider: ControllerTestScreenProvider
    let coordinator: DisplayCoordinator
    let router: CommandRouter
    let menuBar: (any MenuBarPresenting)?
    let palette: PalettePanel
    let placementProvider: GuideTestPlacementProvider
    let guide: GuideTestSpyGuide
    let guideStateStore: GuideTestStateStore
    let shortcutController: HotKeyController
    let controller: PointerApplicationController

    init(_ menuBarFactory: ((CommandRouter) -> any MenuBarPresenting)? = nil) {
        let uuid = DisplayUUID(rawValue: "display-a")
        let descriptor = DisplayDescriptor(
            uuid: uuid,
            frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
            scaleFactor: 2
        )
        provider = ControllerTestScreenProvider(displays: [descriptor])
        coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { ControllerTestOverlay(display: $0) }
        )
        router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        menuBar = menuBarFactory?(router)
        placementProvider = GuideTestPlacementProvider(eventLog: GuideTestEventLog())
        palette = PalettePanel(router: router, guidePlacementProvider: placementProvider)
        guide = GuideTestSpyGuide(
            placementProvider: placementProvider,
            eventLog: GuideTestEventLog()
        )
        guideStateStore = GuideTestStateStore()
        let stateStore = guideStateStore
        guide.onVisible = { stateStore.markFirstUseGuideDismissed() }
        let registrar = GuideTestHotKeyRegistrar()
        shortcutController = HotKeyController(
            registrar: registrar,
            store: GuideTestShortcutStore(),
            scheduler: GuideTestShortcutScheduler()
        )
        controller = PointerApplicationController(
            screenProvider: provider,
            displayCoordinator: coordinator,
            commandRouter: router,
            palette: palette,
            menuBar: menuBar,
            shortcutController: shortcutController,
            guide: guide,
            guideStateStore: guideStateStore,
            controlMetadataProvider: ControlMetadataInventory(palette: palette, menuBar: nil),
            guidePlacementProvider: placementProvider,
            notificationCenter: notificationCenter
        )
    }
}

@MainActor
private final class ControllerTestMenuBar: MenuBarPresenting {
    private let router: CommandRouter
    private var callbacksBound = false
    private var onShowPalette: (() -> Void)?
    private var onLearnPointer: (() -> Void)?
    private(set) var confirmationCount = 0
    private(set) var commandCount = 0

    init(router: CommandRouter) {
        self.router = router
    }

    func install() {}
    func refresh(session: PointerSession) {}
    func remove() {}

    @discardableResult
    func bindCallbacks(
        onShowPalette: (() -> Void)?,
        onLearnPointer: (() -> Void)?
    ) -> Int {
        self.onShowPalette = onShowPalette
        self.onLearnPointer = onLearnPointer
        callbacksBound = true
        router.onClearAllRequested = { [weak self] in
            guard let self, self.callbacksBound else { return }
            self.confirmationCount += 1
            self.commandCount += 1
            self.router.confirmClearAll()
        }
        return (onShowPalette == nil ? 0 : 1)
            + (onLearnPointer == nil ? 0 : 1)
    }

    func clearCallbacks() {
        callbacksBound = false
        onShowPalette = nil
        onLearnPointer = nil
        router.onClearAllRequested = nil
    }

    func requestClearAll() {
        router.route(.clearAll)
    }
}

@MainActor
private final class SelectionControllerFixture {
    let uuid = DisplayUUID(rawValue: "selection-controller-display")
    let provider: ControllerTestScreenProvider
    let coordinator: DisplayCoordinator
    let router: CommandRouter
    let palette: PalettePanel
    let placementProvider: GuideTestPlacementProvider
    let guide: GuideTestSpyGuide
    let guideStateStore = GuideTestStateStore()
    let shortcutController: HotKeyController
    let controller: PointerApplicationController

    init() {
        let descriptor = DisplayDescriptor(
            uuid: uuid,
            frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
            scaleFactor: 2
        )
        provider = ControllerTestScreenProvider(displays: [descriptor])
        coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { OverlayPanel(descriptor: $0) }
        )
        router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        placementProvider = GuideTestPlacementProvider(eventLog: GuideTestEventLog())
        palette = PalettePanel(router: router, guidePlacementProvider: placementProvider)
        guide = GuideTestSpyGuide(
            placementProvider: placementProvider,
            eventLog: GuideTestEventLog()
        )
        let stateStore = guideStateStore
        guide.onVisible = { stateStore.markFirstUseGuideDismissed() }
        let registrar = GuideTestHotKeyRegistrar()
        shortcutController = HotKeyController(
            registrar: registrar,
            store: GuideTestShortcutStore(),
            scheduler: GuideTestShortcutScheduler()
        )
        controller = PointerApplicationController(
            screenProvider: provider,
            displayCoordinator: coordinator,
            commandRouter: router,
            palette: palette,
            menuBar: nil,
            shortcutController: shortcutController,
            guide: guide,
            guideStateStore: guideStateStore,
            controlMetadataProvider: ControlMetadataInventory(palette: palette, menuBar: nil),
            guidePlacementProvider: placementProvider,
            notificationCenter: NotificationCenter()
        )
    }

    func selectAndClear() throws {
        let mark = Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.1),
                end: NormalizedPoint(x: 0.8, y: 0.8)
            ),
            style: .default
        )
        router.route(.setMode(.annotation))
        coordinator.apply(.append(mark, to: uuid))
        router.route(.setTool(.select))
        let overlay = try XCTUnwrap(coordinator.overlays[uuid] as? OverlayPanel)
        overlay.canvasView.beginGesture(at: NSPoint(x: 960, y: 540))
        overlay.canvasView.endGesture()
        overlay.canvasView.beginGesture(at: NSPoint(x: 10, y: 10))
        overlay.canvasView.endGesture()
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
