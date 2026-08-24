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

        let descriptor = PaletteInteractionScreenProvider.descriptor()
        guard case .shown = palette.show(on: descriptor) else {
            return XCTFail("Expected shown(GuidePlacementContext)")
        }
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
}

@MainActor
private final class PaletteInteractionScreenProvider: ScreenProviding {
    let displays: [DisplayDescriptor]

    init(displays: [DisplayDescriptor]) {
        self.displays = displays
    }

    func currentDisplays() -> [DisplayDescriptor] { displays }
    func pointerDisplay() -> DisplayUUID? { displays.first?.uuid }

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
