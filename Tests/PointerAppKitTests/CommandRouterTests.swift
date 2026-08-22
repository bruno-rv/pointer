import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class CommandRouterTests: XCTestCase {
    func testEscapeCancelsDraftThenEntersStandbyFromPaletteFocus() throws {
        let fixture = makeFixture()
        fixture.coordinator.synchronize()
        let overlay = try XCTUnwrap(fixture.coordinator.overlays[fixture.uuid] as? RouterTestOverlay)
        overlay.beginDraft()

        fixture.router.route(.setMode(.annotation))
        fixture.router.route(.escape)

        XCTAssertEqual(fixture.coordinator.session.mode, .standby)
        XCTAssertTrue(overlay.didCancelGesture)
        XCTAssertTrue(fixture.coordinator.session.canvas(for: fixture.uuid).marks.isEmpty)
    }

    func testDeleteRoutesToSelectedMarkOnPointerDisplay() throws {
        let fixture = makeFixture()
        fixture.coordinator.synchronize()
        let mark = Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.1),
                end: NormalizedPoint(x: 0.9, y: 0.9)
            ),
            style: .default
        )
        fixture.coordinator.apply(.append(mark, to: fixture.uuid))
        fixture.coordinator.apply(.setTool(.select))
        let overlay = try XCTUnwrap(fixture.coordinator.overlays[fixture.uuid] as? RouterTestOverlay)
        overlay.select(mark.id)

        fixture.router.route(.delete)

        XCTAssertTrue(fixture.coordinator.session.canvas(for: fixture.uuid).marks.isEmpty)
    }

    func testClearAllRequiresConfirmationAndEnablesUndoClearAll() {
        let fixture = makeFixture()
        fixture.coordinator.synchronize()
        let mark = Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.1),
                end: NormalizedPoint(x: 0.9, y: 0.9)
            ),
            style: .default
        )
        fixture.coordinator.apply(.append(mark, to: fixture.uuid))

        fixture.router.route(.clearAll)
        XCTAssertFalse(fixture.coordinator.session.canvas(for: fixture.uuid).marks.isEmpty)
        XCTAssertFalse(fixture.router.canUndoClearAll)

        fixture.router.confirmClearAll()
        XCTAssertTrue(fixture.coordinator.session.canvas(for: fixture.uuid).marks.isEmpty)
        XCTAssertTrue(fixture.router.canUndoClearAll)

        fixture.router.route(.undoClearAll)
        XCTAssertEqual(fixture.coordinator.session.canvas(for: fixture.uuid).marks, [mark])
    }

    private func makeFixture() -> RouterFixture {
        RouterFixture()
    }
}

@MainActor
private final class RouterFixture {
    let uuid = DisplayUUID(rawValue: "display-a")
    let provider: RouterTestScreenProvider
    let coordinator: DisplayCoordinator
    let router: CommandRouter

    init() {
        let descriptor = DisplayDescriptor(
            uuid: uuid,
            frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
            scaleFactor: 2
        )
        provider = RouterTestScreenProvider(displays: [descriptor])
        coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { RouterTestOverlay(display: $0) }
        )
        router = CommandRouter(coordinator: coordinator, screenProvider: provider)
    }
}

@MainActor
private final class RouterTestScreenProvider: ScreenProviding {
    let displays: [DisplayDescriptor]

    init(displays: [DisplayDescriptor]) {
        self.displays = displays
    }

    func currentDisplays() -> [DisplayDescriptor] { displays }
    func pointerDisplay() -> DisplayUUID? { displays.first?.uuid }
}

@MainActor
private final class RouterTestOverlay: OverlayPresenting {
    var display: DisplayDescriptor
    var didCancelGesture = false
    private var session = PointerSession()
    private var onSessionUpdate: ((PointerSession) -> Void)?

    init(display: DisplayDescriptor) {
        self.display = display
    }

    func update(display: DisplayDescriptor) { self.display = display }
    func update(session: PointerSession) { self.session = session }
    func setMode(_ mode: PointerMode) {}
    func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {
        self.onSessionUpdate = onSessionUpdate
    }
    func cancelActiveGesture() { didCancelGesture = true }
    func close() {}

    func beginDraft() {
        _ = session.beginGesture(
            tool: .arrow,
            at: NormalizedPoint(x: 0.2, y: 0.2),
            on: display.uuid
        )
    }

    func select(_ id: Mark.ID) {
        var updated = session
        updated.apply(.setMode(.annotation))
        let mark = updated.canvas(for: display.uuid).marks.first { $0.id == id }
        guard let mark else { return }
        _ = updated.beginGesture(
            tool: .select,
            at: NormalizedPoint(x: 0.5, y: 0.5),
            on: display.uuid
        )
        if updated.canvas(for: display.uuid).marks.contains(where: { $0.id == mark.id }) {
            session = updated
            onSessionUpdate?(session)
        }
    }
}
