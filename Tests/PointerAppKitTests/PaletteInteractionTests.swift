import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class PaletteInteractionTests: XCTestCase {
    func testPaletteShowReturnsExplicitNoDisplayOrShown() {
        let provider = PaletteInteractionScreenProvider(displays: [])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let placementProvider = GuidePlacementProvider()
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: placementProvider
        )
        XCTAssertTrue(palette.guidePlacementProvider === placementProvider)
        let presenting: any PalettePresenting = palette
        XCTAssertTrue(presenting.guidePlacementProvider === placementProvider)

        let invalid = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "invalid"),
            frame: DisplayFrame(x: 0, y: 0, width: 0, height: 0),
            visibleFrame: DisplayFrame(x: 0, y: 0, width: 0, height: 0),
            scaleFactor: 1
        )
        XCTAssertEqual(palette.show(on: invalid), .noDisplay)
        XCTAssertEqual(palette.appearanceObserverCount, 0)

        let descriptor = PaletteInteractionScreenProvider.descriptor()
        guard case .shown = palette.show(on: descriptor) else {
            return XCTFail("Expected shown(GuidePlacementContext)")
        }
        XCTAssertEqual(palette.appearanceObserverCount, 1)
    }

    func testPaletteShowFailureAfterOrderingOrdersPaletteOut() {
        let descriptor = PaletteInteractionScreenProvider.descriptor()
        let provider = PaletteInteractionScreenProvider(displays: [descriptor])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: NilGuidePlacementProvider()
        )
        defer { palette.close() }

        guard case .failed = palette.show(on: descriptor) else {
            return XCTFail("Expected injected provider failure")
        }
        XCTAssertFalse(palette.isVisible)
        XCTAssertEqual(palette.appearanceObserverCount, 0)
    }

    func testPaletteShowFailsAndStaysHiddenWhenPositiveFrameCannotFitNativeLayout() {
        let descriptor = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "tiny"),
            frame: DisplayFrame(x: 0, y: 0, width: 10, height: 10),
            visibleFrame: DisplayFrame(x: 0, y: 0, width: 10, height: 10),
            scaleFactor: 2
        )
        let provider = PaletteInteractionScreenProvider(displays: [descriptor])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: GuidePlacementProvider()
        )
        defer { palette.close() }

        XCTAssertTrue({
            if case .shown = palette.show(on: PaletteInteractionScreenProvider.descriptor()) {
                return true
            }
            return false
        }())
        guard case .failed = palette.show(on: descriptor) else {
            return XCTFail("Expected native layout failure")
        }
        XCTAssertFalse(palette.isVisible)
    }

    func testPaletteShowSupportsNarrowDisplayThatFitsNativeLayout() {
        let descriptor = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "narrow"),
            frame: DisplayFrame(x: 0, y: 0, width: 420, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 420, height: 1_056),
            scaleFactor: 2
        )
        let provider = PaletteInteractionScreenProvider(displays: [descriptor])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: GuidePlacementProvider()
        )
        defer { palette.close() }

        guard case .shown = palette.show(on: descriptor) else {
            return XCTFail("Expected supported narrow display")
        }
        XCTAssertTrue(palette.isVisible)
    }

    func testTooSmallDirectShowDoesNotLeaveAppearanceObserverOnHiddenPalette() {
        let descriptor = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "tiny-fresh"),
            frame: DisplayFrame(x: 0, y: 0, width: 10, height: 10),
            visibleFrame: DisplayFrame(x: 0, y: 0, width: 10, height: 10),
            scaleFactor: 2
        )
        let provider = PaletteInteractionScreenProvider(displays: [descriptor])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: GuidePlacementProvider()
        )
        defer { palette.close() }

        guard case .failed = palette.show(on: descriptor) else {
            return XCTFail("Expected native layout failure")
        }
        XCTAssertFalse(palette.isVisible)
        XCTAssertEqual(palette.appearanceObserverCount, 0)
    }

    func testEveryHiddenPalettePathStopsObservationAndAllowsReShow() {
        let display = PaletteInteractionScreenProvider.descriptor()
        let provider = PaletteInteractionScreenProvider(displays: [display])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let placementProvider = ObservingGuidePlacementProvider()
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: placementProvider
        )
        placementProvider.palette = palette
        defer { palette.close() }

        let invalid = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "invalid-hidden-path"),
            frame: DisplayFrame(x: 0, y: 0, width: 0, height: 0),
            visibleFrame: DisplayFrame(x: 0, y: 0, width: 0, height: 0),
            scaleFactor: 1
        )
        let tiny = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "tiny-hidden-path"),
            frame: DisplayFrame(x: 0, y: 0, width: 10, height: 10),
            visibleFrame: DisplayFrame(x: 0, y: 0, width: 10, height: 10),
            scaleFactor: 2
        )

        guard case .shown = palette.show(on: display) else {
            return XCTFail("Expected initial palette show")
        }
        XCTAssertEqual(palette.appearanceObserverCount, 1)

        XCTAssertEqual(palette.show(on: invalid), .noDisplay)
        XCTAssertFalse(palette.isVisible)
        XCTAssertEqual(palette.appearanceObserverCount, 0)
        guard case .shown = palette.show(on: display) else {
            return XCTFail("Expected re-show after no-display failure")
        }
        XCTAssertEqual(palette.appearanceObserverCount, 1)

        guard case .failed = palette.show(on: tiny) else {
            return XCTFail("Expected too-small display failure")
        }
        XCTAssertFalse(palette.isVisible)
        XCTAssertEqual(palette.appearanceObserverCount, 0)
        guard case .shown = palette.show(on: display) else {
            return XCTFail("Expected re-show after too-small failure")
        }
        XCTAssertEqual(palette.appearanceObserverCount, 1)

        placementProvider.shouldReturnContext = false
        guard case .failed = palette.show(on: display) else {
            return XCTFail("Expected nil placement failure")
        }
        XCTAssertFalse(palette.isVisible)
        XCTAssertEqual(palette.appearanceObserverCount, 0)
        placementProvider.shouldReturnContext = true
        guard case .shown = palette.show(on: display) else {
            return XCTFail("Expected re-show after placement failure")
        }
        XCTAssertEqual(palette.appearanceObserverCount, 1)

        palette.hide()
        XCTAssertFalse(palette.isVisible)
        XCTAssertEqual(palette.appearanceObserverCount, 0)
        guard case .shown = palette.show(on: display) else {
            return XCTFail("Expected re-show after direct hide")
        }
        XCTAssertEqual(palette.appearanceObserverCount, 1)
    }

    func testPaletteFeedbackImmediatelyUpdatesVisibleStatusAndRefreshRestoresNormalStatus() {
        let provider = PaletteInteractionScreenProvider(displays: [])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let controller = PaletteViewController(router: router)
        controller.loadViewIfNeeded()

        router.route(.setTool(.spotlight))

        XCTAssertEqual(controller.statusMessage, "No presentation display connected")

        router.route(.setStyle(.default))
        controller.refresh(session: router.session)

        XCTAssertEqual(controller.statusMessage, "Standby — overlays are click-through")
    }

    func testNoDisplayNoOpFeedbackUpdatesStatusAccessibilityValueWithoutRefresh() throws {
        let provider = PaletteInteractionScreenProvider(displays: [])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: GuidePlacementProvider()
        )
        palette.paletteViewController.loadViewIfNeeded()
        let status = palette.paletteViewController.control(identifier: "palette.status")

        router.route(.setTool(.spotlight))
        XCTAssertEqual(palette.paletteViewController.statusMessage, "No presentation display connected")
        XCTAssertEqual(status.accessibilityValue() as? String, palette.paletteViewController.statusMessage)

        router.route(.clear)
        XCTAssertEqual(palette.paletteViewController.statusMessage, "Nothing to clear")
        XCTAssertEqual(status.accessibilityValue() as? String, palette.paletteViewController.statusMessage)
        XCTAssertEqual(
            ControlMetadataInventory(palette: palette, menuBar: nil)
                .metadata()
                .first { $0.identifier == "palette.status" }?.value,
            "Nothing to clear"
        )
    }

    func testValidReconnectClearsOnlyStaleNoDisplayStatus() {
        let provider = PaletteInteractionScreenProvider(displays: [])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: GuidePlacementProvider()
        )
        palette.paletteViewController.loadViewIfNeeded()

        router.route(.setTool(.spotlight))
        XCTAssertEqual(
            palette.paletteViewController.statusMessage,
            "No presentation display connected"
        )

        let uuid = DisplayUUID(rawValue: "reconnected-display")
        router.updateDisplayState(DisplaySyncResult(
            connectedUUIDs: [uuid],
            addedUUIDs: [uuid],
            removedUUIDs: [],
            pointerDisplay: uuid,
            hasConnectedDisplays: true,
            enteredZeroDisplayState: false,
            reconnected: true
        ))
        palette.refresh(session: router.session)

        XCTAssertEqual(
            palette.paletteViewController.statusMessage,
            "Standby — overlays are click-through"
        )
    }

    func testShortcutErrorKeepsPriorityOverFeedbackAndRestoresNormalStatus() throws {
        _ = NSApplication.shared
        let display = PaletteInteractionScreenProvider.descriptor()
        let provider = PaletteInteractionScreenProvider(displays: [display])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let registrar = PaletteShortcutRegistrar()
        let shortcutController = HotKeyController(
            registrar: registrar,
            store: PaletteShortcutStore(),
            scheduler: PaletteShortcutScheduler()
        )
        let router = CommandRouter(
            coordinator: coordinator,
            screenProvider: provider,
            shortcutController: shortcutController
        )
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: GuidePlacementProvider()
        )
        defer { palette.close() }
        _ = coordinator.synchronize()
        guard case .shown = palette.show(on: display) else {
            return XCTFail("Expected palette to be shown")
        }
        shortcutController.start()
        registrar.shouldFail = true
        shortcutController.setShortcut(.controlOptionCommandO)
        palette.paletteViewController.refresh(session: router.session)

        let focusedControl = palette.paletteViewController.control(identifier: "palette.mode")
        XCTAssertTrue(palette.makeFirstResponder(focusedControl))
        let origin = palette.frame.origin
        let firstResponder = palette.firstResponder
        let errorStatus = palette.paletteViewController.statusMessage
        XCTAssertTrue(errorStatus.hasPrefix("Shortcut unavailable:"))

        router.route(.setMode(.annotation))
        router.route(.delete)

        XCTAssertEqual(palette.paletteViewController.statusMessage, errorStatus)
        XCTAssertEqual(palette.frame.origin, origin)
        XCTAssertTrue(palette.firstResponder === firstResponder)

        shortcutController.stop()
        registrar.shouldFail = false
        shortcutController.start()
        palette.paletteViewController.refresh(session: router.session)
        palette.paletteViewController.refresh(session: router.session)

        XCTAssertEqual(
            palette.paletteViewController.statusMessage,
            "Annotation enabled · Shortcut: control-option-command-p"
        )
    }

    func testOverflowRefreshKeepsMenuIdentityAndFocusForContinuousStateUpdates() throws {
        let descriptor = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "overflow-stability"),
            frame: DisplayFrame(x: 0, y: 0, width: 452, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 452, height: 1_056),
            scaleFactor: 2
        )
        let provider = PaletteInteractionScreenProvider(displays: [descriptor])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        _ = coordinator.synchronize()
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: GuidePlacementProvider()
        )
        defer { palette.close() }
        guard case .shown = palette.show(on: descriptor) else {
            return XCTFail("Expected supported overflow width")
        }
        var session = router.session
        session.apply(.setMode(.annotation))
        session.apply(.setTool(.spotlight))
        palette.refresh(session: session)
        palette.window.contentView?.layoutSubtreeIfNeeded()
        let overflow = try XCTUnwrap(palette.paletteViewController.control(identifier: "palette.tools.overflow") as? NSPopUpButton)
        let originalItems = try XCTUnwrap(overflow.menu?.items)
        let originalHeaderTitle = overflow.title
        XCTAssertTrue(palette.makeFirstResponder(overflow))

        for radius in [0.2, 0.3, 0.4] {
            session.apply(.setSpotlight(radius: radius, dimness: 0.7))
            palette.refresh(session: session)
            palette.window.contentView?.layoutSubtreeIfNeeded()
        }

        XCTAssertEqual(overflow.title, originalHeaderTitle)
        XCTAssertTrue(palette.firstResponder === overflow)
        XCTAssertEqual(overflow.menu?.items.count, originalItems.count)
        for (current, original) in zip(overflow.menu?.items ?? [], originalItems) {
            XCTAssertTrue(current === original)
        }
        XCTAssertTrue((overflow.accessibilityValue() as? String)?.contains("Spotlight") == true)

        session.apply(.setTool(.pen))
        palette.refresh(session: session)
        palette.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertFalse(overflow.menu?.items.first === originalItems.first)
    }

    func testPaletteUndoAndClearDisableWhenAcceptedPointerDisplayDisconnects() throws {
        let descriptor = PaletteInteractionScreenProvider.descriptor()
        let provider = PaletteInteractionScreenProvider(displays: [descriptor])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        _ = coordinator.synchronize()
        let mark = Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.1),
                end: NormalizedPoint(x: 0.8, y: 0.8)
            ),
            style: .default
        )
        coordinator.apply(.append(mark, to: descriptor.uuid))

        let controller = PaletteViewController(router: router)
        controller.loadViewIfNeeded()
        controller.refresh(session: coordinator.session)
        let undo = try XCTUnwrap(control(in: controller, identifier: "palette.undo"))
        let clear = try XCTUnwrap(control(in: controller, identifier: "palette.clear"))
        XCTAssertTrue(undo.isEnabled)
        XCTAssertTrue(clear.isEnabled)

        router.updateDisplayState(DisplaySyncResult(
            connectedUUIDs: [],
            addedUUIDs: [],
            removedUUIDs: [descriptor.uuid],
            pointerDisplay: nil,
            hasConnectedDisplays: false,
            enteredZeroDisplayState: true,
            reconnected: false
        ))
        controller.refresh(session: coordinator.session)

        XCTAssertFalse(undo.isEnabled)
        XCTAssertFalse(clear.isEnabled)
    }

    private func control(
        in controller: PaletteViewController,
        identifier: String
    ) -> NSControl? {
        controller.controls.first { $0.identifier?.rawValue == identifier }
    }

    func testGuidePlacementProviderRejectsInvalidFramesAndReturnsExactContext() {
        let provider = GuidePlacementProvider()
        let display = PaletteInteractionScreenProvider.descriptor()
        let paletteFrame = DisplayFrame(
            x: display.visibleFrame.x + 10,
            y: display.visibleFrame.y + 10,
            width: 100,
            height: 40
        )

        XCTAssertNil(provider.context(
            for: DisplayDescriptor(
                uuid: display.uuid,
                frame: display.frame,
                visibleFrame: DisplayFrame(x: 0, y: 0, width: 0, height: 100),
                scaleFactor: 2
            ),
            paletteFrame: paletteFrame
        ))
        XCTAssertNil(provider.context(
            for: display,
            paletteFrame: DisplayFrame(x: 0, y: 0, width: 0, height: 40)
        ))

        XCTAssertEqual(
            provider.context(for: display, paletteFrame: paletteFrame),
            GuidePlacementContext(
                display: display,
                visibleFrame: display.visibleFrame,
                paletteFrame: paletteFrame,
                avoidanceFrames: [paletteFrame]
            )
        )
    }

    func testDeleteAffordanceRequiresAnnotationAndSelection() {
        let descriptor = PaletteInteractionScreenProvider.descriptor()
        let provider = PaletteInteractionScreenProvider(displays: [descriptor])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        let controller = PaletteViewController(router: router)
        controller.loadViewIfNeeded()

        controller.refresh(session: router.session)
        XCTAssertFalse(controller.deleteButton.isEnabled)

        var session = router.session
        session.ensureCanvas(for: descriptor.uuid)
        session.apply(.setMode(.annotation))
        controller.refresh(session: session)
        XCTAssertFalse(controller.deleteButton.isEnabled)

        let mark = Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.1),
                end: NormalizedPoint(x: 0.8, y: 0.8)
            ),
            style: .default
        )
        session.apply(.append(mark, to: descriptor.uuid))
        session.apply(.setTool(.select))
        _ = session.beginGesture(
            tool: .select,
            at: NormalizedPoint(x: 0.5, y: 0.5),
            on: descriptor.uuid
        )
        _ = session.commitGesture()
        controller.refresh(session: session)
        XCTAssertTrue(controller.deleteButton.isEnabled)

        session.apply(.setMode(.standby))
        controller.refresh(session: session)
        XCTAssertFalse(controller.deleteButton.isEnabled)
    }

    func testRelevantStyleControlsAreEnabledAndIrrelevantControlsExplainDisabledState() {
        let controller = PaletteViewController(router: makeRouter())
        controller.loadViewIfNeeded()

        var session = controllerSession(tool: .arrow, mode: .annotation)
        controller.refresh(session: session)
        XCTAssertTrue(controller.control(identifier: "palette.style.color").isEnabled)
        XCTAssertFalse(controller.control(identifier: "palette.spotlight.radius").isEnabled)
        XCTAssertTrue(
            controller.control(identifier: "palette.spotlight.radius")
                .accessibilityHelp()?.contains("Spotlight") == true
        )

        session = controllerSession(tool: .spotlight, mode: .annotation)
        controller.refresh(session: session)
        XCTAssertFalse(controller.control(identifier: "palette.style.color").isEnabled)
        XCTAssertTrue(controller.control(identifier: "palette.spotlight.radius").isEnabled)
    }

    func testSliderValuesAreExposedAsAccessibleValues() {
        let controller = PaletteViewController(router: makeRouter())
        controller.loadViewIfNeeded()

        var session = controllerSession(tool: .arrow, mode: .annotation)
        session.apply(.setStyle(MarkStyle(color: .red, strokeWidth: 8, opacity: 0.75)))
        session.apply(.setSpotlight(radius: 0.3, dimness: 0.65))
        controller.refresh(session: session)

        XCTAssertEqual(
            controller.control(identifier: "palette.style.stroke-width").accessibilityValue() as? String,
            "8"
        )
        XCTAssertEqual(
            controller.control(identifier: "palette.style.opacity").accessibilityValue() as? String,
            "75%"
        )
        XCTAssertEqual(
            controller.control(identifier: "palette.spotlight.radius").accessibilityValue() as? String,
            "30%"
        )
        XCTAssertEqual(
            controller.control(identifier: "palette.spotlight.dimness").accessibilityValue() as? String,
            "65%"
        )
    }

    func testControlMetadataInventoryIsReadOnlyAndDeterministic() {
        let palette = PalettePanel(
            router: makeRouter(),
            guidePlacementProvider: GuidePlacementProvider()
        )
        palette.paletteViewController.loadViewIfNeeded()
        let inventory = ControlMetadataInventory(palette: palette, menuBar: nil)

        let first = inventory.metadata()
        let second = inventory.metadata()

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.identifier), palette.paletteViewController.controls.compactMap { $0.identifier?.rawValue })
        XCTAssertTrue(first.allSatisfy {
            !$0.identifier.isEmpty && !$0.accessibleName.isEmpty && !$0.role.isEmpty
        })
        XCTAssertFalse(first.first { $0.identifier == "palette.status" }?.isKeyboardReachable ?? true)
        XCTAssertTrue(first.first { $0.identifier == "palette.style.stroke-width" }?.value != nil)
    }

    func testControlMetadataInventoryIncludesInstalledMenuHierarchyAfterPaletteRows() {
        let router = makeRouter()
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: GuidePlacementProvider()
        )
        let menuBar = MenuBarController(router: router)
        menuBar.install()
        defer { menuBar.remove() }

        let identifiers = ControlMetadataInventory(palette: palette, menuBar: menuBar)
            .metadata()
            .map(\.identifier)

        XCTAssertEqual(identifiers.first, "palette.mode")
        XCTAssertTrue(identifiers.contains("pointer.menu-bar"))
        XCTAssertTrue(identifiers.contains("menu.show-palette"))
        XCTAssertTrue(identifiers.contains("menu.shortcut"))
        XCTAssertTrue(identifiers.contains("menu.shortcut.control-option-command-p"))
        XCTAssertTrue(identifiers.contains("menu.quit"))

        let metadata = ControlMetadataInventory(palette: palette, menuBar: menuBar).metadata()
        XCTAssertTrue(metadata.allSatisfy {
            !$0.identifier.isEmpty
                && !$0.accessibleName.isEmpty
                && $0.help?.isEmpty == false
                && !$0.role.isEmpty
        })
    }

    func testMetadataUsesHonestKeyboardReachabilityForDisabledAndHiddenControls() {
        let router = makeRouter()
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: GuidePlacementProvider()
        )
        palette.paletteViewController.loadViewIfNeeded()
        palette.paletteViewController.refresh(session: controllerSession(tool: .arrow, mode: .annotation))

        let metadata = ControlMetadataInventory(palette: palette, menuBar: nil).metadata()
        XCTAssertFalse(metadata.first { $0.identifier == "palette.status" }?.isKeyboardReachable ?? true)
        XCTAssertFalse(metadata.first { $0.identifier == "palette.spotlight.radius" }?.isKeyboardReachable ?? true)
        XCTAssertFalse(metadata.first { $0.identifier == "palette.spotlight.radius" }?.isEnabled ?? true)
    }

    func testSelectedCompatibleMarksEnableContextualControlsWithAcceptedDisplay() {
        let fixture = acceptedFixture()
        let controller = PaletteViewController(router: fixture.router)
        controller.loadViewIfNeeded()

        let selectedGeometries: [(MarkGeometry, NormalizedPoint)] = [
            (
                .rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)),
                NormalizedPoint(x: 0.2, y: 0.4)
            ),
            (
                .freehand([
                    NormalizedPoint(x: 0.2, y: 0.2),
                    NormalizedPoint(x: 0.4, y: 0.4),
                ]),
                NormalizedPoint(x: 0.3, y: 0.3)
            ),
        ]
        for (geometry, hitPoint) in selectedGeometries {
            let session = selectedSession(
                geometry: geometry,
                hitPoint: hitPoint,
                display: fixture.display
            )
            controller.refresh(session: session)
            XCTAssertTrue(controller.control(identifier: "palette.style.color").isEnabled)
            XCTAssertTrue(controller.control(identifier: "palette.style.stroke-width").isEnabled)
            XCTAssertTrue(controller.control(identifier: "palette.style.opacity").isEnabled)
        }
    }

    func testSelectedSpecializedMarksEnableOnlyTheirContextualControls() {
        let fixture = acceptedFixture()
        let controller = PaletteViewController(router: fixture.router)
        controller.loadViewIfNeeded()

        let emoji = selectedSession(
            geometry: .emoji(
                text: "👉",
                rect: NormalizedRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)
            ),
            hitPoint: NormalizedPoint(x: 0.3, y: 0.3),
            display: fixture.display
        )
        controller.refresh(session: emoji)
        XCTAssertTrue(controller.control(identifier: "palette.emoji").isEnabled)
        XCTAssertFalse(controller.control(identifier: "palette.style.color").isEnabled)
        XCTAssertFalse(controller.control(identifier: "palette.spotlight.radius").isEnabled)

        let spotlight = selectedSession(
            geometry: .spotlight(
                center: NormalizedPoint(x: 0.4, y: 0.4),
                radius: 0.15,
                dimness: 0.5
            ),
            hitPoint: NormalizedPoint(x: 0.4, y: 0.4),
            display: fixture.display
        )
        controller.refresh(session: spotlight)
        XCTAssertFalse(controller.control(identifier: "palette.emoji").isEnabled)
        XCTAssertFalse(controller.control(identifier: "palette.style.color").isEnabled)
        XCTAssertTrue(controller.control(identifier: "palette.spotlight.radius").isEnabled)
        XCTAssertTrue(controller.control(identifier: "palette.spotlight.dimness").isEnabled)
    }

    func testSelectedDisplayWinsWhenPointerDisplayMovesToAnotherDisplay() {
        let fixture = crossDisplayFixture()
        let controller = PaletteViewController(router: fixture.router)
        controller.loadViewIfNeeded()

        let rectangle = selectedSession(
            geometry: .rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)),
            hitPoint: NormalizedPoint(x: 0.2, y: 0.4),
            display: fixture.selectedDisplay
        )
        controller.refresh(session: rectangle)
        XCTAssertTrue(controller.control(identifier: "palette.style.color").isEnabled)
        XCTAssertTrue(controller.deleteButton.isEnabled)

        let emoji = selectedSession(
            geometry: .emoji(
                text: "👉",
                rect: NormalizedRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)
            ),
            hitPoint: NormalizedPoint(x: 0.3, y: 0.3),
            display: fixture.selectedDisplay
        )
        controller.refresh(session: emoji)
        XCTAssertTrue(controller.control(identifier: "palette.emoji").isEnabled)
        XCTAssertFalse(controller.control(identifier: "palette.style.color").isEnabled)
        XCTAssertTrue(controller.deleteButton.isEnabled)

        let spotlight = selectedSession(
            geometry: .spotlight(
                center: NormalizedPoint(x: 0.4, y: 0.4),
                radius: 0.15,
                dimness: 0.5
            ),
            hitPoint: NormalizedPoint(x: 0.4, y: 0.4),
            display: fixture.selectedDisplay
        )
        controller.refresh(session: spotlight)
        XCTAssertTrue(controller.control(identifier: "palette.spotlight.radius").isEnabled)
        XCTAssertFalse(controller.control(identifier: "palette.style.color").isEnabled)
        XCTAssertTrue(controller.deleteButton.isEnabled)
    }

    func testSelectedCompatibleMarkValuesAndActionsPreserveCompositeStyle() throws {
        let selectedStyle = MarkStyle(
            color: RGBAColor(red: 0.1, green: 0.2, blue: 0.9),
            strokeWidth: 13,
            opacity: 0.42
        )
        for geometry in [
            MarkGeometry.rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)),
            MarkGeometry.freehand([
                NormalizedPoint(x: 0.2, y: 0.2),
                NormalizedPoint(x: 0.4, y: 0.4),
            ]),
        ] {
            let fixture = selectedMarkFixture(
                geometry: geometry,
                style: selectedStyle,
                hitPoint: geometryHitPoint(for: geometry)
            )
            let controller = PaletteViewController(router: fixture.router)
            controller.loadViewIfNeeded()
            controller.refresh(session: fixture.router.session)
            let stroke = try XCTUnwrap(controller.control(identifier: "palette.style.stroke-width") as? NSSlider)
            let opacity = try XCTUnwrap(controller.control(identifier: "palette.style.opacity") as? NSSlider)
            let colorWell = try XCTUnwrap(controller.control(identifier: "palette.style.color") as? NSColorWell)
            XCTAssertEqual(stroke.doubleValue, selectedStyle.strokeWidth)
            XCTAssertEqual(opacity.doubleValue, selectedStyle.opacity)
            XCTAssertEqual(
                colorWell.accessibilityValue() as? String,
                "RGBA 0.1, 0.2, 0.9"
            )

            stroke.doubleValue = 17
            sendAction(stroke)
            opacity.doubleValue = 0.63
            sendAction(opacity)

            let updated = try XCTUnwrap(
                fixture.router.session.canvas(for: fixture.display.uuid).marks.first {
                    $0.id == fixture.markID
                }
            )
            XCTAssertEqual(updated.style.color, selectedStyle.color)
            XCTAssertEqual(updated.style.strokeWidth, 17)
            XCTAssertEqual(updated.style.opacity, 0.63)
            XCTAssertEqual(fixture.router.session.toolState.style, updated.style)
        }
    }

    func testSelectedEmojiAndSpotlightValuesDriveActionsWithoutOverwritingOtherProperties() throws {
        let emojiFixture = selectedMarkFixture(
            geometry: .emoji(
                text: "✅",
                rect: NormalizedRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)
            ),
            style: .default,
            hitPoint: NormalizedPoint(x: 0.3, y: 0.3),
            futureEmoji: "👉"
        )
        let emojiController = PaletteViewController(router: emojiFixture.router)
        emojiController.loadViewIfNeeded()
        emojiController.refresh(session: emojiFixture.router.session)
        let emoji = try XCTUnwrap(emojiController.control(identifier: "palette.emoji") as? NSPopUpButton)
        XCTAssertEqual(emoji.titleOfSelectedItem, "✅")
        emoji.selectItem(withTitle: "⭐️")
        sendAction(emoji)
        let updatedEmoji = try XCTUnwrap(
            emojiFixture.router.session.canvas(for: emojiFixture.display.uuid).marks.first {
                $0.id == emojiFixture.markID
            }
        )
        guard case let .emoji(text, _) = updatedEmoji.geometry else {
            return XCTFail("Expected selected emoji mark")
        }
        XCTAssertEqual(text, "⭐️")
        XCTAssertEqual(emojiFixture.router.session.toolState.emoji, "⭐️")

        let spotlightFixture = selectedMarkFixture(
            geometry: .spotlight(
                center: NormalizedPoint(x: 0.4, y: 0.4),
                radius: 0.4,
                dimness: 0.8
            ),
            style: .default,
            hitPoint: NormalizedPoint(x: 0.4, y: 0.4),
            futureSpotlight: (radius: 0.15, dimness: 0.25)
        )
        let spotlightController = PaletteViewController(router: spotlightFixture.router)
        spotlightController.loadViewIfNeeded()
        spotlightController.refresh(session: spotlightFixture.router.session)
        let radius = try XCTUnwrap(spotlightController.control(identifier: "palette.spotlight.radius") as? NSSlider)
        let dimness = try XCTUnwrap(spotlightController.control(identifier: "palette.spotlight.dimness") as? NSSlider)
        XCTAssertEqual(radius.doubleValue, 0.4)
        XCTAssertEqual(dimness.doubleValue, 0.8)
        radius.doubleValue = 0.6
        sendAction(radius)
        let updatedSpotlight = try XCTUnwrap(
            spotlightFixture.router.session.canvas(for: spotlightFixture.display.uuid).marks.first {
                $0.id == spotlightFixture.markID
            }
        )
        guard case let .spotlight(_, updatedRadius, updatedDimness) = updatedSpotlight.geometry else {
            return XCTFail("Expected selected spotlight mark")
        }
        XCTAssertEqual(updatedRadius, 0.6)
        XCTAssertEqual(updatedDimness, 0.8)
        XCTAssertEqual(spotlightFixture.router.session.toolState.spotlightRadius, 0.6)
        XCTAssertEqual(spotlightFixture.router.session.toolState.spotlightDimness, 0.8)
    }

    func testOverflowCommunicatesActivePenAndSpotlightWithCheckmarks() throws {
        let fixture = acceptedFixture()
        let controller = PaletteViewController(router: fixture.router)
        controller.loadViewIfNeeded()
        for tool in [PointerTool.pen, .spotlight] {
            var session = fixture.router.session
            session.apply(.setMode(.annotation))
            session.apply(.setTool(tool))
            controller.refresh(session: session)
            controller.applyLayout(for: 420)
            controller.view.layoutSubtreeIfNeeded()

            let overflow = try XCTUnwrap(controller.control(identifier: "palette.tools.overflow") as? NSPopUpButton)
            XCTAssertFalse(overflow.isHidden)
            XCTAssertTrue(overflow.title.contains("More"))
            XCTAssertTrue(
                overflow.title.contains(tool.displayName)
                    || overflow.title.contains(tool == .spotlight ? "Spot" : "Pen")
            )
            XCTAssertGreaterThanOrEqual(overflow.frame.width, overflow.intrinsicContentSize.width)
            XCTAssertTrue((overflow.accessibilityValue() as? String)?.contains("\(tool.displayName)") == true)
            let item = try XCTUnwrap(overflow.menu?.items.first { $0.title == tool.displayName })
            XCTAssertEqual(item.state, .on)
            XCTAssertTrue(controller.control(identifier: "palette.tool.\(toolIdentifier(tool))").isHidden)
        }
    }

    func testEveryOverflowToolAt420UsesStablePullDownHeaderAndRepresentedIDRouting() throws {
        let fixture = acceptedFixture()
        let controller = PaletteViewController(router: fixture.router)
        controller.loadViewIfNeeded()
        let overflowedTools: [PointerTool] = [.rectangle, .ellipse, .pen, .eraser, .emoji, .spotlight]

        for tool in overflowedTools {
            var session = fixture.router.session
            session.apply(.setMode(.annotation))
            session.apply(.setTool(tool))
            controller.refresh(session: session)
            controller.applyLayout(for: 420)
            controller.view.layoutSubtreeIfNeeded()
            let overflow = try XCTUnwrap(controller.control(identifier: "palette.tools.overflow") as? NSPopUpButton)
            let items = try XCTUnwrap(overflow.menu?.items)
            XCTAssertTrue(overflow.pullsDown)
            XCTAssertEqual(items.count, overflowedTools.count + 1)
            XCTAssertEqual(items.first?.representedObject as? String, nil)
            XCTAssertFalse(items.first?.isEnabled == true)
            XCTAssertTrue(items.first?.title.contains("More") == true)
            XCTAssertGreaterThanOrEqual(overflow.frame.width, overflow.intrinsicContentSize.width)
            XCTAssertEqual(
                Set(items.dropFirst().map(\.title)),
                Set(overflowedTools.map(\.displayName))
            )
            for item in items.dropFirst() {
                XCTAssertEqual(item.representedObject as? String, toolIdentifier(forTitle: item.title))
                XCTAssertNotNil(item.action)
                XCTAssertNotNil(item.target)
            }
            let active = try XCTUnwrap(items.dropFirst().first { $0.title == tool.displayName })
            XCTAssertEqual(active.state, .on)

            XCTAssertTrue(NSApp.sendAction(active.action!, to: active.target, from: active))
            XCTAssertEqual(fixture.router.session.toolState.tool, tool)

            controller.refresh(session: fixture.router.session)
            controller.applyLayout(for: 420)
            controller.view.layoutSubtreeIfNeeded()
            let refreshed = try XCTUnwrap(controller.control(identifier: "palette.tools.overflow") as? NSPopUpButton)
            XCTAssertEqual(refreshed.menu?.items.count, items.count)
            XCTAssertEqual(
                Set(refreshed.menu?.items.dropFirst().map(\.title) ?? []),
                Set(overflowedTools.map(\.displayName))
            )
        }
    }

    func testNativeKeyViewTraversalMatchesReachableMetadataAtWideAndOverflowWidths() throws {
        for width in [420.0, PaletteLayout.minimumAllToolsWidth] {
            let fixture = acceptedFixture()
            let display = DisplayDescriptor(
                uuid: DisplayUUID(rawValue: "key-\(Int(width))"),
                frame: DisplayFrame(x: 0, y: 0, width: width + 32, height: 1_080),
                visibleFrame: DisplayFrame(x: 0, y: 24, width: width + 32, height: 1_056),
                scaleFactor: 2
            )
            let palette = PalettePanel(
                router: fixture.router,
                guidePlacementProvider: GuidePlacementProvider()
            )
            defer { palette.close() }
            guard case .shown = palette.show(on: display) else {
                return XCTFail("Expected palette at \(width)")
            }
            var session = fixture.router.session
            session.apply(.setMode(.annotation))
            session.apply(.setTool(.spotlight))
            palette.refresh(session: session)
            palette.window.contentView?.layoutSubtreeIfNeeded()

            let expected = ControlMetadataInventory(
                palette: palette,
                menuBar: nil
            ).metadata()
            .filter(\.isKeyboardReachable)
            .map(\.identifier)
            let start = palette.paletteViewController.control(identifier: "palette.mode")
            XCTAssertTrue(palette.makeFirstResponder(start))
            var actual = [start.identifier!.rawValue]
            for _ in 1..<expected.count {
                palette.selectNextKeyView(nil)
                let responder = try XCTUnwrap(palette.firstResponder as? NSView)
                actual.append(try XCTUnwrap(responder.identifier?.rawValue))
            }
            XCTAssertEqual(actual, expected)
        }
    }

    func testSelectWithoutSelectionDisablesSpecializedControlsAndDeleteIsHidden() {
        let fixture = acceptedFixture()
        let controller = PaletteViewController(router: fixture.router)
        controller.loadViewIfNeeded()
        var session = PointerSession()
        session.ensureCanvas(for: fixture.display.uuid)
        session.apply(.setMode(.annotation))
        session.apply(.setTool(.select))

        controller.refresh(session: session)
        XCTAssertFalse(controller.control(identifier: "palette.style.color").isEnabled)
        XCTAssertFalse(controller.control(identifier: "palette.emoji").isEnabled)
        XCTAssertFalse(controller.control(identifier: "palette.spotlight.radius").isEnabled)
        XCTAssertTrue(controller.control(identifier: "palette.style.color").accessibilityHelp()?.contains("Annotation color") == true)
        XCTAssertTrue(controller.control(identifier: "palette.emoji").accessibilityHelp()?.contains("Emoji") == true)
        XCTAssertTrue(controller.control(identifier: "palette.spotlight.radius").accessibilityHelp()?.contains("Spotlight") == true)
        XCTAssertTrue(controller.deleteButton.isHidden)
        XCTAssertFalse(controller.deleteButton.isEnabled)
    }

    func testNoSelectionKeepsActionsVisibleAndCollapsesDeleteUntilSelection() {
        let fixture = acceptedFixture()
        let controller = PaletteViewController(router: fixture.router)
        controller.loadViewIfNeeded()
        var noSelection = PointerSession()
        noSelection.ensureCanvas(for: fixture.display.uuid)
        noSelection.apply(.setMode(.annotation))
        noSelection.apply(.setTool(.select))
        controller.refresh(session: noSelection)
        controller.view.layoutSubtreeIfNeeded()

        for identifier in ["palette.undo", "palette.clear"] {
            let action = controller.control(identifier: identifier)
            XCTAssertFalse(action.isHidden, identifier)
            XCTAssertGreaterThanOrEqual(action.frame.width, 44, identifier)
            XCTAssertGreaterThanOrEqual(action.frame.height, 28, identifier)
        }
        XCTAssertTrue(controller.deleteButton.isHidden)
        XCTAssertEqual(controller.deleteButton.frame.width, 0, accuracy: 1)
        XCTAssertEqual(controller.deleteButton.frame.height, 0, accuracy: 1)

        let selected = selectedSession(
            geometry: .rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)),
            hitPoint: NormalizedPoint(x: 0.2, y: 0.4),
            display: fixture.display
        )
        controller.refresh(session: selected)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(controller.deleteButton.isHidden)
        XCTAssertTrue(controller.deleteButton.isEnabled)
        XCTAssertGreaterThanOrEqual(controller.deleteButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(controller.deleteButton.frame.height, 28)
    }

    func testRefreshPreservesPaletteOriginAndFirstResponder() throws {
        let fixture = acceptedFixture()
        let palette = PalettePanel(
            router: fixture.router,
            guidePlacementProvider: GuidePlacementProvider()
        )
        defer { palette.close() }
        guard case .shown = palette.show(on: fixture.display) else {
            return XCTFail("Expected palette to be shown")
        }
        let tool = palette.paletteViewController.control(identifier: "palette.tool.arrow")
        XCTAssertTrue(palette.makeFirstResponder(tool))
        let origin = palette.frame.origin
        let firstResponder = palette.firstResponder

        palette.refresh(session: controllerSession(tool: .arrow, mode: .annotation))

        XCTAssertEqual(palette.frame.origin, origin)
        XCTAssertTrue(palette.firstResponder === firstResponder)
    }

    func testReduceTransparencyAndIncreaseContrastChangeUsableVisualState() {
        var options = PaletteViewController.DisplayOptions(
            reduceTransparency: false,
            increaseContrast: false
        )
        let controller = PaletteViewController(
            router: makeRouter(),
            displayOptionsProvider: { options }
        )
        controller.loadViewIfNeeded()
        controller.startAppearanceObservation()
        let initialRefreshCount = controller.displayOptionsRefreshCount
        let originalFrame = controller.view.frame

        options = PaletteViewController.DisplayOptions(
            reduceTransparency: true,
            increaseContrast: true
        )
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        XCTAssertEqual(controller.displayOptionsRefreshCount, initialRefreshCount + 1)
        XCTAssertTrue(controller.isVisualEffectHidden)
        XCTAssertEqual(controller.appliedBorderWidth, 2)
        XCTAssertEqual(controller.view.layer?.backgroundColor?.alpha ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(controller.view.frame, originalFrame)

        options = PaletteViewController.DisplayOptions(
            reduceTransparency: false,
            increaseContrast: false
        )
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        XCTAssertFalse(controller.isVisualEffectHidden)
        XCTAssertEqual(controller.appliedBorderWidth, 1)
        XCTAssertEqual(controller.view.layer?.backgroundColor?.alpha ?? 0, 0.84, accuracy: 0.001)
    }

    func testEffectiveAppearanceReappliesResolvedColorsWithoutChangingFrameFocusOrObserver() throws {
        let fixture = acceptedFixture()
        let controller = PaletteViewController(
            router: fixture.router,
            displayOptionsProvider: {
                PaletteViewController.DisplayOptions(
                    reduceTransparency: false,
                    increaseContrast: true
                )
            }
        )
        controller.loadViewIfNeeded()
        controller.startAppearanceObservation()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = controller.view
        let focusedControl = controller.control(identifier: "palette.mode")
        XCTAssertTrue(window.makeFirstResponder(focusedControl))
        let root = try XCTUnwrap(controller.view as? PaletteRootView)
        let originalFrame = controller.view.frame
        let observerCount = controller.appearanceObserverCount

        root.appearance = NSAppearance(named: .aqua)
        root.viewDidChangeEffectiveAppearance()
        let aquaBackground = controller.view.layer?.backgroundColor?.components
        let aquaBorder = controller.view.layer?.borderColor?.components

        root.appearance = NSAppearance(named: .darkAqua)
        root.viewDidChangeEffectiveAppearance()
        let darkBackground = controller.view.layer?.backgroundColor?.components
        let darkBorder = controller.view.layer?.borderColor?.components

        XCTAssertNotEqual(aquaBackground, darkBackground)
        XCTAssertNotEqual(aquaBorder, darkBorder)
        XCTAssertEqual(controller.view.frame, originalFrame)
        XCTAssertTrue(window.firstResponder === focusedControl)
        XCTAssertEqual(controller.appearanceObserverCount, observerCount)
    }

    func testRestartingAppearanceObservationAppliesOptionsChangedWhileStopped() {
        var options = PaletteViewController.DisplayOptions(
            reduceTransparency: false,
            increaseContrast: false
        )
        let controller = PaletteViewController(
            router: makeRouter(),
            displayOptionsProvider: { options }
        )
        controller.loadViewIfNeeded()
        controller.stopAppearanceObservation()

        options = PaletteViewController.DisplayOptions(
            reduceTransparency: true,
            increaseContrast: true
        )
        controller.startAppearanceObservation()

        XCTAssertEqual(controller.appliedDisplayOptions, options)
        XCTAssertTrue(controller.isVisualEffectHidden)
        XCTAssertEqual(controller.view.layer?.backgroundColor?.alpha ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(controller.appliedBorderWidth, 2)
        XCTAssertEqual(controller.appearanceObserverCount, 1)
    }

    func testClosingAndShowingPaletteRestartsAppearanceObservation() throws {
        let fixture = acceptedFixture()
        let placementProvider = ObservingGuidePlacementProvider()
        let palette = PalettePanel(
            router: fixture.router,
            guidePlacementProvider: placementProvider
        )
        placementProvider.palette = palette
        defer { palette.close() }

        guard case .shown = palette.show(on: fixture.display) else {
            return XCTFail("Expected palette to be shown")
        }
        XCTAssertEqual(palette.appearanceObserverCount, 1)
        let refreshCount = palette.paletteViewController.displayOptionsRefreshCount

        placementProvider.observations.removeAll()
        guard case .shown = palette.show(on: fixture.display) else {
            return XCTFail("Expected palette to remain shown")
        }
        XCTAssertEqual(palette.paletteViewController.displayOptionsRefreshCount, refreshCount)
        XCTAssertEqual(placementProvider.observations.last?.refreshCount, refreshCount)

        palette.close()
        XCTAssertEqual(palette.appearanceObserverCount, 0)
        let refreshCountBeforeReshow = palette.paletteViewController.displayOptionsRefreshCount

        placementProvider.observations.removeAll()
        guard case .shown = palette.show(on: fixture.display) else {
            return XCTFail("Expected palette to be shown after close")
        }
        XCTAssertEqual(palette.appearanceObserverCount, 1)
        XCTAssertEqual(
            palette.paletteViewController.displayOptionsRefreshCount,
            refreshCountBeforeReshow + 1
        )
        XCTAssertEqual(
            placementProvider.observations.last?.refreshCount,
            refreshCountBeforeReshow + 1
        )
    }

    func testFeedbackDoesNotStealFocusOrMovePalette() throws {
        let fixture = acceptedFixture()
        let palette = PalettePanel(
            router: fixture.router,
            guidePlacementProvider: GuidePlacementProvider()
        )
        defer { palette.close() }
        guard case .shown = palette.show(on: fixture.display) else {
            return XCTFail("Expected palette to be shown")
        }

        let focusedControl = palette.paletteViewController.control(identifier: "palette.mode")
        XCTAssertTrue(palette.makeFirstResponder(focusedControl))
        let origin = palette.frame.origin
        let firstResponder = palette.firstResponder

        fixture.router.route(.clear)

        XCTAssertEqual(fixture.router.feedbackMessage, "Nothing to clear")
        XCTAssertEqual(palette.paletteViewController.statusMessage, "Nothing to clear")
        XCTAssertEqual(palette.frame.origin, origin)
        XCTAssertTrue(palette.firstResponder === firstResponder)
    }

    private func makeRouter() -> CommandRouter {
        let descriptor = PaletteInteractionScreenProvider.descriptor()
        let provider = PaletteInteractionScreenProvider(displays: [descriptor])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        return CommandRouter(coordinator: coordinator, screenProvider: provider)
    }

    private func controllerSession(tool: PointerTool, mode: PointerMode) -> PointerSession {
        var session = PointerSession()
        session.apply(.setMode(mode))
        session.apply(.setTool(tool))
        return session
    }

    private func acceptedFixture() -> (
        router: CommandRouter,
        coordinator: DisplayCoordinator,
        display: DisplayDescriptor
    ) {
        let display = PaletteInteractionScreenProvider.descriptor()
        let provider = PaletteInteractionScreenProvider(displays: [display])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        _ = coordinator.synchronize()
        return (router, coordinator, display)
    }

    private func crossDisplayFixture() -> (
        router: CommandRouter,
        selectedDisplay: DisplayDescriptor,
        pointerDisplay: DisplayDescriptor
    ) {
        let selectedDisplay = PaletteInteractionScreenProvider.descriptor()
        let pointerDisplay = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "display-b"),
            frame: DisplayFrame(x: 1_920, y: 0, width: 1_920, height: 1_080),
            visibleFrame: DisplayFrame(x: 1_920, y: 24, width: 1_920, height: 1_056),
            scaleFactor: 2
        )
        let provider = PaletteInteractionScreenProvider(
            displays: [selectedDisplay, pointerDisplay],
            pointerUUID: pointerDisplay.uuid
        )
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        _ = coordinator.synchronize()
        XCTAssertEqual(router.pointerDisplay, pointerDisplay.uuid)
        return (router, selectedDisplay, pointerDisplay)
    }

    private func selectedSession(
        geometry: MarkGeometry,
        hitPoint: NormalizedPoint,
        display: DisplayDescriptor
    ) -> PointerSession {
        var session = PointerSession()
        session.ensureCanvas(for: display.uuid)
        session.apply(.setMode(.annotation))
        session.apply(.append(Mark(geometry: geometry, style: .default), to: display.uuid))
        session.apply(.setTool(.select))
        _ = session.beginGesture(tool: .select, at: hitPoint, on: display.uuid)
        _ = session.commitGesture()
        return session
    }

    private func sendAction(_ control: NSControl) {
        XCTAssertNotNil(control.action)
        XCTAssertTrue(NSApp.sendAction(control.action!, to: control.target, from: control))
    }

    private func selectedMarkFixture(
        geometry: MarkGeometry,
        style: MarkStyle,
        hitPoint: NormalizedPoint,
        futureEmoji: String = "👉",
        futureSpotlight: (radius: Double, dimness: Double) = (0.15, 0.5)
    ) -> (
        router: CommandRouter,
        coordinator: DisplayCoordinator,
        display: DisplayDescriptor,
        markID: Mark.ID
    ) {
        let display = PaletteInteractionScreenProvider.descriptor()
        var session = PointerSession()
        session.ensureCanvas(for: display.uuid)
        session.apply(.setEmoji(futureEmoji))
        session.apply(.setSpotlight(
            radius: futureSpotlight.radius,
            dimness: futureSpotlight.dimness
        ))
        let mark = Mark(geometry: geometry, style: style)
        session.apply(.append(mark, to: display.uuid))
        session.apply(.setMode(.annotation))
        session.apply(.setTool(.select))
        _ = session.beginGesture(tool: .select, at: hitPoint, on: display.uuid)
        _ = session.commitGesture()
        let provider = PaletteInteractionScreenProvider(displays: [display])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            session: session,
            overlayFactory: { PaletteInteractionOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        _ = coordinator.synchronize()
        return (router, coordinator, display, mark.id)
    }

    private func geometryHitPoint(for geometry: MarkGeometry) -> NormalizedPoint {
        switch geometry {
        case .rectangle:
            return NormalizedPoint(x: 0.2, y: 0.4)
        case .freehand:
            return NormalizedPoint(x: 0.3, y: 0.3)
        default:
            return NormalizedPoint(x: 0.5, y: 0.5)
        }
    }

    private func toolIdentifier(_ tool: PointerTool) -> String {
        switch tool {
        case .select: return "select"
        case .arrow: return "arrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "ellipse"
        case .pen: return "pen"
        case .eraser: return "eraser"
        case .emoji: return "emoji"
        case .spotlight: return "spotlight"
        }
    }

    private func toolIdentifier(forTitle title: String) -> String? {
        PointerTool.allCases.first { $0.displayName == title }.map(toolIdentifier)
    }
}

