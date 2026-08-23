import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class DisplayLifecycleRegressionTests: XCTestCase {
    func testZeroDisplayTransitionCancelsGesturesClosesOverlayAndRetainsSessionCanvas() throws {
        _ = NSApplication.shared
        let uuid = DisplayUUID(rawValue: "display-a")
        let provider = LifecycleScreenProvider(displays: [descriptor(uuid: uuid)])
        var created: [OverlayPanel] = []
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { descriptor in
                let panel = OverlayPanel(descriptor: descriptor)
                created.append(panel)
                return panel
            }
        )
        _ = coordinator.synchronize()

        let style = MarkStyle(
            color: RGBAColor(red: 0.2, green: 0.3, blue: 0.4),
            strokeWidth: 9,
            opacity: 0.6
        )
        let mark = Mark(
            geometry: .rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.3)),
            style: style
        )
        coordinator.apply(.setTool(.select))
        coordinator.apply(.setStyle(style))
        coordinator.apply(.setEmoji("🧭"))
        coordinator.apply(.setMode(.annotation))
        coordinator.apply(.append(mark, to: uuid))

        let originalPanel = try XCTUnwrap(created.first)
        originalPanel.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))
        XCTAssertTrue(originalPanel.canvasView.hasActiveGesture)

        var boundaries: [GestureBoundaryEvent] = []
        coordinator.onBoundaryEvent = { _, event in boundaries.append(event) }
        provider.displays = []

        let zero = coordinator.synchronize()

        XCTAssertTrue(zero.enteredZeroDisplayState)
        XCTAssertTrue(coordinator.overlays.isEmpty)
        XCTAssertFalse(originalPanel.isVisible)
        XCTAssertTrue(originalPanel.ignoresMouseEvents)
        XCTAssertFalse(originalPanel.canvasView.hasActiveGesture)
        XCTAssertEqual(boundaries, [.cancelled])
        XCTAssertEqual(coordinator.session.mode, .standby)
        XCTAssertEqual(coordinator.session.toolState.tool, .select)
        XCTAssertEqual(coordinator.session.toolState.style, style)
        XCTAssertEqual(coordinator.session.toolState.emoji, "🧭")
        XCTAssertEqual(coordinator.session.canvas(for: uuid).marks, [mark])
        XCTAssertTrue(coordinator.session.canUndo(on: uuid))

        provider.displays = [descriptor(uuid: uuid, x: 40, width: 2_560, height: 1_440)]
        _ = coordinator.synchronize()

        let reconnectedPanel = try XCTUnwrap(created.last)
        XCTAssertEqual(created.count, 2)
        XCTAssertTrue(reconnectedPanel !== originalPanel)
        XCTAssertTrue(reconnectedPanel.ignoresMouseEvents)
        XCTAssertEqual(reconnectedPanel.canvasView.session.mode, .standby)
        XCTAssertEqual(reconnectedPanel.canvasView.session.canvas(for: uuid).marks, [mark])
    }

    func testDisplayLossProducesExactlyOneCancellationBoundaryPerActiveOverlay() throws {
        _ = NSApplication.shared
        let uuid = DisplayUUID(rawValue: "display-a")
        let provider = LifecycleScreenProvider(displays: [descriptor(uuid: uuid)])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { OverlayPanel(descriptor: $0) }
        )
        _ = coordinator.synchronize()
        coordinator.apply(.setMode(.annotation))
        let panel = try XCTUnwrap(coordinator.overlays[uuid] as? OverlayPanel)

        var boundaries: [GestureBoundaryEvent] = []
        coordinator.onBoundaryEvent = { _, event in boundaries.append(event) }
        panel.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))
        boundaries.removeAll()
        provider.displays = []

        _ = coordinator.synchronize()

        XCTAssertEqual(boundaries, [.cancelled])
        XCTAssertFalse(panel.canvasView.hasActiveGesture)
        guard let staleMouseUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ) else {
            return XCTFail("Expected stale mouse-up fixture")
        }
        panel.canvasView.mouseUp(with: staleMouseUp)

        XCTAssertEqual(boundaries, [.cancelled])
        XCTAssertTrue(panel.canvasView.session.canvas(for: uuid).marks.isEmpty)
    }

    func testPointerDisplayChangeDoesNotMigrateMarks() throws {
        let firstUUID = DisplayUUID(rawValue: "display-a")
        let secondUUID = DisplayUUID(rawValue: "display-b")
        let provider = LifecycleScreenProvider(
            displays: [descriptor(uuid: firstUUID), descriptor(uuid: secondUUID, x: 1_920)],
            pointerUUID: firstUUID
        )
        var created: [LifecycleOverlay] = []
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { descriptor in
                let overlay = LifecycleOverlay(display: descriptor)
                created.append(overlay)
                return overlay
            }
        )
        _ = coordinator.synchronize()

        let mark = Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.2),
                end: NormalizedPoint(x: 0.8, y: 0.7)
            ),
            style: .default
        )
        coordinator.apply(.append(mark, to: firstUUID))
        provider.pointerUUID = secondUUID

        let result = coordinator.synchronize()

        XCTAssertEqual(result.pointerDisplay, secondUUID)
        XCTAssertEqual(coordinator.session.canvas(for: firstUUID).marks, [mark])
        XCTAssertTrue(coordinator.session.canvas(for: secondUUID).marks.isEmpty)
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(created.map(\.showCount), [1, 1])
    }

    func testRepeatedSynchronizeDoesNotDuplicateOverlayOrCallback() {
        let uuid = DisplayUUID(rawValue: "display-a")
        let provider = LifecycleScreenProvider(displays: [descriptor(uuid: uuid)])
        var created: [LifecycleOverlay] = []
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { descriptor in
                let overlay = LifecycleOverlay(display: descriptor)
                created.append(overlay)
                return overlay
            }
        )
        var syncCallbacks = 0
        var sessionCallbacks = 0
        coordinator.onDisplaySync = { _ in syncCallbacks += 1 }
        coordinator.onSessionUpdate = { _ in sessionCallbacks += 1 }

        _ = coordinator.synchronize()
        _ = coordinator.synchronize()
        _ = coordinator.synchronize()

        let overlay = created[0]
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(coordinator.overlays.count, 1)
        XCTAssertEqual(overlay.showCount, 1)
        XCTAssertEqual(syncCallbacks, 3)
        XCTAssertEqual(overlay.handlerBindingCount, 3)

        overlay.emitSessionUpdate(coordinator.session)

        XCTAssertEqual(sessionCallbacks, 1)
        XCTAssertEqual(coordinator.overlays.count, 1)
    }

    func testStopWithZeroDisplaysReturnsAllZeroCounts() {
        let provider = LifecycleScreenProvider(displays: [])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { LifecycleOverlay(display: $0) }
        )

        let first = coordinator.stop()
        let second = coordinator.stop()

        let expected = DisplayStopResult(
            closedOverlayCount: 0,
            remainingOverlayCount: 0,
            activeGestureCount: 0,
            clearedHandlerCount: 0,
            boundHandlerCount: 0
        )
        XCTAssertEqual(first, expected)
        XCTAssertEqual(second, expected)
        XCTAssertTrue(coordinator.overlays.isEmpty)
    }

    private func descriptor(
        uuid: DisplayUUID,
        x: Double = 0,
        width: Double = 1_920,
        height: Double = 1_080
    ) -> DisplayDescriptor {
        DisplayDescriptor(
            uuid: uuid,
            frame: DisplayFrame(x: x, y: 0, width: width, height: height),
            visibleFrame: DisplayFrame(x: x, y: 24, width: width, height: height - 24),
            scaleFactor: 2
        )
    }
}

