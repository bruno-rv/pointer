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

    func testStandbyOverlayKeepsMarksVisibleButRemovesHandlesAndMouseEvents() throws {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        let mark = fixtureRectangle()
        session.apply(.append(mark, to: panel.display.uuid))
        session.apply(.setTool(.select))

        panel.update(session: session)
        panel.setMode(.standby)

        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.canvasView.cursorPlan, .clickThrough)
        XCTAssertEqual(panel.canvasView.session.canvas(for: panel.display.uuid).marks, [mark])
    }

    func testOverlayStopAndClearReturnsObservableCleanupCounts() {
        _ = NSApplication.shared
        let overlay = RecordingOverlay(display: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        let first = overlay.stopAndClear()
        let second = overlay.stopAndClear()

        XCTAssertEqual(first.clearedHandlerCount, 3)
        XCTAssertEqual(first.remainingHandlerCount, 0)
        XCTAssertTrue(first.didClose)
        XCTAssertEqual(second.clearedHandlerCount, 0)
        XCTAssertFalse(second.didClose)
        XCTAssertEqual(overlay.closeCount, 1)
    }

    func testDefaultOverlayStopAndClearIsObservableNoOp() {
        let fake = ExistingOverlayConformingFake(display: descriptor(uuid: DisplayUUID(rawValue: "display-a")))

        let result = fake.stopAndClear()

        XCTAssertEqual(result, OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: false
        ))
    }

    func testFreshOverlayStopAndClearReportsZeroInstalledHandlers() {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))

        let first = panel.stopAndClear()
        let second = panel.stopAndClear()

        XCTAssertEqual(first, OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: true
        ))
        XCTAssertEqual(second, OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: false
        ))
    }

    func testPartialOverlayStopAndClearReportsInstalledHandlerCount() {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        panel.canvasView.onBoundaryEvent = { _ in }

        let result = panel.stopAndClear()

        XCTAssertEqual(result.clearedHandlerCount, 1)
        XCTAssertEqual(result.remainingHandlerCount, 0)
        XCTAssertTrue(result.didClose)
        XCTAssertNil(panel.canvasView.onSessionUpdate)
        XCTAssertNil(panel.canvasView.onBoundaryEvent)
        XCTAssertNil(panel.canvasView.onRedrawRequested)
    }

    func testRealOverlayStopAndClearCancelsGestureAndClearsHandlers() {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        panel.update(session: session)

        var sessionUpdates = 0
        var boundaryEvents = 0
        var redrawRequests = 0
        panel.setEventHandlers(
            onSessionUpdate: { _ in sessionUpdates += 1 },
            onBoundaryEvent: { _ in boundaryEvents += 1 }
        )
        panel.canvasView.onRedrawRequested = { redrawRequests += 1 }
        panel.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))
        sessionUpdates = 0
        boundaryEvents = 0
        redrawRequests = 0

        let result = panel.stopAndClear()

        XCTAssertTrue(result.cancelledActiveGesture)
        XCTAssertEqual(result.clearedHandlerCount, 3)
        XCTAssertEqual(result.remainingHandlerCount, 0)
        XCTAssertTrue(result.didClose)
        XCTAssertFalse(panel.canvasView.hasActiveGesture)
        XCTAssertNil(panel.canvasView.onSessionUpdate)
        XCTAssertNil(panel.canvasView.onBoundaryEvent)
        XCTAssertNil(panel.canvasView.onRedrawRequested)
        XCTAssertEqual(sessionUpdates, 1)
        XCTAssertEqual(boundaryEvents, 1)
        XCTAssertEqual(redrawRequests, 1)
    }

    func testDirectCloseCancelsActiveGestureAndClearsHandlersExactlyOnce() {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        panel.update(session: session)

        var sessionUpdates = 0
        var boundaryEvents = 0
        var redrawRequests = 0
        panel.setEventHandlers(
            onSessionUpdate: { _ in sessionUpdates += 1 },
            onBoundaryEvent: { _ in boundaryEvents += 1 }
        )
        panel.canvasView.onRedrawRequested = { redrawRequests += 1 }
        panel.show()
        XCTAssertTrue(panel.isVisible)
        panel.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))
        sessionUpdates = 0
        boundaryEvents = 0
        redrawRequests = 0

        panel.close()
        panel.close()

        XCTAssertFalse(panel.canvasView.hasActiveGesture)
        XCTAssertNil(panel.canvasView.onSessionUpdate)
        XCTAssertNil(panel.canvasView.onBoundaryEvent)
        XCTAssertNil(panel.canvasView.onRedrawRequested)
        XCTAssertEqual(sessionUpdates, 1)
        XCTAssertEqual(boundaryEvents, 1)
        XCTAssertEqual(redrawRequests, 1)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.stopAndClear(), OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: false
        ))
    }

    func testClosedOverlayCannotShowOrRebindHandlers() {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        panel.show()
        XCTAssertTrue(panel.isVisible)

        let first = panel.stopAndClear()
        panel.show()
        panel.setEventHandlers(onSessionUpdate: { _ in }, onBoundaryEvent: { _ in })

        XCTAssertTrue(first.didClose)
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(panel.canvasView.onSessionUpdate)
        XCTAssertNil(panel.canvasView.onBoundaryEvent)
        XCTAssertEqual(panel.stopAndClear(), OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: false
        ))
    }

    func testStopAndClearIsReentrancySafeDuringCancellationCallbacks() {
        _ = NSApplication.shared
        let panel = OverlayPanel(descriptor: descriptor(uuid: DisplayUUID(rawValue: "display-a")))
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        panel.update(session: session)

        var innerResult: OverlayCleanupResult?
        var reentrantHandlerWasBound = false
        var visibleAfterReentrantCalls = false
        panel.setEventHandlers(
            onSessionUpdate: { _ in },
            onBoundaryEvent: { [weak panel] event in
                guard event == .cancelled, let panel else { return }
                panel.canvasView.onSessionUpdate = nil
                panel.setEventHandlers(
                    onSessionUpdate: { _ in },
                    onBoundaryEvent: { _ in }
                )
                reentrantHandlerWasBound = panel.canvasView.onSessionUpdate != nil
                innerResult = panel.stopAndClear()
                panel.close()
                panel.show()
                visibleAfterReentrantCalls = panel.isVisible
            }
        )
        panel.canvasView.onRedrawRequested = {}
        panel.show()
        panel.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))

        let outerResult = panel.stopAndClear()

        XCTAssertEqual(innerResult, OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: false
        ))
        XCTAssertFalse(reentrantHandlerWasBound)
        XCTAssertTrue(visibleAfterReentrantCalls)
        XCTAssertTrue(outerResult.cancelledActiveGesture)
        XCTAssertEqual(outerResult.clearedHandlerCount, 3)
        XCTAssertEqual(outerResult.remainingHandlerCount, 0)
        XCTAssertTrue(outerResult.didClose)
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(panel.canvasView.onSessionUpdate)
        XCTAssertNil(panel.canvasView.onBoundaryEvent)
        XCTAssertNil(panel.canvasView.onRedrawRequested)
        panel.show()
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.stopAndClear(), OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: 0,
            remainingHandlerCount: 0,
            didClose: false
        ))
    }

    private func descriptor(uuid: DisplayUUID, x: Double = 0, width: Double = 1_920) -> DisplayDescriptor {
        DisplayDescriptor(
            uuid: uuid,
            frame: DisplayFrame(x: x, y: 0, width: width, height: 1_080),
            visibleFrame: DisplayFrame(x: x, y: 24, width: width, height: 1_056),
            scaleFactor: 2
        )
    }

    private func fixtureRectangle() -> Mark {
        Mark(
            geometry: .rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.3)),
            style: .default
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