@MainActor
private final class PaletteInteractionScreenProvider: ScreenProviding {
    let displays: [DisplayDescriptor]
    let pointerUUID: DisplayUUID?

    init(displays: [DisplayDescriptor], pointerUUID: DisplayUUID? = nil) {
        self.displays = displays
        self.pointerUUID = pointerUUID
    }

    func currentDisplays() -> [DisplayDescriptor] { displays }
    func pointerDisplay() -> DisplayUUID? { pointerUUID ?? displays.first?.uuid }

    static func descriptor() -> DisplayDescriptor {
        DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "display-a"),
            frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
            scaleFactor: 2
        )
    }
}

@MainActor
private final class PaletteShortcutRegistrar: HotKeyRegistering {
    var onEvent: ((HotKeyToken) -> Void)?
    var shouldFail = false
    private var nextToken: UInt64 = 1

    func register(_ preset: ShortcutPreset) throws -> HotKeyToken {
        if shouldFail {
            throw PaletteShortcutError.registrationFailed
        }
        defer { nextToken += 1 }
        return HotKeyToken(rawValue: nextToken)
    }

    func unregister(_ token: HotKeyToken) {}
}

private enum PaletteShortcutError: Error {
    case registrationFailed
}

@MainActor
private final class PaletteShortcutStore: ShortcutStoring {
    func load() -> ShortcutPreset? { nil }
    func save(_ preset: ShortcutPreset) {}
}

