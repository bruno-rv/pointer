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
