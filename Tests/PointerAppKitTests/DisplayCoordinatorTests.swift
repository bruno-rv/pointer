import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class DisplayCoordinatorTests: XCTestCase {
    func testReconnectWithSameUUIDReusesCanvasAcrossChangedFrame() {
        let uuid = DisplayUUID(rawValue: "display-a")
        let first = descriptor(uuid: uuid, x: 0, width: 1_920)
        let second = descriptor(uuid: uuid, x: 40, width: 1_600)
        let provider = FakeScreenProvider(displays: [first])
        var created: [FakeOverlay] = []
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { descriptor in
                let overlay = FakeOverlay(display: descriptor)
                created.append(overlay)
                return overlay
            }
        )

        coordinator.synchronize()
        guard let original = coordinator.overlays[uuid] as? FakeOverlay else {
            return XCTFail("Expected an overlay for the connected display")
        }
        provider.displays = [second]

        coordinator.synchronize()

        XCTAssertTrue(coordinator.overlays[uuid] === original)
        XCTAssertEqual(original.display.frame, second.frame)
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(coordinator.session.canvas(for: uuid), Canvas())
    }

    func testNewlyConnectedOverlayIsPresentedExactlyOnce() {
        let uuid = DisplayUUID(rawValue: "display-a")
        let provider = FakeScreenProvider(displays: [descriptor(uuid: uuid)])
        var created: [FakeOverlay] = []
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { descriptor in
                let overlay = FakeOverlay(display: descriptor)
                created.append(overlay)
                return overlay
            }
        )

        coordinator.synchronize()
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created[0].presentationCount, 1)

        coordinator.synchronize()
        XCTAssertEqual(created[0].presentationCount, 1)
    }

    func testRemovingScreenClosesOnlyItsOverlayAndRetainsItsCanvas() {
        let retainedUUID = DisplayUUID(rawValue: "display-a")
        let removedUUID = DisplayUUID(rawValue: "display-b")
        let retained = descriptor(uuid: retainedUUID, x: 0, width: 1_920)
        let removed = descriptor(uuid: removedUUID, x: 1_920, width: 1_920)
        let provider = FakeScreenProvider(displays: [retained, removed])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { FakeOverlay(display: $0) }
        )
        coordinator.synchronize()
        let mark = Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.2, y: 0.2),
                end: NormalizedPoint(x: 0.8, y: 0.8)
            ),
            style: .default
        )
        coordinator.apply(.append(mark, to: removedUUID))
        let removedOverlay = try! XCTUnwrap(coordinator.overlays[removedUUID] as? FakeOverlay)
        let retainedOverlay = try! XCTUnwrap(coordinator.overlays[retainedUUID] as? FakeOverlay)
        provider.displays = [retained]

        coordinator.synchronize()

        XCTAssertNil(coordinator.overlays[removedUUID])
        XCTAssertTrue(removedOverlay.didClose)
        XCTAssertFalse(retainedOverlay.didClose)
        XCTAssertEqual(coordinator.session.canvas(for: removedUUID).marks, [mark])
    }

    func testStandbyOverlayIgnoresMouseEvents() throws {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))

        XCTAssertTrue(panel.ignoresMouseEvents)

        panel.setMode(.annotation)
        XCTAssertFalse(panel.ignoresMouseEvents)

        panel.setMode(.standby)
        XCTAssertTrue(panel.ignoresMouseEvents)
    }

    private func descriptor(uuid: DisplayUUID, x: Double = 0, width: Double = 1_920) -> DisplayDescriptor {
        DisplayDescriptor(
            uuid: uuid,
            frame: DisplayFrame(x: x, y: 0, width: width, height: 1_080),
            visibleFrame: DisplayFrame(x: x, y: 24, width: width, height: 1_056),
            scaleFactor: 2
        )
    }
}

@MainActor
private final class FakeScreenProvider: ScreenProviding {
    var displays: [DisplayDescriptor]

    init(displays: [DisplayDescriptor]) {
        self.displays = displays
    }

    func currentDisplays() -> [DisplayDescriptor] { displays }
    func pointerDisplay() -> DisplayUUID? { displays.first?.uuid }
}

@MainActor
private final class FakeOverlay: OverlayPresenting {
    var display: DisplayDescriptor
    var didClose = false
    var presentationCount = 0

    init(display: DisplayDescriptor) {
        self.display = display
    }

    func update(display: DisplayDescriptor) {
        self.display = display
    }

    func update(session: PointerSession) {}
    func setMode(_ mode: PointerMode) {}
    func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {}
    func show() { presentationCount += 1 }
    func close() { didClose = true }
}