@MainActor
private final class PaletteShortcutScheduler: ShortcutScheduling {
    var activeTimerCount: Int { 0 }

    @discardableResult
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> ShortcutScheduleToken {
        fatalError("A failing shortcut registration does not schedule a timer")
    }

    func cancel(_ token: ShortcutScheduleToken) {}
}

@MainActor
private final class PaletteInteractionOverlay: OverlayPresenting {
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

@MainActor
private final class NilGuidePlacementProvider: GuidePlacementProviding {
    func context(
        for display: DisplayDescriptor,
        paletteFrame: DisplayFrame
    ) -> GuidePlacementContext? {
        nil
    }
}

@MainActor
private final class ObservingGuidePlacementProvider: GuidePlacementProviding {
    struct Observation {
        let isVisible: Bool
        let refreshCount: Int
    }

    weak var palette: PalettePanel?
    var observations: [Observation] = []
    var shouldReturnContext = true
    private let provider = GuidePlacementProvider()

    func context(
        for display: DisplayDescriptor,
        paletteFrame: DisplayFrame
    ) -> GuidePlacementContext? {
        observations.append(Observation(
            isVisible: palette?.isVisible ?? false,
            refreshCount: palette?.paletteViewController.displayOptionsRefreshCount ?? 0
        ))
        guard shouldReturnContext else { return nil }
        return provider.context(for: display, paletteFrame: paletteFrame)
    }
}
