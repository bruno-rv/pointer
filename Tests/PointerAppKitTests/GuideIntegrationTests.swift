import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class GuideIntegrationTests: XCTestCase {
    func testStartupShowsPaletteBeforeFirstUseGuide() {
        let fixture = GuideControllerFixture()

        fixture.controller.start()

        XCTAssertEqual(fixture.events, ["palette.show", "guide.showIfNeeded"])
        XCTAssertTrue(fixture.guide.isVisible)
    }

    func testZeroDisplayStartupDefersGuideAndFirstReconnectRetriesInOrder() {
        let fixture = GuideControllerFixture(displays: [])

        fixture.controller.start()

        XCTAssertEqual(fixture.events, [])
        fixture.provider.displays = [fixture.display]
        fixture.postScreenChange()

        XCTAssertEqual(fixture.events, ["palette.show", "guide.showIfNeeded"])
    }

    func testDismissedFirstUseAtZeroDisplayDoesNotRetryAfterReconnect() {
        let fixture = GuideControllerFixture(displays: [])
        fixture.guideStateStore.markFirstUseGuideDismissed()

        fixture.controller.start()
        XCTAssertEqual(fixture.events, [])

        fixture.provider.displays = [fixture.display]
        fixture.postScreenChange()

        XCTAssertEqual(fixture.events, ["palette.show"])
    }

    func testPendingFirstUsePaletteFailureHidesAndRestoresAfterDisplayLoss() {
        let fixture = GuideControllerFixture(
            displays: [GuideTestScreenProvider.narrowDisplay]
        )

        fixture.controller.start()
        XCTAssertEqual(fixture.events, [])
        XCTAssertFalse(fixture.guide.isVisible)

        fixture.provider.displays = []
        fixture.postScreenChange()
        XCTAssertEqual(fixture.events, ["guide.hideForDisplayLoss"])
        XCTAssertFalse(fixture.guide.isVisible)
        XCTAssertEqual(fixture.guideStateStore.markCount, 0)

        fixture.provider.displays = [fixture.display]
        fixture.postScreenChange()
        XCTAssertEqual(
            fixture.events,
            ["guide.hideForDisplayLoss", "palette.show", "guide.restoreAfterDisplayLoss"]
        )
        XCTAssertTrue(fixture.guide.isVisible)
    }

    func testVisibleGuideConsumesEscapeBeforeCommandRouter() {
        let guide = GuideTestSpyGuide(placementProvider: GuidePlacementProvider(), visible: true)
        let provider = GuideTestScreenProvider(displays: [])
        let coordinator = DisplayCoordinator(screenProvider: provider)
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)

        let consumed = PointerApplication.routeLocalEvent(
            keyDown(keyCode: 53),
            guide: guide,
            localRouter: router,
            commandRouter: router
        )

        XCTAssertTrue(consumed)
        XCTAssertEqual(guide.consumeEscapeCount, 1)
        XCTAssertNil(router.lastHandledCommand)
        XCTAssertFalse(guide.isVisible)
    }

    func testVisibleGuideDoesNotConsumeReturnBeforeLocalRouter() {
        let guide = GuideTestSpyGuide(placementProvider: GuidePlacementProvider(), visible: true)
        let localRouter = GuideTestLocalRouter(result: true)

        let consumed = PointerApplication.routeLocalEvent(
            keyDown(keyCode: 36),
            guide: guide,
            localRouter: localRouter,
            commandRouter: nil
        )

        XCTAssertTrue(consumed)
        XCTAssertEqual(guide.consumeEscapeCount, 0)
        XCTAssertEqual(localRouter.callCount, 1)
        XCTAssertTrue(guide.isVisible)
    }

    func testVisibleGuideDoesNotConsumeMouseEventAndLocalRouterControlsConsumption() {
        let guide = GuideTestSpyGuide(placementProvider: GuidePlacementProvider(), visible: true)
        let unhandledLocalRouter = GuideTestLocalRouter(result: false)

        let unconsumed = PointerApplication.routeLocalEvent(
            mouseDown(),
            guide: guide,
            localRouter: unhandledLocalRouter,
            commandRouter: nil
        )

        XCTAssertFalse(unconsumed)
        XCTAssertEqual(guide.consumeEscapeCount, 0)
        XCTAssertEqual(unhandledLocalRouter.callCount, 1)
        XCTAssertTrue(guide.isVisible)

        let handledLocalRouter = GuideTestLocalRouter(result: true)
        let consumed = PointerApplication.routeLocalEvent(
            mouseDown(),
            guide: guide,
            localRouter: handledLocalRouter,
            commandRouter: nil
        )

        XCTAssertTrue(consumed)
        XCTAssertEqual(guide.consumeEscapeCount, 0)
        XCTAssertEqual(handledLocalRouter.callCount, 1)
        XCTAssertTrue(guide.isVisible)
    }

    func testHiddenGuideLetsInjectedLocalRouterHandleBeforeCommandFallback() {
        let guide = GuideTestSpyGuide(placementProvider: GuidePlacementProvider())
        let provider = GuideTestScreenProvider(displays: [])
        let coordinator = DisplayCoordinator(screenProvider: provider)
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let localRouter = GuideTestLocalRouter(result: true)

        let consumed = PointerApplication.routeLocalEvent(
            keyDown(keyCode: 6),
            guide: guide,
            localRouter: localRouter,
            commandRouter: router
        )

        XCTAssertTrue(consumed)
        XCTAssertEqual(localRouter.callCount, 1)
        XCTAssertNil(router.lastHandledCommand)
    }

    func testLocalRouterFalseDoesNotInvokeCommandFallback() {
        let guide = GuideTestSpyGuide(placementProvider: GuidePlacementProvider())
        let provider = GuideTestScreenProvider(displays: [])
        let coordinator = DisplayCoordinator(screenProvider: provider)
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let localRouter = GuideTestLocalRouter(result: false)

        let consumed = PointerApplication.routeLocalEvent(
            keyDown(keyCode: 53),
            guide: guide,
            localRouter: localRouter,
            commandRouter: router
        )

        XCTAssertFalse(consumed)
        XCTAssertEqual(localRouter.callCount, 1)
        XCTAssertNil(router.lastHandledCommand)
    }

    func testMissingLocalRouterFallsBackToCommandRouter() {
        let guide = GuideTestSpyGuide(placementProvider: GuidePlacementProvider())
        let provider = GuideTestScreenProvider(displays: [])
        let coordinator = DisplayCoordinator(screenProvider: provider)
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)

        let consumed = PointerApplication.routeLocalEvent(
            keyDown(keyCode: 53),
            guide: guide,
            localRouter: nil,
            commandRouter: router
        )

        XCTAssertTrue(consumed)
        guard case .escape = router.lastHandledCommand else {
            return XCTFail("Command router did not receive Escape")
        }
    }

    func testToolSelectionModeEntryAndShortcutAnnotationToggleDismissGuide() throws {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        fixture.guide.show(in: fixture.placementContext)

        fixture.router.route(.setTool(.arrow))
        XCTAssertEqual(fixture.guide.dismissCount, 1)

        fixture.guide.show(in: fixture.placementContext)
        fixture.router.route(.setMode(.annotation))
        XCTAssertEqual(fixture.guide.dismissCount, 2)

        fixture.guide.show(in: fixture.placementContext)
        fixture.router.route(.setMode(.standby))
        let activeToken = try XCTUnwrap(fixture.shortcutController.activeToken)
        fixture.registrar.deliver(activeToken)
        XCTAssertEqual(fixture.guide.dismissCount, 3)
    }

    func testCanvasViewGestureDoesNotDismissGuideWithoutCommandEntry() {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        fixture.guide.show(in: fixture.placementContext)
        fixture.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))
        fixture.canvasView.endGesture()

        XCTAssertEqual(fixture.guide.dismissCount, 0)
    }

    func testGuidePlacementReceivesPaletteFrameAndAvoidanceRectsAndClamps() throws {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        fixture.controller.showGuide()

        let context = try XCTUnwrap(fixture.placementProvider.lastContext)
        XCTAssertEqual(context.display, fixture.display)
        XCTAssertEqual(context.paletteFrame, DisplayFrame(fixture.palette.window.frame))
        XCTAssertEqual(context.visibleFrame, fixture.display.visibleFrame)
        XCTAssertTrue(context.avoidanceFrames.contains(DisplayFrame(fixture.palette.window.frame)))
    }

    func testInvalidDisplayOrPaletteFrameReturnsNilPlacementContext() {
        let provider = GuidePlacementProvider()
        let invalid = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "invalid"),
            frame: DisplayFrame(x: 0, y: 0, width: 0, height: 0),
            visibleFrame: DisplayFrame(x: 0, y: 0, width: 0, height: 0),
            scaleFactor: 1
        )

        XCTAssertNil(provider.context(
            for: invalid,
            paletteFrame: DisplayFrame(x: 0, y: 0, width: 0, height: 0)
        ))
    }

    func testDisplayLossHidesGuideAndReconnectRestoresOnlyAfterPaletteShown() {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        XCTAssertTrue(fixture.guideStateStore.hasDismissedFirstUseGuide)
        fixture.events.removeAll()

        fixture.provider.displays = []
        fixture.postScreenChange()
        XCTAssertEqual(fixture.events, ["guide.hideForDisplayLoss"])

        fixture.provider.displays = [fixture.display]
        fixture.postScreenChange()
        XCTAssertEqual(
            fixture.events,
            ["guide.hideForDisplayLoss", "palette.show", "guide.restoreAfterDisplayLoss"]
        )
    }

    func testSeenVisibleGuideStillRestoresAfterDisplayLoss() {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        XCTAssertTrue(fixture.guideStateStore.hasDismissedFirstUseGuide)
        fixture.events.removeAll()

        fixture.provider.displays = []
        fixture.postScreenChange()
        fixture.provider.displays = [fixture.display]
        fixture.postScreenChange()

        XCTAssertEqual(
            fixture.events,
            ["guide.hideForDisplayLoss", "palette.show", "guide.restoreAfterDisplayLoss"]
        )
        XCTAssertTrue(fixture.guide.isVisible)
    }

    func testDismissedRestoredGuideDoesNotRestoreOnASecondDisplayLoss() {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        fixture.events.removeAll()

        fixture.provider.displays = []
        fixture.postScreenChange()
        fixture.provider.displays = [fixture.display]
        fixture.postScreenChange()
        XCTAssertEqual(
            fixture.events,
            ["guide.hideForDisplayLoss", "palette.show", "guide.restoreAfterDisplayLoss"]
        )

        fixture.guide.dismiss()
        fixture.guideStateStore.markFirstUseGuideDismissed()
        fixture.events.removeAll()
        fixture.provider.displays = []
        fixture.postScreenChange()
        fixture.provider.displays = [fixture.display]
        fixture.postScreenChange()

        XCTAssertEqual(fixture.events, ["palette.show"])
    }

    func testDisplayLossRestoreSurvivesReconnectPaletteFailureAndRetriesOnLaterSync() {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        fixture.events.removeAll()

        fixture.provider.displays = []
        fixture.postScreenChange()
        XCTAssertEqual(fixture.events, ["guide.hideForDisplayLoss"])

        fixture.provider.displays = [GuideTestScreenProvider.narrowDisplay]
        fixture.postScreenChange()
        XCTAssertEqual(fixture.events, ["guide.hideForDisplayLoss"])
        XCTAssertFalse(fixture.guide.isVisible)

        fixture.provider.displays = [fixture.display]
        fixture.postScreenChange()
        XCTAssertEqual(
            fixture.events,
            ["guide.hideForDisplayLoss", "palette.show", "guide.restoreAfterDisplayLoss"]
        )
        XCTAssertTrue(fixture.guide.isVisible)
    }

    func testStopClearsDisplayLossIntentWithoutChangingGuideStateAndRestartUsesSeenRule() {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        fixture.events.removeAll()
        let markCount = fixture.guideStateStore.markCount
        let hasDismissed = fixture.guideStateStore.hasDismissedFirstUseGuide

        fixture.provider.displays = []
        fixture.postScreenChange()
        fixture.controller.stop()

        XCTAssertEqual(
            fixture.events,
            ["guide.hideForDisplayLoss", "guide.hideForApplicationStop"]
        )
        XCTAssertEqual(fixture.guideStateStore.markCount, markCount)
        XCTAssertEqual(fixture.guideStateStore.hasDismissedFirstUseGuide, hasDismissed)

        fixture.provider.displays = [fixture.display]
        fixture.controller.start()

        XCTAssertEqual(
            fixture.events,
            [
                "guide.hideForDisplayLoss",
                "guide.hideForApplicationStop",
                "palette.show",
            ]
        )
    }

    func testControllerPaletteAndGuideShareTheInjectedPlacementProvider() {
        let fixture = GuideControllerFixture()

        XCTAssertTrue(fixture.controller.guidePlacementProvider === fixture.placementProvider)
        XCTAssertTrue(fixture.palette.guidePlacementProvider === fixture.placementProvider)
        XCTAssertTrue(fixture.guide.placementProvider === fixture.placementProvider)
    }

    func testMenuLearnPointerAndCallbacksCanBeClearedAndRebound() throws {
        let fixture = GuideControllerFixture()
        let menuBar = MenuBarController(router: fixture.router)
        menuBar.install()
        defer { menuBar.remove() }

        var learnCount = 0
        XCTAssertEqual(
            menuBar.bindCallbacks(
                onShowPalette: nil,
                onLearnPointer: { learnCount += 1 }
            ),
            1
        )
        let learnIndex = try XCTUnwrap(menuBar.menu?.items.firstIndex {
            $0.identifier?.rawValue == "menu.learn-pointer"
        })
        menuBar.menu?.performActionForItem(at: learnIndex)
        XCTAssertEqual(learnCount, 1)

        menuBar.clearCallbacks()
        menuBar.menu?.performActionForItem(at: learnIndex)
        XCTAssertEqual(learnCount, 1)

        menuBar.bindCallbacks(onShowPalette: nil, onLearnPointer: { learnCount += 1 })
        menuBar.menu?.performActionForItem(at: learnIndex)
        XCTAssertEqual(learnCount, 2)
    }
}

