# Pointer C — Product Surface and Accessibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking. The coordinating agent owns commits and publication; worker tasks end with evidence/status handoff instead of commit steps.

**Goal:** Make Pointer's palette, menu bar, commands, shortcut flow, display-loss behavior, keyboard routing, and accessibility semantics legible, compact, reversible, and safe across normal, no-display, and restart states.

**Architecture:** Keep CommandRouter as the single command mutation route. Add an injected FirstUseGuidePresenting protocol without importing D's concrete guide, consume B's DisplaySyncResult/DisplayStopResult for lifecycle decisions, and make PalettePresenting.show(on:) return an explicit result. Keep native AppKit controls and SF Symbols, hide irrelevant style controls contextually, and expose every action through keyboard and accessibility metadata.

**Tech Stack:** Swift tools 5.10, macOS 14+, AppKit, PointerCore, PointerAppKit, XCTest, Carbon shortcut registration, NotificationCenter, native SF Symbols.

**Spec:** .codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md (Workstream C — palette, commands, shortcuts, and accessibility; B's accepted lifecycle contracts and D's guide implementation contract).

## Global Constraints

- The campaign improves the current annotation product. It does not broaden the product into a document or distribution platform.
- Use native AppKit controls, native menus, and native SF Symbols before adding custom UI, dependencies, or a new design system.
- The palette communicates one clear current mode and one clear selected tool; momentary actions look and behave like actions, not persistent selections.
- Icon-only controls never carry the sole meaning; every control retains an accessible name, help, stable identifier, enabled state, keyboard route, and visible focus state.
- On no connected displays, keep session/menu-bar/shortcut controls alive, reject annotation-entry commands with actionable “No presentation display connected” feedback, and do not mutate mode or selected tool.
- Guide timing is ordered and retryable: palette show must return shown before first-use show or reconnect restore; failed/hidden palette show cannot advance guide state. `GuidePresentationResult.shown` is valid only when the concrete guide is actually visible; the controller clears pending first-use/display-loss intent only for `.shown` or `.notNeeded`, and retries `.failed` or hidden results.
- The initial-palette state is explicit and separate from guide state. A valid first connection consumes the pending presentation; an initial zero-display connection keeps that presentation pending. Ordinary connected-display sync refreshes state without calling `palette.show(on:)`, preserving a manual drag. A palette hidden before zero-display remains hidden on reconnect; a palette visible at the transition is restored and clamped. If a first-use guide attempt failed before that manual hide, its pending first-use intent is preserved and explicit Show Palette retries it. A failed display-loss restore likewise remains pending through a temporary palette hide until explicit Show Palette/Learn, a successful or not-needed guide result, or application stop. Later guide retries compute a fresh context from the injected provider, current pointer display, and current palette frame without moving the palette.
- `PointerSession.selectedDisplay` is a B-owned session handoff consumed read-only by C's palette selection/style surface; future changes to its ownership return to B. C does not recreate or infer a selected display.
- Production shortcut/store/controller construction is dependency-injected; no production convenience initializer discovers global state.
- Work only in /Users/bruno/Dev/pointer/.worktrees/stable-app; preserve unrelated dirty files and generated artifacts in /Users/bruno/Dev/pointer.
- This workstream owns Sources/PointerAppKit/Palette/**, Sources/PointerAppKit/Palette/GuidePlacementContext.swift, Sources/PointerAppKit/Palette/GuidePlacementProvider.swift, Sources/PointerAppKit/Palette/ControlMetadataProvider.swift, CommandRouter.swift, MenuBarController.swift, PointerApplication.swift, PointerApplicationController.swift, Shortcuts/**, new Sources/PointerAppKit/Help/FirstUseGuidePresenting.swift, and app-controller/palette/command/shortcut tests except A's Support/** and Harness/** and F's PointerCompositionTests.
- Do not edit D's concrete guide files/assets, F's composition/build files, B's lifecycle implementation, A's diagnostics, E's measurement files, or unrelated cleanup.

---

## Dependency and interface contract

C consumes B's DisplaySyncResult, DisplayStopResult, DisplayCoordinator.onDisplaySync, DisplayCoordinator.synchronize() -> DisplaySyncResult, and DisplayCoordinator.stop() -> DisplayStopResult. C produces the guide protocol for D and F:

    @MainActor
    public enum PaletteShowResult: Equatable, Sendable {
        case shown(GuidePlacementContext)
        case noDisplay
        case failed(String)
    }

    public enum GuidePresentationResult: Equatable, Sendable {
        case shown
        case notNeeded
        case failed(String)
    }

    @MainActor
    public struct GuidePlacementContext: Equatable, Sendable {
        public let display: DisplayDescriptor
        public let visibleFrame: DisplayFrame
        public let paletteFrame: DisplayFrame
        public let avoidanceFrames: [DisplayFrame]
        public init(display: DisplayDescriptor, visibleFrame: DisplayFrame,
                    paletteFrame: DisplayFrame,
                    avoidanceFrames: [DisplayFrame])
    }

    @MainActor
    public protocol GuidePlacementProviding: AnyObject {
        func context(for display: DisplayDescriptor,
                     paletteFrame: DisplayFrame) -> GuidePlacementContext?
    }

    @MainActor
    public final class GuidePlacementProvider: GuidePlacementProviding {
        public init()
        public func context(for display: DisplayDescriptor,
                            paletteFrame: DisplayFrame) -> GuidePlacementContext?
    }

    @MainActor
    public protocol PalettePresenting: AnyObject {
        var window: NSWindow { get }
        var guidePlacementProvider: any GuidePlacementProviding { get }
        func refresh(session: PointerSession)
        func show(on display: DisplayDescriptor) -> PaletteShowResult
        func hide()
    }

    @MainActor
    public struct ControlMetadata: Equatable, Sendable {
        public let identifier: String
        public let accessibleName: String
        public let help: String?
        public let value: String?
        public let role: String
        public let isEnabled: Bool
        public let isKeyboardReachable: Bool
    }

    @MainActor
    public protocol ControlMetadataProviding: AnyObject {
        func metadata() -> [ControlMetadata]
    }

    @MainActor
    public final class ControlMetadataInventory: ControlMetadataProviding {
        public init(palette: PalettePanel, menuBar: MenuBarController?)
        public func metadata() -> [ControlMetadata]
    }

    @MainActor
    public protocol FirstUseGuidePresenting: AnyObject {
        var isVisible: Bool { get }
        var placementProvider: any GuidePlacementProviding { get }
        @discardableResult
        func showIfNeeded(in context: GuidePlacementContext) -> GuidePresentationResult
        @discardableResult
        func show(in context: GuidePlacementContext) -> GuidePresentationResult
        func dismiss()
        func hideForDisplayLoss()
        @discardableResult
        func restoreAfterDisplayLoss(in context: GuidePlacementContext) -> GuidePresentationResult
        func hideForApplicationStop()
        func consumeEscape() -> Bool
    }

    @MainActor
    public protocol LocalKeyRouting: AnyObject {
        @discardableResult
        func routeLocalKeyEvent(_ event: NSEvent) -> Bool
    }

    extension CommandRouter: LocalKeyRouting {}

    @MainActor
    public final class PointerApplication: NSApplication {
        public override init() { super.init() }
        public weak var commandRouter: CommandRouter?
        public weak var localKeyRouter: (any LocalKeyRouting)?
        public weak var firstUseGuide: (any FirstUseGuidePresenting)?
    }

    @MainActor
    public final class PointerApplicationController: NSObject, NSApplicationDelegate {
        public let screenProvider: any ScreenProviding
        public let displayCoordinator: DisplayCoordinator
        public let commandRouter: CommandRouter
        public let palette: any PalettePresenting
        public let menuBar: (any MenuBarPresenting)?
        public let shortcutController: HotKeyController
        public let guide: any FirstUseGuidePresenting
        public let guideStateStore: any FirstUseGuideStateStoring
        public let controlMetadataProvider: any ControlMetadataProviding
        public let guidePlacementProvider: any GuidePlacementProviding
        public let shortcutStore: any ShortcutStoring
        public let hotKeyRegistrar: any HotKeyRegistering
        public let shortcutScheduler: any ShortcutScheduling
        public let notificationCenter: NotificationCenter
    }

    @MainActor
    public init(
        screenProvider: any ScreenProviding,
        displayCoordinator: DisplayCoordinator,
        commandRouter: CommandRouter,
        palette: any PalettePresenting,
        menuBar: (any MenuBarPresenting)?,
        shortcutController: HotKeyController,
        guide: any FirstUseGuidePresenting,
        guideStateStore: any FirstUseGuideStateStoring,
        controlMetadataProvider: any ControlMetadataProviding,
        guidePlacementProvider: any GuidePlacementProviding,
        notificationCenter: NotificationCenter
    )

No C file imports FirstUseGuideController or FirstUseGuideViewController. F injects D's concrete guide through this protocol.

## Task 1: Make command and palette show outcomes explicit

**Files:**

- Modify: Sources/PointerAppKit/Palette/PalettePanel.swift
- Modify: Sources/PointerAppKit/Palette/PaletteViewController.swift
- Modify: Sources/PointerAppKit/CommandRouter.swift
- Modify: Tests/PointerAppKitTests/PaletteLayoutTests.swift
- Modify: Tests/PointerAppKitTests/CommandRouterTests.swift
- Create: Tests/PointerAppKitTests/PaletteInteractionTests.swift

**Interfaces:**

- PalettePanel.show(on:) -> PaletteShowResult returns noDisplay for nonpositive visible-frame dimensions, failed(reason) for layout/order-front failure, and shown(GuidePlacementContext) only after the window is visible and clamped; the associated context is the exact provider output consumed by the guide.
- PalettePanel.init(router:guidePlacementProvider:) stores the injected C GuidePlacementProvider as public let guidePlacementProvider and uses it to produce the associated .shown(context) value; it never creates a second provider.
- Every Task 1 palette fixture constructs and injects one GuidePlacementProvider through PalettePanel(router:guidePlacementProvider:). The existing controller-only internal/deprecated convenience seam is retained solely so pre-Task-3 production/controller call sites compile; Task 3 must migrate every ControllerFixture and PointerApplicationController call site to the same injected provider/guide identity and delete that seam. No public palette initializer discovers a provider globally.
- GuidePlacementProvider.context(for:paletteFrame:) returns nil for an invalid display/palette frame; otherwise it returns GuidePlacementContext(display: display, visibleFrame: display.visibleFrame, paletteFrame: paletteFrame, avoidanceFrames: [paletteFrame]) after deterministic clamping/avoidance calculation.
- CommandRouter exposes public private(set) var feedbackMessage: String? and public var onFeedback: ((String) -> Void)?.
- CommandRouter exposes public var activeShortcutID: String? { get } and public var shortcutError: String? { get }; activeShortcutID is shortcutController.activePreset?.rawValue and shortcutError is shortcutController.registrationError without discovering a controller.
- CommandRouter exposes public var onAnnotationEntry: (() -> Void)? and calls it only for command/controller entry into annotation: setTool, setMode(.annotation), and toggle/shortcut from standby. CanvasView gesture methods never call this hook.
- CommandRouter exposes public func updateDisplayState(_ result: DisplaySyncResult) and public func clearCallbacks()/bindCallbacks(onStateChange:onClearAllRequested:onAnnotationEntry:). Annotation-entry commands guard the accepted result's hasConnectedDisplays, valid connectedUUIDs, and pointerDisplay membership; an invalid descriptor/pointer UUID rejects without mutating mode/tool and emits “No presentation display connected”.
- CommandRouter Escape has one cancellation route: coordinator.cancelActiveGestures() exactly once, then coordinator.apply(.setMode(.standby), cancellingActiveGestures: false). It never calls coordinator.apply(.setMode(.standby)) through the default cancelling path.
- CommandRouter's callback API is explicit:

    @discardableResult
    public func bindCallbacks(
        onStateChange: ((PointerSession) -> Void)?,
        onClearAllRequested: (() -> Void)?,
        onAnnotationEntry: (() -> Void)?
    ) -> Int
    public func clearCallbacks()

  bindCallbacks installs each once and returns the binding count. Task 3, which owns MenuBarController and controller lifecycle, must add clearCallbacks() and bindCallbacks(onShowPalette:onLearnPointer:) -> Int, clearing/rebinding its Show Palette, Learn Pointer, Clear All, Undo Clear All, shortcut, and Quit action closures without replacing the NSMenu hierarchy.
- setTool still selects the tool and enters annotation in one route when a display exists; setStyle, setEmoji, and setSpotlight preserve existing selected-mark/future-default behavior.

- [ ] **Step 1: Write failing command and show-result tests.**

    @MainActor
    func testNoDisplayRejectsAnnotationEntryWithoutMutatingModeOrTool() {
        let provider = TestScreenProvider(displays: [])
        let coordinator = DisplayCoordinator(screenProvider: provider)
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        router.route(.setTool(.spotlight))
        XCTAssertEqual(router.session.mode, .standby)
        XCTAssertEqual(router.session.toolState.tool, .arrow)
        XCTAssertEqual(router.feedbackMessage, "No presentation display connected")
    }

    @MainActor
    func testEscapeCancelsRealOverlayOnceAndStaleMouseUpDoesNotDuplicateBoundary() {
        let fixture = CommandFixture.withRealOverlay()
        var boundaries: [GestureBoundaryEvent] = []
        fixture.coordinator.onBoundaryEvent = { _, event in boundaries.append(event) }
        fixture.router.route(.setMode(.annotation))
        fixture.beginRealGesture()
        fixture.router.route(.escape)
        fixture.sendStaleMouseUp()
        XCTAssertEqual(boundaries, [.began, .cancelled])
        XCTAssertEqual(fixture.router.session.mode, .standby)
        XCTAssertTrue(fixture.router.session.canvas(for: fixture.display).marks.isEmpty)
    }

    @MainActor
    func testInvalidPointerUUIDOrDescriptorIsRejectedAgainstAcceptedDisplaySyncSet() {
        let valid = displayDescriptor(uuid: DisplayUUID(rawValue: "valid"))
        let provider = TestScreenProvider(displays: [valid], pointerUUID: DisplayUUID(rawValue: "missing"))
        let coordinator = DisplayCoordinator(screenProvider: provider)
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        router.updateDisplayState(coordinator.synchronize())
        router.route(.setMode(.annotation))
        XCTAssertEqual(router.session.mode, .standby)
        XCTAssertEqual(router.feedbackMessage, "No presentation display connected")
    }

    @MainActor
    func testPaletteShowReturnsExplicitNoDisplayOrShown() {
        let provider = TestScreenProvider(displays: [])
        let coordinator = DisplayCoordinator(screenProvider: provider)
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let placementProvider = GuidePlacementProvider()
        let palette = PalettePanel(router: router, guidePlacementProvider: placementProvider)
        XCTAssertTrue(palette.guidePlacementProvider === placementProvider)
        let invalid = DisplayDescriptor(uuid: DisplayUUID(rawValue: "invalid"),
                                        frame: DisplayFrame(x: 0, y: 0, width: 0, height: 0),
                                        visibleFrame: DisplayFrame(x: 0, y: 0, width: 0, height: 0),
                                        scaleFactor: 1)
        XCTAssertEqual(palette.show(on: invalid), .noDisplay)
        let descriptor = displayDescriptor()
        guard case .shown = palette.show(on: descriptor) else {
            return XCTFail("Expected shown(GuidePlacementContext)")
        }
    }

    @MainActor
    func testDeleteAffordanceFollowsExplicitSelectionAndStandby() throws {
        let fixture = PaletteFixture.oneDisplay()
        fixture.controller.start()
        let display = fixture.display
        fixture.harnessCreateArrow(on: display)
        fixture.router.route(.setTool(.select))
        fixture.harnessSelectArrow(on: display)
        XCTAssertTrue(fixture.paletteController.deleteButton.isEnabled)
        fixture.router.route(.setMode(.standby))
        XCTAssertFalse(fixture.paletteController.deleteButton.isHidden == false && fixture.paletteController.deleteButton.isEnabled)
        fixture.router.route(.setMode(.annotation))
        XCTAssertFalse(fixture.paletteController.deleteButton.isEnabled)
    }

- [ ] **Step 2: Run focused tests and verify RED.**

Run:

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'CommandRouterTests|PaletteInteractionTests|PaletteLayoutTests'

Expected: compilation fails because PaletteShowResult, feedbackMessage/onFeedback, and contextual Delete are absent. If a pre-existing palette layout test passes, retain it as baseline and keep the new interaction assertions.

- [ ] **Step 3: Implement explicit show and rejection behavior.**

Validate the descriptor's visible frame before changing window state. In CommandRouter, centralize the display guard in a private requirePointerDisplayForAnnotation() helper that checks the last accepted DisplaySyncResult.hasConnectedDisplays, connectedUUIDs, and pointerDisplay membership, sets feedbackMessage, and calls onFeedback once. clearCallbacks()/bindCallbacks() must not reset the accepted display state. Clear feedbackMessage after a successful mode/tool/action route. Do not create a fallback display, mutate the selected tool on rejection, or hide the palette from the router.

- [ ] **Step 4: Add contextual Delete and no-op enablement.**

Add a stable palette.delete control that is enabled only when session.mode == .annotation && session.selection != nil; route it to the same .delete command as Delete/Backspace. Disable Undo when no per-display undo is available and Clear when the pointer display is absent or empty. Keep Clear All in MenuBarController with confirmation and Undo Clear All. Clear selection on empty-canvas click via B's session route; emit brief nonmodal feedback through onFeedback.

- [ ] **Step 5: Run focused tests and verify GREEN.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'CommandRouterTests|PaletteInteractionTests|PaletteLayoutTests'

Expected: PASS, with no-display rejection, explicit PaletteShowResult, contextual Delete sequence, and no-op action state covered.

## Task 2: Make palette controls compact, contextual, and keyboard-operable

**Files:**

- Modify: Sources/PointerAppKit/Palette/PaletteViewController.swift
- Modify: Sources/PointerAppKit/Palette/PaletteLayout.swift
- Create: Sources/PointerAppKit/Palette/GuidePlacementContext.swift
- Create: Sources/PointerAppKit/Palette/GuidePlacementProvider.swift
- Create: Sources/PointerAppKit/Palette/ControlMetadataProvider.swift
- Modify: Tests/PointerAppKitTests/PaletteLayoutTests.swift
- Modify: Tests/PointerAppKitTests/PaletteInteractionTests.swift

**Interfaces:**

- PaletteViewController.controls remains the inspectable list of all controls; add deleteButton and a mode/status control with stable identifiers.
- Tool controls use native SF Symbols paired with visible canonical titles: Select, Arrow, Rectangle, Ellipse, Pen, Eraser, Emoji, Spotlight. The symbol is never the only accessible name.
- PaletteViewController.refresh(session:) updates selected tool, mode, style values, shortcut status, contextual visibility/enabled state, and status feedback without moving the window or stealing focus.
- PaletteLayout.plan(availableWidth:) keeps every tool reachable at width 420, gives overflow an obvious “More Tools” label, and never returns a zero-width tool.
- ControlMetadataInventory in Palette/ControlMetadataProvider.swift conforms to ControlMetadataProviding, accepts the real PalettePanel and MenuBarController hierarchy, and returns one deterministic ControlMetadata row per palette/menu control in keyboard order through metadata(). It has no mutation API and never exposes NSControl instances.

- [ ] **Step 1: Write failing layout, enabled-state, and focus-order tests.**

    func testNarrowPaletteKeepsModeAndReachableToolsWithNamedOverflow() {
        let plan = PaletteLayout.plan(availableWidth: 420)
        XCTAssertTrue(plan.usesOverflow)
        XCTAssertFalse(plan.overflowTools.isEmpty)
        XCTAssertTrue(plan.rows.flatMap { $0 }.contains(.overflow))
    }

    @MainActor
    func testPaletteControlsHaveStableNamesHelpValuesAndFocusOrder() {
        let controller = PaletteViewController(router: fixtureRouter())
        controller.loadViewIfNeeded()
        let controls = controller.controls
        XCTAssertEqual(Set(controls.compactMap { $0.identifier?.rawValue }).count,
                       controls.count)
        XCTAssertTrue(controls.allSatisfy { $0.isAccessibilityElement && !$0.accessibilityLabel.isEmpty })
        XCTAssertTrue(controls.allSatisfy { $0.focusRingType != .none })
        XCTAssertEqual(controls.first?.identifier?.rawValue, "palette.mode")
    }

    @MainActor
    func testRelevantStyleControlsAreEnabledAndIrrelevantControlsExplainDisabledState() {
        let controller = PaletteViewController(router: fixtureRouter())
        controller.loadViewIfNeeded()
        controller.refresh(session: session(tool: .arrow, mode: .annotation))
        XCTAssertTrue(controller.control(identifier: "palette.style.color").isEnabled)
        XCTAssertFalse(controller.control(identifier: "palette.spotlight.radius").isEnabled)
        XCTAssertTrue(controller.control(identifier: "palette.spotlight.radius").accessibilityHelp?.contains("Spotlight") == true)
    }

- [ ] **Step 2: Run focused tests and verify RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PaletteLayoutTests|PaletteInteractionTests'

Expected: failures identify missing symbols, delete control, focus order, contextual style enablement, or overflow naming.

- [ ] **Step 3: Implement native control semantics and layout.**

Assign NSImage(systemSymbolName:) with a text fallback, keep visible titles, set accessibility label/help/identifier, and configure keyEquivalent only for local commands that already route through CommandRouter. Make the mode control visually distinct from tool toggles. Use a horizontal style scroller only for the second row; keep all first-row tools reachable at narrow width through a named More Tools popup. Preserve normal refresh window origin and make explicit Show Palette the only reposition path.

- [ ] **Step 4: Implement context rules and visible values.**

Enable color/stroke/opacity for arrow, rectangle, ellipse, pen, and compatible selected marks; enable emoji only for emoji tool or selected emoji; enable radius/dimness only for spotlight; keep disabled controls visible with an explanatory accessibility help string when removing them would destabilize keyboard order. Show numeric slider values through accessibilityValue and a concise visible value label. Delete appears only for an explicit selection in annotation mode.

- [ ] **Step 5: Run C palette tests and verify GREEN.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PaletteLayoutTests|PaletteInteractionTests|CommandRouterTests'

Expected: PASS at wide and 420-point layouts, with stable identifiers, names, values, visible focus, and contextual state.

## Task 3: Inject the guide protocol and order first-use/display-loss behavior

**Files:**

- Create: Sources/PointerAppKit/Help/FirstUseGuidePresenting.swift
- Modify: Sources/PointerAppKit/PointerApplicationController.swift
- Modify: Sources/PointerAppKit/MenuBarController.swift
- Modify: Sources/PointerAppKit/PointerApplication.swift
- Modify: Tests/PointerAppKitTests/PointerApplicationControllerTests.swift
- Create: Tests/PointerAppKitTests/GuideIntegrationTests.swift

**Interfaces:**

- FirstUseGuidePresenting is exactly the protocol in this plan's dependency contract and receives GuidePlacementContext for first-use/show/restore placement.
- PointerApplicationController owns pending-initial-palette, pending-first-use, and display-loss intent flags; it never persists guide state itself. It recomputes guide placement context for retries without repositioning the palette.
- PointerApplicationController exposes public let guide: any FirstUseGuidePresenting, public let controlMetadataProvider: any ControlMetadataProviding, and public let guidePlacementProvider: any GuidePlacementProviding. It converts the current palette.window.frame to DisplayFrame and asks the C provider for a failable context(for:paletteFrame:) before every guide show/restore.
- PointerApplicationController exposes public func showGuide(), which calls guide.show(in:) with the associated GuidePlacementContext from a successful palette show result and returns the guide's `GuidePresentationResult` when a display is available. A successful explicit Learn Pointer/showGuide result consumes pending first-use and superseded restore intent only for `.shown` when visible or `.notNeeded`; `.failed` and hidden `.shown` remain retryable.
- PointerApplicationController exposes public let shortcutController: HotKeyController (nonoptional) and its production initializer requires that concrete controller; tests pass a real HotKeyController built with fake registrar/store/scheduler collaborators.
- The source declaration is exactly public let shortcutController: HotKeyController, never an optional. PointerApplicationControllerTests constructs the controller with a nonnil fake-backed HotKeyController and asserts the property identity before and after stop/start.
- PointerApplication exposes injectable LocalKeyRouting and FirstUseGuidePresenting references; sendEvent asks guide.consumeEscape() before the injected router's routeLocalKeyEvent(event). CommandRouter conforms to LocalKeyRouting, so tests use the real final router and observe lastHandledCommand rather than subclassing it.
- MenuBarController adds Learn Pointer with stable identifier menu.learn-pointer and calls the controller's placement-aware Learn Pointer hook without importing D.
- GuideControllerFixture owns a real final CommandRouter, real HotKeyController backed by fake registrar/store/scheduler, SpyGuide, SpyPlacementProvider, real PalettePanel, and a CanvasView. Its shortcutController.simulateToggle() delivers the active registered token through HotKeyController.onEvent; no final-class spy subclass is used.

- [ ] **Step 1: Write failing guide-order and Escape-precedence tests.**

    @MainActor
    func testStartupShowsPaletteBeforeFirstUseGuide() {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        XCTAssertEqual(fixture.events, ["palette.show", "guide.showIfNeeded"])
        XCTAssertTrue(fixture.guide.isVisible)
    }

    @MainActor
    func testZeroDisplayStartupDefersGuideAndFirstReconnectRetriesInOrder() {
        let fixture = GuideControllerFixture(displays: [])
        fixture.controller.start()
        XCTAssertEqual(fixture.events, [])
        fixture.provider.displays = [fixture.display]
        fixture.postScreenChange()
        XCTAssertEqual(fixture.events, ["palette.show", "guide.showIfNeeded"])
    }

    @MainActor
    func testVisibleGuideConsumesEscapeBeforeCommandRouter() {
        let guide = SpyGuide(visible: true)
        let provider = TestScreenProvider(displays: [])
        let coordinator = DisplayCoordinator(screenProvider: provider)
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let application = PointerApplication()
        application.commandRouter = router
        application.localKeyRouter = router
        application.firstUseGuide = guide
        let event = keyDown(keyCode: 53)
        application.sendEvent(event)
        XCTAssertEqual(guide.consumeEscapeCount, 1)
        XCTAssertNil(router.lastHandledCommand)
        XCTAssertEqual(guide.isVisible, false)
    }

    @MainActor
    func testToolSelectionModeEntryAndShortcutAnnotationToggleDismissGuide() {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        fixture.guide.show(in: fixture.placementContext)
        fixture.router.route(.setTool(.arrow))
        XCTAssertEqual(fixture.guide.dismissCount, 1)
        fixture.guide.show(in: fixture.placementContext)
        fixture.router.route(.setMode(.annotation))
        XCTAssertEqual(fixture.guide.dismissCount, 2)
        fixture.guide.show(in: fixture.placementContext)
        fixture.shortcutController.simulateToggle()
        XCTAssertEqual(fixture.guide.dismissCount, 3)
    }

    @MainActor
    func testCanvasViewGestureDoesNotDismissGuideWithoutCommandEntry() {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        fixture.guide.show(in: fixture.placementContext)
        fixture.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))
        fixture.canvasView.endGesture()
        XCTAssertEqual(fixture.guide.dismissCount, 0)
    }

    @MainActor
    func testGuidePlacementReceivesPaletteFrameAndAvoidanceRectsAndClamps() {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        fixture.controller.showGuide()
        XCTAssertEqual(fixture.placementProvider.lastContext.display, fixture.display)
        XCTAssertEqual(fixture.placementProvider.lastContext.paletteFrame,
                       DisplayFrame(fixture.palette.window.frame))
        XCTAssertEqual(fixture.placementProvider.lastContext.visibleFrame,
                       fixture.display.visibleFrame)
        XCTAssertTrue(fixture.placementProvider.lastContext.avoidanceFrames.contains(
            DisplayFrame(fixture.palette.window.frame)))
    }

    @MainActor
    func testInvalidDisplayOrPaletteFrameReturnsNilPlacementContext() {
        let provider = GuidePlacementProvider()
        let invalid = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "invalid"),
            frame: DisplayFrame(x: 0, y: 0, width: 0, height: 0),
            visibleFrame: DisplayFrame(x: 0, y: 0, width: 0, height: 0),
            scaleFactor: 1
        )
        XCTAssertNil(provider.context(for: invalid,
                                     paletteFrame: DisplayFrame(x: 0, y: 0, width: 0, height: 0)))
    }

    @MainActor
    func testDisplayLossHidesGuideAndReconnectRestoresOnlyAfterPaletteShown() {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        fixture.events.removeAll()
        fixture.provider.displays = []
        fixture.postScreenChange()
        XCTAssertEqual(fixture.events, ["guide.hideForDisplayLoss"])
        fixture.provider.displays = [fixture.display]
        fixture.postScreenChange()
        XCTAssertEqual(fixture.events, ["guide.hideForDisplayLoss", "palette.show", "guide.restoreAfterDisplayLoss"])
    }

- [ ] **Step 2: Run focused tests and verify RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'GuideIntegrationTests|PointerApplicationControllerTests'

Expected: compilation fails because FirstUseGuidePresenting, injected PointerApplication construction, and DisplaySyncResult callback consumption are absent.

- [ ] **Step 3: Add the protocol and explicit dependency injection.**

Create FirstUseGuidePresenting.swift with the exact placement-aware methods above. Remove the production no-argument PointerApplicationController initializer; require screenProvider, displayCoordinator, commandRouter, palette, menuBar, shortcutController, guide, guideStateStore, controlMetadataProvider, guidePlacementProvider, and notificationCenter. C depends only on the catalog-agnostic guide contract; D's concrete guide owns/exposes its injected asset catalog. Keep any test-only convenience construction under the existing PointerAppKitTests target and unavailable to the production target. Wire PointerApplication with:

    public weak var commandRouter: CommandRouter?
    public weak var localKeyRouter: (any LocalKeyRouting)?
    public weak var firstUseGuide: (any FirstUseGuidePresenting)?

    public override func sendEvent(_ event: NSEvent) {
        if firstUseGuide?.consumeEscape() == true { return }
        if localKeyRouter?.routeLocalKeyEvent(event) == true { return }
        super.sendEvent(event)
    }

- [ ] **Step 4: Implement ordered startup, display-state guard, callback rebinding, and placement consumption.**

On start, bind CommandRouter.bindCallbacks(...) and MenuBarController.bindCallbacks() exactly once, bind the coordinator's onDisplaySync callback once, synchronize, call commandRouter.updateDisplayState(result), refresh, and call palette.show(on:). The .shown(context) associated value is passed directly to guide.showIfNeeded(in:). At zero displays, first apply the standby command through DisplayCoordinator before emitting DisplaySyncResult, call commandRouter.updateDisplayState(result), record a pending first-use attempt without showing or marking the guide, hide the palette, and reject annotation entry without mutating mode/tool. On a later hasConnectedDisplays result with a valid pointer UUID, show the palette first; pass its .shown(context) directly to guide.restoreAfterDisplayLoss(in:).

The onAnnotationEntry hook dismisses the guide for tool selection, explicit mode entry, menu mode entry, and shortcut toggles into annotation. CanvasView.beginGesture/continueGesture/endGesture never calls this hook. stop() calls CommandRouter.clearCallbacks(), MenuBarController.clearCallbacks(), and sets displayCoordinator.onDisplaySync = nil; start() rebinds the display-sync callback once and rebinds command/menu callbacks once. The controller tests assert the callback is nil while stopped and nonnil exactly once after restart; the clear-all callback is tested across stop/start so one Clear All request produces one confirmation and one command. On a normal connected sync, the controller does not re-show or reposition an already-present palette; it only consumes a pending initial/reconnect presentation or retries a guide using a fresh context from the current display and palette frame. A hidden palette does not cancel pending guide intent merely because it is hidden temporarily.

- [ ] **Step 5: Add menu Learn Pointer and run GREEN tests.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'GuideIntegrationTests|PointerApplicationControllerTests|CommandRouterTests'

Expected: PASS with order, retry, display-loss, reconnect, Escape precedence, and no-guide-state-mutation assertions.

## Task 4: Make shortcuts explicit, reversible, and restart-safe

**Files:**

- Modify: Sources/PointerAppKit/Shortcuts/UserDefaultsShortcutStore.swift
- Modify: Sources/PointerAppKit/Shortcuts/HotKeyController.swift
- Modify: Sources/PointerAppKit/Shortcuts/ShortcutStoring.swift
- Modify: Sources/PointerAppKit/PointerApplicationController.swift
- Modify: Tests/PointerAppKitTests/HotKeyControllerTests.swift
- Create: Tests/PointerAppKitTests/ShortcutLifecycleTests.swift

**Interfaces:**

- UserDefaultsShortcutStore.init(userDefaults: UserDefaults, key: String) has no default arguments.
- HotKeyController.init(registrar: any HotKeyRegistering, store: any ShortcutStoring, scheduler: any ShortcutScheduling, timeout: TimeInterval = 5) requires all production collaborators; production no-argument construction is removed.
- HotKeyController exposes public let registrar: any HotKeyRegistering, public let store: any ShortcutStoring, and public let scheduler: any ShortcutScheduling as read-only dependency identities; its production construction remains explicit.
- HotKeyController keeps the old active shortcut until a candidate event is delivered, persists only after delivery within five seconds, unregisters/rolls back on registration error or timeout, ignores late candidate events, and exposes registrationError.
- PointerApplicationController.stop() calls HotKeyController.stop(), removes its callback/observer/menu/palette/guide resources, and start() binds one callback exactly once.
- PointerApplicationController exposes public let screenProvider, displayCoordinator, commandRouter, palette, menuBar, shortcutStore, hotKeyRegistrar, shortcutScheduler, and notificationCenter identities alongside shortcutController/guide/providers so F can assert the complete composition graph.
- Every ControllerFixture and PointerApplicationControllerTests construction supplies a nonnil HotKeyController created with the test registrar/store/scheduler; assertions compare fixture.controller.shortcutController === fixture.shortcutController and exercise activeShortcutID/error through the real CommandRouter.

- [ ] **Step 1: Write failing shortcut transaction and restart tests.**

    @MainActor
    func testCandidateTimeoutKeepsOldShortcutAndReportsActionableError() {
        let fakes = ShortcutFakes()
        let controller = HotKeyController(registrar: fakes.registrar,
                                          store: fakes.store,
                                          scheduler: fakes.scheduler)
        controller.start()
        let old = controller.activePreset
        controller.setShortcut(.controlOptionCommandO)
        fakes.scheduler.fireAll()
        XCTAssertEqual(controller.activePreset, old)
        XCTAssertTrue(controller.registrationError?.contains("five seconds") == true)
        fakes.registrar.send(.controlOptionCommandO)
        XCTAssertEqual(controller.activePreset, old)
    }

    @MainActor
    func testDeliveredCandidatePersistsAndTogglesOnce() {
        let fakes = ShortcutFakes()
        let controller = HotKeyController(registrar: fakes.registrar,
                                          store: fakes.store,
                                          scheduler: fakes.scheduler)
        var toggles = 0
        controller.onToggle = { toggles += 1 }
        controller.start()
        controller.setShortcut(.controlOptionCommandO)
        fakes.registrar.send(.controlOptionCommandO)
        XCTAssertEqual(controller.activePreset, .controlOptionCommandO)
        XCTAssertEqual(fakes.store.saved, [.controlOptionCommandO])
        XCTAssertEqual(toggles, 1)
    }

    @MainActor
    func testControllerStopStartRebindsOneCallbackAndOneTogglePerEvent() {
        let fixture = ControllerFixture.withShortcutFakes()
        fixture.controller.start()
        fixture.controller.stop()
        fixture.controller.start()
        fixture.registrar.sendActive()
        XCTAssertEqual(fixture.toggleCount, 1)
    }

- [ ] **Step 2: Run focused tests and verify RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'HotKeyControllerTests|ShortcutLifecycleTests'

Expected: compilation fails for required initializer arguments or the current timeout/late-event behavior fails.

- [ ] **Step 3: Remove global shortcut/store discovery and implement rollback semantics.**

Require explicit UserDefaults and key. In HotKeyController, preserve activeToken/activePreset while pending, schedule exactly one timeout, cancel/unregister pending on replacement, and on candidate delivery save only after the candidate token matches. On timeout or registration error, clear pending state, unregister the candidate, retain active state, and set a message naming the preset and five-second deadline. Ignore events whose token is neither pending nor active.

CommandRouter.activeShortcutID returns shortcutController.activePreset?.rawValue and CommandRouter.shortcutError returns shortcutController.registrationError; both are read-only and remain available to A's later harness without exposing registrar tokens.

- [ ] **Step 4: Implement stop/start ownership.**

stop() cancels pending timers, unregisters active tokens, clears registrar.onEvent and onToggle, and leaves zero timer/callback resources. start() binds one registrar callback and one controller callback. PointerApplicationController must not install duplicate screen observers or menu callbacks after repeated start/stop.

- [ ] **Step 5: Run shortcut and C suites.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'HotKeyControllerTests|ShortcutLifecycleTests|PointerApplicationControllerTests|CommandRouterTests'

Expected: PASS with old-shortcut preservation, candidate delivery, timeout, late-event, error, and duplicate-free restart evidence.

## Task 5: Add accessibility, appearance, and lifecycle checkpoint assertions

**Files:**

- Modify: Sources/PointerAppKit/Palette/PaletteViewController.swift
- Modify: Sources/PointerAppKit/MenuBarController.swift
- Modify: Sources/PointerAppKit/PointerApplicationController.swift
- Modify: Tests/PointerAppKitTests/PaletteInteractionTests.swift
- Modify: Tests/PointerAppKitTests/PointerApplicationControllerTests.swift
- Create: Tests/PointerAppKitTests/AccessibilityMetadataTests.swift

**Interfaces:**

- Every palette/menu control has a stable identifier, accessible name, help, role/value where relevant, enabled/selected state, keyboard route, and visible focus ring.
- VoiceOver-relevant order is mode, tool controls, relevant style controls, actions, status/shortcut error; no state relies on color alone.
- Reduce Transparency hides the visual effect and supplies an opaque background; Increase Contrast increases border/focus contrast; error/disabled/selected states have non-color cues.
- Lifecycle checkpoints assert running, stopped, and restarted bounded resources independently: one palette, one menu item, one screen observer, one shortcut wiring, one overlay per connected display, zero normal timers; stop has zero active controller-owned lifecycle windows/overlays/timers/callbacks/observers (permanent object-lifetime wiring is not an active resource); restart rebuilds one of each without duplicates.
- CommandRouter.clearCallbacks()/bindCallbacks(...) and MenuBarController.clearCallbacks()/bindCallbacks() are the only callback lifecycle APIs. The stop/start tests assert callback binding count one after restart and one Clear All confirmation/command for one menu action.

- [ ] **Step 1: Add failing accessibility and checkpoint tests.**

    @MainActor
    func testPaletteAndMenuMetadataIsCompleteAndKeyboardReachable()
    @MainActor
    func testReduceTransparencyAndIncreaseContrastChangeUsableVisualState()
    @MainActor
    func testRunningStoppedAndRestartedResourceCheckpointsAreSeparate()
    @MainActor
    func testFeedbackDoesNotStealFocusOrMovePalette()
    @MainActor
    func testStopStartRebindsClearAllCallbackExactlyOnce()
    @MainActor
    func testStopClearsDisplaySyncCallbackAndRestartBindsExactlyOnce()

The metadata test calls the read-only ControlMetadataProviding.metadata() and asserts nonempty identifier/name/help, role, value for sliders/popups, enabled state, and keyboard reachability for both palette and menu hierarchy. The checkpoint test records exact counts before stop, after stop, and after restart; it must not use a single aggregate count.

- [ ] **Step 2: Run focused tests and verify RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'AccessibilityMetadataTests|PaletteInteractionTests|PointerApplicationControllerTests'

Expected: failures identify missing roles/values/focus/checkpoint state or duplicate observer/callback/window resources.

- [ ] **Step 3: Implement metadata and appearance adaptation.**

Set accessibilityRoleDescription for controls where AppKit does not infer it, accessibilityValue for numeric sliders and selected tool/mode, and explicit disabled help. Keep selected state visible through title/image/state and focus ring. Re-run applyDisplayOptions when appearance/accessibility settings change without resizing or moving the palette.

- [ ] **Step 4: Implement checkpoint instrumentation only within C-owned objects.**

Track observer token, palette visibility, menu status item, shortcut callback/timer wiring, and guide visibility using weak references or explicit ownership flags. stop() must call B's DisplayCoordinator.stop() and require zero returned overlays/handlers before hiding palette/menu/guide. start() rebuilds the bindings once and calls synchronize; no controller may retain a closed panel or stale guide display-loss intent.

- [ ] **Step 5: Run complete C verification.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
    git diff --check

Expected: PASS with accessibility metadata, keyboard, appearance, feedback, no-display, guide order, shortcut, and lifecycle checkpoint coverage.

## Task 6: Worker/reviewer/adversarial reconciliation gate

**Files:**

- Modify only files listed in Tasks 1–5 after a finding is accepted.
- Evidence handoff: coordinator-owned review record; no commit or publication from this worker.

- [ ] **Step 1: Check disjoint scope.**

    git status --short
    git diff --name-only -- Sources/PointerAppKit/Palette Sources/PointerAppKit/CommandRouter.swift Sources/PointerAppKit/MenuBarController.swift Sources/PointerAppKit/PointerApplication.swift Sources/PointerAppKit/PointerApplicationController.swift Sources/PointerAppKit/Shortcuts Sources/PointerAppKit/Help/FirstUseGuidePresenting.swift Tests/PointerAppKitTests

Expected: no B core/display, A diagnostics/TestSupport, D concrete guide/assets, E performance, or F composition/build path appears in C's worker diff.

- [ ] **Step 2: Run focused and full verification.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'CommandRouterTests|PaletteLayoutTests|PaletteInteractionTests|GuideIntegrationTests|HotKeyControllerTests|ShortcutLifecycleTests|AccessibilityMetadataTests|PointerApplicationControllerTests'
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

Expected: PASS with no duplicate callbacks, no hidden annotation-entry mutation, no missing metadata, and no lifecycle leaks in deterministic checkpoints.

- [ ] **Step 3: Handoff to the configured Luna reviewer.**

Include changed paths, exact public protocol/initializer signatures, command route tests, palette screenshots if available, metadata inventory, keyboard/appearance evidence class, and the explicit statement that D's concrete guide is not imported. Reviewer returns REVISE with exact findings or APPROVED only when the product surface is compact and all action/error states are understandable.

- [ ] **Step 4: After reviewer approval, run adversarial Codex review.**

Challenge no-display annotation rejection, mode/tool mutation, guide order and Escape precedence, shortcut timeout/late events, duplicate restart delivery, focus loss, narrow width, disabled controls, color-only state, Reduce Transparency, Increase Contrast, and accidental C→D dependency.

- [ ] **Step 5: Reconcile until worker, reviewer, and Codex agree.**

Return every finding to the smallest C-owned path, rerun RED/GREEN tests, obtain reviewer re-approval, and rerun adversarial checks. Report RECONCILED only when the common path has no new click caused by C and all blockers/high-severity accessibility or lifecycle findings are closed.

## Plan self-check

- Palette result, no-display behavior, contextual Delete, style relevance, narrow layout, keyboard routing, guide protocol/order, Escape precedence, shortcut transactions, accessibility metadata, appearance, and running/stopped/restarted checkpoints map to Tasks 1–5.
- Names are consistent: PaletteShowResult.shown(GuidePlacementContext), PalettePresenting.show(on:), GuidePresentationResult.shown/notNeeded/failed, FirstUseGuidePresenting.showIfNeeded(in:)/show(in:)/restoreAfterDisplayLoss(in:), GuidePlacementContext/GuidePlacementProviding, B-owned PointerSession.selectedDisplay, ControlMetadata/ControlMetadataProviding, CommandRouter.activeShortcutID/shortcutError/onAnnotationEntry/updateDisplayState/clearCallbacks/bindCallbacks, DisplaySyncResult, DisplayStopResult, nonoptional shortcutController, and the explicit controller initializer.
- No task modifies D's guide implementation, F's composition root, B's lifecycle source, A's diagnostics, or E's performance harness; no commit instruction is included.
