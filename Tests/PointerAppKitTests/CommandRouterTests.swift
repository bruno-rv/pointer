import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class CommandRouterTests: XCTestCase {
    func testNoDisplayRejectsAnnotationEntryWithoutMutatingModeOrTool() {
        let provider = RouterTestScreenProvider(displays: [])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { RouterTestOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)

        router.route(.setTool(.spotlight))

        XCTAssertEqual(router.session.mode, .standby)
        XCTAssertEqual(router.session.toolState.tool, .arrow)
        XCTAssertEqual(router.feedbackMessage, "No presentation display connected")
    }

    func testDeleteWithoutSelectionPublishesFeedbackWithoutMutatingSession() {
        let fixture = makeFixture()
        _ = fixture.coordinator.synchronize()
        var feedback: [String] = []
        fixture.router.onFeedback = { feedback.append($0) }
        let before = fixture.router.session

        fixture.router.route(.delete)

        XCTAssertEqual(fixture.router.session, before)
        XCTAssertEqual(fixture.router.feedbackMessage, "Select a mark to delete")
        XCTAssertEqual(feedback, ["Select a mark to delete"])
    }

    func testUndoWithoutPointerOrHistoryPublishesFeedbackWithoutMutatingSession() {
        let fixture = makeFixture()
        _ = fixture.coordinator.synchronize()
        var feedback: [String] = []
        fixture.router.onFeedback = { feedback.append($0) }
        let before = fixture.router.session

        fixture.router.route(.undo)

        XCTAssertEqual(fixture.router.session, before)
        XCTAssertEqual(fixture.router.feedbackMessage, "Nothing to undo")
        XCTAssertEqual(feedback, ["Nothing to undo"])
    }

    func testClearWithoutPointerOrMarksPublishesFeedbackWithoutMutatingSession() {
        let fixture = makeFixture()
        _ = fixture.coordinator.synchronize()
        var feedback: [String] = []
        fixture.router.onFeedback = { feedback.append($0) }
        let before = fixture.router.session

        fixture.router.route(.clear)

        XCTAssertEqual(fixture.router.session, before)
        XCTAssertEqual(fixture.router.feedbackMessage, "Nothing to clear")
        XCTAssertEqual(feedback, ["Nothing to clear"])
    }

    func testInvalidPointerUUIDIsRejectedAgainstAcceptedDisplaySyncSet() {
        let valid = RouterTestScreenProvider.descriptor(uuid: DisplayUUID(rawValue: "valid"))
        let provider = RouterTestScreenProvider(
            displays: [valid],
            pointerUUID: DisplayUUID(rawValue: "missing")
        )
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { RouterTestOverlay(display: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)

        router.updateDisplayState(coordinator.synchronize())
        router.route(.setMode(.annotation))

        XCTAssertEqual(router.session.mode, .standby)
        XCTAssertEqual(router.feedbackMessage, "No presentation display connected")
    }

    func testPointerDisplayUsesLastAcceptedSyncStateInsteadOfRawProviderPointer() {
        let fixture = makeFixture()
        _ = fixture.coordinator.synchronize()
        fixture.provider.pointerUUID = DisplayUUID(rawValue: "stale")

        XCTAssertEqual(fixture.router.pointerDisplay, fixture.uuid)
    }

    func testDisconnectedAcceptedDisplayDisablesUndoAndClearWithoutMutatingRetainedCanvas() {
        let fixture = makeFixture()
        _ = fixture.coordinator.synchronize()
        let mark = Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.1),
                end: NormalizedPoint(x: 0.8, y: 0.8)
            ),
            style: .default
        )
        fixture.coordinator.apply(.append(mark, to: fixture.uuid))
        let before = fixture.router.session
        var feedback: [String] = []
        fixture.router.onFeedback = { feedback.append($0) }

        fixture.router.updateDisplayState(DisplaySyncResult(
            connectedUUIDs: [],
            addedUUIDs: [],
            removedUUIDs: [fixture.uuid],
            pointerDisplay: nil,
            hasConnectedDisplays: false,
            enteredZeroDisplayState: true,
            reconnected: false
        ))

        XCTAssertNil(fixture.router.pointerDisplay)
        fixture.router.route(.undo)
        XCTAssertEqual(fixture.router.session, before)
        XCTAssertEqual(fixture.router.feedbackMessage, "Nothing to undo")
        fixture.router.route(.clear)
        XCTAssertEqual(fixture.router.session, before)
        XCTAssertEqual(fixture.router.feedbackMessage, "Nothing to clear")
        XCTAssertEqual(feedback, ["Nothing to undo", "Nothing to clear"])
    }

    func testEscapeCancelsRealOverlayOnceAndStaleMouseUpDoesNotDuplicateBoundary() throws {
        _ = NSApplication.shared
        let uuid = DisplayUUID(rawValue: "display-a")
        let descriptor = RouterTestScreenProvider.descriptor(uuid: uuid)
        let provider = RouterTestScreenProvider(displays: [descriptor])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { OverlayPanel(descriptor: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        var boundaries: [GestureBoundaryEvent] = []
        coordinator.onBoundaryEvent = { _, event in boundaries.append(event) }

        _ = coordinator.synchronize()
        router.route(.setMode(.annotation))
        let overlay = try XCTUnwrap(coordinator.overlays[uuid] as? OverlayPanel)
        overlay.canvasView.beginGesture(at: NSPoint(x: 100, y: 100))
        router.route(.escape)
        overlay.canvasView.mouseUp(with: NSEvent())

        XCTAssertEqual(boundaries, [.began, .cancelled])
        XCTAssertEqual(router.session.mode, .standby)
        XCTAssertTrue(router.session.canvas(for: uuid).marks.isEmpty)
    }

    func testEmptyCanvasClickPublishesSelectionClearedForRealOverlay() throws {
        _ = NSApplication.shared
        let uuid = DisplayUUID(rawValue: "display-a")
        let descriptor = RouterTestScreenProvider.descriptor(uuid: uuid)
        let provider = RouterTestScreenProvider(displays: [descriptor])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { OverlayPanel(descriptor: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        var feedback: [String] = []
        router.onFeedback = { feedback.append($0) }

        _ = coordinator.synchronize()
        router.route(.setMode(.annotation))
        let mark = Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.1),
                end: NormalizedPoint(x: 0.8, y: 0.8)
            ),
            style: .default
        )
        coordinator.apply(.append(mark, to: uuid))
        router.route(.setTool(.select))
        let overlay = try XCTUnwrap(coordinator.overlays[uuid] as? OverlayPanel)

        overlay.canvasView.beginGesture(at: NSPoint(x: 960, y: 540))
        overlay.canvasView.endGesture()
        XCTAssertEqual(router.session.selection, mark.id)
        feedback.removeAll()

        overlay.canvasView.beginGesture(at: NSPoint(x: 10, y: 10))
        XCTAssertTrue(feedback.isEmpty)
        XCTAssertNil(router.feedbackMessage)
        overlay.canvasView.endGesture()

        XCTAssertNil(router.session.selection)
        XCTAssertEqual(feedback, ["Selection cleared"])
        XCTAssertEqual(router.feedbackMessage, "Selection cleared")
    }

    func testEmptyCanvasClickCancelledRestoresSelectionWithoutFeedback() throws {
        _ = NSApplication.shared
        let uuid = DisplayUUID(rawValue: "display-a")
        let descriptor = RouterTestScreenProvider.descriptor(uuid: uuid)
        let provider = RouterTestScreenProvider(displays: [descriptor])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { OverlayPanel(descriptor: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        var feedback: [String] = []
        router.onFeedback = { feedback.append($0) }

        _ = coordinator.synchronize()
        router.route(.setMode(.annotation))
        let mark = Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.1),
                end: NormalizedPoint(x: 0.8, y: 0.8)
            ),
            style: .default
        )
        coordinator.apply(.append(mark, to: uuid))
        router.route(.setTool(.select))
        let overlay = try XCTUnwrap(coordinator.overlays[uuid] as? OverlayPanel)
        overlay.canvasView.beginGesture(at: NSPoint(x: 960, y: 540))
        overlay.canvasView.endGesture()
        XCTAssertEqual(router.session.selection, mark.id)
        feedback.removeAll()

        overlay.canvasView.beginGesture(at: NSPoint(x: 10, y: 10))
        XCTAssertTrue(feedback.isEmpty)
        XCTAssertNil(router.feedbackMessage)
        overlay.canvasView.cancelGesture()

        XCTAssertEqual(router.session.selection, mark.id)
        XCTAssertTrue(feedback.isEmpty)
        XCTAssertNil(router.feedbackMessage)

        overlay.canvasView.beginGesture(at: NSPoint(x: 10, y: 10))
        XCTAssertTrue(feedback.isEmpty)
        router.updateDisplayState(DisplaySyncResult(
            connectedUUIDs: [],
            addedUUIDs: [],
            removedUUIDs: [uuid],
            pointerDisplay: nil,
            hasConnectedDisplays: false,
            enteredZeroDisplayState: true,
            reconnected: false
        ))
        overlay.canvasView.endGesture()
        XCTAssertTrue(feedback.isEmpty)
        XCTAssertNil(router.feedbackMessage)
    }

    func testSelectionClearedFeedbackIsNotPublishedForStandbyDeleteOrClear() throws {
        _ = NSApplication.shared
        let uuid = DisplayUUID(rawValue: "display-a")
        let descriptor = RouterTestScreenProvider.descriptor(uuid: uuid)
        let provider = RouterTestScreenProvider(displays: [descriptor])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { OverlayPanel(descriptor: $0) }
        )
        let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
        var feedback: [String] = []
        router.onFeedback = { feedback.append($0) }
        _ = coordinator.synchronize()
        router.route(.setMode(.annotation))
        let overlay = try XCTUnwrap(coordinator.overlays[uuid] as? OverlayPanel)

        func appendAndSelect(_ mark: Mark) {
            coordinator.apply(.append(mark, to: uuid))
            router.route(.setTool(.select))
            overlay.canvasView.beginGesture(at: NSPoint(x: 960, y: 540))
            overlay.canvasView.endGesture()
            XCTAssertEqual(router.session.selection, mark.id)
        }

        appendAndSelect(Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.1),
                end: NormalizedPoint(x: 0.8, y: 0.8)
            ),
            style: .default
        ))
        feedback.removeAll()
        router.route(.delete)
        XCTAssertFalse(feedback.contains("Selection cleared"))

        appendAndSelect(Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.1),
                end: NormalizedPoint(x: 0.8, y: 0.8)
            ),
            style: .default
        ))
        feedback.removeAll()
        router.route(.clear)
        XCTAssertFalse(feedback.contains("Selection cleared"))

        appendAndSelect(Mark(
            geometry: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.1),
                end: NormalizedPoint(x: 0.8, y: 0.8)
            ),
            style: .default
        ))
        feedback.removeAll()
        router.route(.setMode(.standby))
        XCTAssertFalse(feedback.contains("Selection cleared"))
    }

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

    func testCommandsCancelActiveGestureBeforeStaleMouseUpCanRepublishIt() throws {
        let commands: [CommandRouter.Command] = [
            .setTool(.ellipse),
            .setStyle(MarkStyle(color: MarkStyle.default.color, strokeWidth: 8, opacity: 0.5)),
            .setMode(.standby),
        ]

        for command in commands {
            let fixture = makeFixture()
            fixture.coordinator.synchronize()
            let overlay = try XCTUnwrap(fixture.coordinator.overlays[fixture.uuid] as? RouterTestOverlay)
            overlay.beginDraft()

            fixture.router.route(command)
            overlay.finishDraft()

            XCTAssertTrue(overlay.didCancelGesture, "Expected cancellation for \(command)")
            XCTAssertFalse(
                fixture.coordinator.session.canvas(for: fixture.uuid).marks.contains {
                    if case .arrow = $0.geometry { return true }
                    return false
                },
                "Stale draft survived \(command)"
            )
        }

        let clearAllFixture = makeFixture()
        clearAllFixture.coordinator.synchronize()
        let clearAllOverlay = try XCTUnwrap(
            clearAllFixture.coordinator.overlays[clearAllFixture.uuid] as? RouterTestOverlay
        )
        clearAllOverlay.beginDraft()
        clearAllFixture.router.confirmClearAll()
        clearAllOverlay.finishDraft()
        XCTAssertTrue(clearAllOverlay.didCancelGesture)
        XCTAssertTrue(clearAllFixture.coordinator.session.canvas(for: clearAllFixture.uuid).marks.isEmpty)
    }

    func testCallbackBindingReplacesCallbacksAndKeepsAcceptedDisplayState() {
        let fixture = makeFixture()
        _ = fixture.coordinator.synchronize()
        var stateChangeCount = 0
        var entryCount = 0

        XCTAssertEqual(
            fixture.router.bindCallbacks(
                onStateChange: { _ in stateChangeCount += 1 },
                onClearAllRequested: nil,
                onAnnotationEntry: { entryCount += 1 }
            ),
            2
        )
        fixture.router.clearCallbacks()
        XCTAssertEqual(
            fixture.router.bindCallbacks(
                onStateChange: { _ in stateChangeCount += 1 },
                onClearAllRequested: nil,
                onAnnotationEntry: { entryCount += 1 }
            ),
            2
        )

        fixture.router.route(.setMode(.annotation))

        XCTAssertEqual(entryCount, 1)
        XCTAssertGreaterThan(stateChangeCount, 0)
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
    var pointerUUID: DisplayUUID?

    init(displays: [DisplayDescriptor], pointerUUID: DisplayUUID? = nil) {
        self.displays = displays
        self.pointerUUID = pointerUUID
    }

    func currentDisplays() -> [DisplayDescriptor] { displays }
    func pointerDisplay() -> DisplayUUID? { pointerUUID ?? displays.first?.uuid }

    static func descriptor(uuid: DisplayUUID) -> DisplayDescriptor {
        DisplayDescriptor(
            uuid: uuid,
            frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
            scaleFactor: 2
        )
    }
}

@MainActor
private final class RouterTestOverlay: OverlayPresenting {
    var display: DisplayDescriptor
    var didCancelGesture = false
    private var hasActiveGesture = false
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
    func cancelActiveGesture() {
        guard hasActiveGesture else { return }
        didCancelGesture = true
        _ = session.cancelGesture()
        hasActiveGesture = false
        onSessionUpdate?(session)
    }
    func close() {}

    func beginDraft() {
        _ = session.beginGesture(
            tool: .arrow,
            at: NormalizedPoint(x: 0.2, y: 0.2),
            on: display.uuid
        )
        hasActiveGesture = true
    }

    func finishDraft() {
        guard hasActiveGesture else { return }
        _ = session.commitGesture()
        hasActiveGesture = false
        onSessionUpdate?(session)
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