@MainActor
final class GuideControllerFixture {
    let notificationCenter = NotificationCenter()
    let display: DisplayDescriptor
    let provider: GuideTestScreenProvider
    let coordinator: DisplayCoordinator
    let router: CommandRouter
    let placementProvider: GuideTestPlacementProvider
    let palette: PalettePanel
    let guide: GuideTestSpyGuide
    let guideStateStore = GuideTestStateStore()
    let registrar: GuideTestHotKeyRegistrar
    let shortcutStore: GuideTestShortcutStore
    let shortcutScheduler: GuideTestShortcutScheduler
    let shortcutController: HotKeyController
    let canvasView: CanvasView
    let controller: PointerApplicationController
    let eventLog: GuideTestEventLog

    var events: [String] {
        get { eventLog.values }
        set { eventLog.values = newValue }
    }

    init(displays: [DisplayDescriptor]? = nil) {
        display = GuideTestScreenProvider.defaultDisplay
        provider = GuideTestScreenProvider(displays: displays ?? [display])
        eventLog = GuideTestEventLog()
        coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { GuideTestOverlay(display: $0) }
        )
        let registrar = GuideTestHotKeyRegistrar()
        let store = GuideTestShortcutStore()
        let scheduler = GuideTestShortcutScheduler()
        let shortcutController = HotKeyController(
            registrar: registrar,
            store: store,
            scheduler: scheduler
        )
        self.registrar = registrar
        shortcutStore = store
        shortcutScheduler = scheduler
        self.shortcutController = shortcutController
        router = CommandRouter(
            coordinator: coordinator,
            screenProvider: provider,
            shortcutController: shortcutController
        )
        placementProvider = GuideTestPlacementProvider(eventLog: eventLog)
        palette = PalettePanel(
            router: router,
            guidePlacementProvider: placementProvider
        )
        guide = GuideTestSpyGuide(placementProvider: placementProvider, eventLog: eventLog)
        let stateStore = guideStateStore
        guide.onVisible = { stateStore.markFirstUseGuideDismissed() }
        canvasView = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 1_600, height: 1_000),
            display: display.uuid,
            session: PointerSession()
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
            notificationCenter: notificationCenter
        )
        canvasView.update(session: router.session)
    }

    var placementContext: GuidePlacementContext {
        GuidePlacementContext(
            display: display,
            visibleFrame: display.visibleFrame,
            paletteFrame: DisplayFrame(palette.window.frame),
            avoidanceFrames: [DisplayFrame(palette.window.frame)]
        )
    }

    func postScreenChange() {
        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
}