@MainActor
private final class RecordingOverlay: OverlayPresenting {
    private let panel: OverlayPanel
    var closeCount = 0

    var display: DisplayDescriptor { panel.display }

    init(display: DisplayDescriptor) {
        panel = OverlayPanel(descriptor: display)
        panel.setEventHandlers(onSessionUpdate: { _ in }, onBoundaryEvent: { _ in })
        panel.canvasView.onRedrawRequested = {}
    }

    func update(display: DisplayDescriptor) {
        panel.update(display: display)
    }

    func update(session: PointerSession) {
        panel.update(session: session)
    }

    func setMode(_ mode: PointerMode) {
        panel.setMode(mode)
    }

    func cancelActiveGesture() {
        panel.cancelActiveGesture()
    }

    func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {
        panel.setEventHandlers(onSessionUpdate: onSessionUpdate, onBoundaryEvent: onBoundaryEvent)
    }

    func show() {
        panel.show()
    }

    func close() {
        panel.close()
    }

    func stopAndClear() -> OverlayCleanupResult {
        let result = panel.stopAndClear()
        if result.didClose {
            closeCount += 1
        }
        return result
    }
}

@MainActor
private final class ExistingOverlayConformingFake: OverlayPresenting {
    var display: DisplayDescriptor

    init(display: DisplayDescriptor) {
        self.display = display
    }

    func update(display: DisplayDescriptor) {
        self.display = display
    }

    func update(session: PointerSession) {}
    func setMode(_ mode: PointerMode) {}
    func close() {}
}