@MainActor
private final class LifecycleScreenProvider: ScreenProviding {
    var displays: [DisplayDescriptor]
    var pointerUUID: DisplayUUID?

    init(displays: [DisplayDescriptor], pointerUUID: DisplayUUID? = nil) {
        self.displays = displays
        self.pointerUUID = pointerUUID
    }

    func currentDisplays() -> [DisplayDescriptor] { displays }

    func pointerDisplay() -> DisplayUUID? {
        pointerUUID ?? displays.first?.uuid
    }
}

@MainActor
private final class LifecycleOverlay: OverlayPresenting {
    var display: DisplayDescriptor
    var mode: PointerMode = .standby
    var latestSession = PointerSession()
    var showCount = 0
    var closeCount = 0
    var cancelCount = 0
    var handlerBindingCount = 0
    var handlerCount = 0
    private var isClosed = false

    private var onSessionUpdate: ((PointerSession) -> Void)?

    init(display: DisplayDescriptor) {
        self.display = display
    }

    func update(display: DisplayDescriptor) {
        self.display = display
    }

    func update(session: PointerSession) {
        latestSession = session
    }

    func setMode(_ mode: PointerMode) {
        self.mode = mode
    }

    func cancelActiveGesture() {
        cancelCount += 1
    }

    func show() {
        guard !isClosed else { return }
        showCount += 1
    }

    func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {
        guard !isClosed else { return }
        handlerBindingCount += 1
        self.onSessionUpdate = onSessionUpdate
        handlerCount = 2
        _ = onBoundaryEvent
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        closeCount += 1
    }

    func stopAndClear() -> OverlayCleanupResult {
        let cleared = handlerCount
        handlerCount = 0
        onSessionUpdate = nil
        return OverlayCleanupResult(
            cancelledActiveGesture: false,
            clearedHandlerCount: cleared,
            remainingHandlerCount: handlerCount,
            didClose: false
        )
    }

    func emitSessionUpdate(_ session: PointerSession) {
        onSessionUpdate?(session)
    }
}