@MainActor
final class GuideTestSpyGuide: FirstUseGuidePresenting {
    let placementProvider: any GuidePlacementProviding
    let eventLog: GuideTestEventLog?
    var onVisible: (() -> Void)?
    var isVisible: Bool
    var consumeEscapeCount = 0
    var dismissCount = 0
    var lastContext: GuidePlacementContext?

    init(
        placementProvider: any GuidePlacementProviding,
        visible: Bool = false,
        eventLog: GuideTestEventLog
    ) {
        self.placementProvider = placementProvider
        self.isVisible = visible
        self.eventLog = eventLog
    }

    convenience init(placementProvider: any GuidePlacementProviding, visible: Bool = false) {
        self.init(
            placementProvider: placementProvider,
            visible: visible,
            eventLog: GuideTestEventLog()
        )
    }

    func showIfNeeded(in context: GuidePlacementContext) {
        eventLog?.values.append("guide.showIfNeeded")
        lastContext = context
        isVisible = true
        onVisible?()
    }

    func show(in context: GuidePlacementContext) {
        lastContext = context
        isVisible = true
    }

    func dismiss() {
        dismissCount += 1
        isVisible = false
    }

    func hideForDisplayLoss() {
        eventLog?.values.append("guide.hideForDisplayLoss")
        isVisible = false
    }

    func restoreAfterDisplayLoss(in context: GuidePlacementContext) {
        eventLog?.values.append("guide.restoreAfterDisplayLoss")
        lastContext = context
        isVisible = true
    }

    func hideForApplicationStop() {
        eventLog?.values.append("guide.hideForApplicationStop")
        isVisible = false
    }

    func consumeEscape() -> Bool {
        consumeEscapeCount += 1
        guard isVisible else { return false }
        dismiss()
        return true
    }
}

@MainActor
final class GuideTestPlacementProvider: GuidePlacementProviding {
    let eventLog: GuideTestEventLog
    var lastContext: GuidePlacementContext?

    init(eventLog: GuideTestEventLog) { self.eventLog = eventLog }

    func context(
        for display: DisplayDescriptor,
        paletteFrame: DisplayFrame
    ) -> GuidePlacementContext? {
        guard display.visibleFrame.width > 0,
              display.visibleFrame.height > 0,
              paletteFrame.width > 0,
              paletteFrame.height > 0 else {
            return nil
        }
        eventLog.values.append("palette.show")
        let context = GuidePlacementContext(
            display: display,
            visibleFrame: display.visibleFrame,
            paletteFrame: paletteFrame,
            avoidanceFrames: [paletteFrame]
        )
        lastContext = context
        return context
    }
}

@MainActor
final class GuideTestEventLog {
    var values: [String] = []
}

@MainActor
final class GuideTestStateStore: FirstUseGuideStateStoring {
    var hasDismissedFirstUseGuide = false
    private(set) var markCount = 0

    func markFirstUseGuideDismissed() {
        markCount += 1
        hasDismissedFirstUseGuide = true
    }
}

@MainActor
final class GuideTestLocalRouter: LocalKeyRouting {
    let result: Bool
    private(set) var callCount = 0

    init(result: Bool) {
        self.result = result
    }

    func routeLocalKeyEvent(_ event: NSEvent) -> Bool {
        callCount += 1
        return result
    }
}

@MainActor
final class GuideTestScreenProvider: ScreenProviding {
    static let defaultDisplay = DisplayDescriptor(
        uuid: DisplayUUID(rawValue: "guide-display"),
        frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
        visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
        scaleFactor: 2
    )

    static let narrowDisplay = DisplayDescriptor(
        uuid: defaultDisplay.uuid,
        frame: DisplayFrame(x: 0, y: 0, width: 420, height: 150),
        visibleFrame: DisplayFrame(x: 0, y: 24, width: 420, height: 126),
        scaleFactor: 2
    )

    var displays: [DisplayDescriptor]

    init(displays: [DisplayDescriptor]) {
        self.displays = displays
    }

    func currentDisplays() -> [DisplayDescriptor] { displays }
    func pointerDisplay() -> DisplayUUID? { displays.first?.uuid }
}

@MainActor
final class GuideTestOverlay: OverlayPresenting {
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

@MainActor
final class GuideTestHotKeyRegistrar: HotKeyRegistering {
    var onEvent: ((HotKeyToken) -> Void)?
    private(set) var registrations: [HotKeyToken: ShortcutPreset] = [:]
    private var nextToken: UInt64 = 1

    func register(_ preset: ShortcutPreset) throws -> HotKeyToken {
        let token = HotKeyToken(rawValue: nextToken)
        nextToken += 1
        registrations[token] = preset
        return token
    }

    func unregister(_ token: HotKeyToken) {
        registrations.removeValue(forKey: token)
    }

    func deliver(_ token: HotKeyToken) {
        onEvent?(token)
    }
}

@MainActor
final class GuideTestShortcutStore: ShortcutStoring {
    var stored: ShortcutPreset?
    func load() -> ShortcutPreset? { stored }
    func save(_ preset: ShortcutPreset) { stored = preset }
}

@MainActor
final class GuideTestShortcutScheduler: ShortcutScheduling {
    private var nextToken: UInt64 = 1
    private var actions: [ShortcutScheduleToken: () -> Void] = [:]

    var activeTimerCount: Int { actions.count }

    @discardableResult
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> ShortcutScheduleToken {
        let token = ShortcutScheduleToken(rawValue: nextToken)
        nextToken += 1
        actions[token] = action
        return token
    }

    func cancel(_ token: ShortcutScheduleToken) {
        actions.removeValue(forKey: token)
    }

    func fireAll() {
        let pending = Array(actions.values)
        actions.removeAll()
        pending.forEach { $0() }
    }
}

private func keyDown(keyCode: UInt16) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: keyCode
    )!
}

private func mouseDown() -> NSEvent {
    NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: NSPoint(x: 10, y: 10),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1
    )!
}
