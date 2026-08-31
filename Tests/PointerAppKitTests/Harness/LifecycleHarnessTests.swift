import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class LifecycleHarnessTests: XCTestCase {
    func testOneDisplayRunningCheckpointAndRealCanvasMarkUseExactResources() throws {
        let fixture = LifecycleInteractionFixture(displayCount: 1)
        fixture.start()
        defer { fixture.stop() }

        assertRunningCheckpoint(fixture, displayCount: 1, guideVisible: true)
        let display = try XCTUnwrap(fixture.provider.displays.first)
        let overlay = try XCTUnwrap(fixture.coordinator.overlays[display.uuid] as? OverlayPanel)
        let originalCanvas = overlay.canvasView

        drawArrow(on: overlay, in: fixture)

        XCTAssertEqual(fixture.coordinator.session.canvas(for: display.uuid).marks.count, 1)
        XCTAssertEqual(originalCanvas.renderPlan.committedMarks.count, 1)
        XCTAssertNil(originalCanvas.renderPlan.activeDraft)
        XCTAssertTrue(overlay.isVisible)
    }

    func testTwoDisplayRunningCheckpointAndEachRealOverlayCanDraw() throws {
        let fixture = LifecycleInteractionFixture(displayCount: 2)
        fixture.start()
        defer { fixture.stop() }

        assertRunningCheckpoint(fixture, displayCount: 2, guideVisible: true)
        for (index, display) in fixture.provider.displays.enumerated() {
            let overlay = try XCTUnwrap(
                fixture.coordinator.overlays[display.uuid] as? OverlayPanel
            )
            fixture.commandRouter.route(.setMode(.annotation))
            fixture.commandRouter.route(.setTool(index == 0 ? .arrow : .rectangle))
            overlay.canvasView.beginGesture(at: NSPoint(x: 120, y: 120))
            overlay.canvasView.continueGesture(to: NSPoint(x: 360, y: 280))
            overlay.canvasView.endGesture()

            XCTAssertEqual(
                fixture.coordinator.session.canvas(for: display.uuid).marks.count,
                1
            )
            XCTAssertEqual(overlay.canvasView.renderPlan.committedMarks.count, 1)
            XCTAssertNil(overlay.canvasView.renderPlan.activeDraft)
        }
    }

    func testStopZerosResourcesClosesRealOverlaysAndClearsOnlyProductionHandlers() throws {
        let fixture = LifecycleInteractionFixture(displayCount: 2)
        fixture.start()
        let overlays = try fixture.provider.displays.map { display in
            try XCTUnwrap(fixture.coordinator.overlays[display.uuid] as? OverlayPanel)
        }

        fixture.commandRouter.route(.setMode(.annotation))
        drawArrow(on: overlays[0], in: fixture)
        let beforeStop = fixture.controller.resourceCheckpoint
        XCTAssertEqual(beforeStop.overlayCount, 2)

        fixture.stop()

        let stopResult = try XCTUnwrap(fixture.controller.lastDisplayStopResult)
        XCTAssertEqual(
            stopResult,
            DisplayStopResult(
                closedOverlayCount: 2,
                remainingOverlayCount: 0,
                activeGestureCount: 0,
                clearedHandlerCount: 4,
                boundHandlerCount: 0
            )
        )
        assertStoppedCheckpoint(fixture)
        XCTAssertTrue(overlays.allSatisfy { !$0.isVisible })
        XCTAssertTrue(overlays.allSatisfy { $0.canvasView.onSessionUpdate == nil })
        XCTAssertTrue(overlays.allSatisfy { $0.canvasView.onBoundaryEvent == nil })
        XCTAssertEqual(fixture.coordinator.session.canvas(for: overlays[0].display.uuid).marks.count, 1)

        fixture.notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        XCTAssertEqual(fixture.controller.lastDisplayStopResult, stopResult)
        assertStoppedCheckpoint(fixture)
        XCTAssertTrue(fixture.coordinator.overlays.isEmpty)
    }

    func testFirstUseShownMarksSeenExactlyOnceAfterVisibleCallback() {
        let fixture = LifecycleInteractionFixture(displayCount: 1)
        fixture.start()
        defer { fixture.stop() }

        XCTAssertTrue(fixture.guide.isVisible)
        XCTAssertTrue(fixture.guideStateStore.hasDismissedFirstUseGuide)
        XCTAssertEqual(fixture.guideStateStore.markCount, 1)

        fixture.postScreenChange()

        XCTAssertTrue(fixture.guide.isVisible)
        XCTAssertTrue(fixture.guideStateStore.hasDismissedFirstUseGuide)
        XCTAssertEqual(fixture.guideStateStore.markCount, 1)
    }

    func testUnseenGuideHiddenBeforeVisibleKeepsStateUnseenAndRetriesAfterReconnect() {
        let fixture = LifecycleInteractionFixture(
            displayCount: 1,
            guideBecomesVisibleOnShow: false,
            guideShowIfNeededResult: .shown,
            guideRestoreAfterDisplayLossResult: .failed("panel unavailable")
        )
        fixture.start()
        defer { fixture.stop() }

        XCTAssertFalse(fixture.guide.isVisible)
        XCTAssertFalse(fixture.guideStateStore.hasDismissedFirstUseGuide)
        XCTAssertEqual(fixture.guideStateStore.markCount, 0)

        fixture.events.removeAll()
        fixture.provider.displays = []
        fixture.postScreenChange()
        XCTAssertFalse(fixture.guide.isVisible)
        XCTAssertFalse(fixture.guideStateStore.hasDismissedFirstUseGuide)
        XCTAssertEqual(fixture.guideStateStore.markCount, 0)

        fixture.provider.displays = [fixture.display]
        fixture.postScreenChange()
        XCTAssertFalse(fixture.guide.isVisible)
        XCTAssertFalse(fixture.guideStateStore.hasDismissedFirstUseGuide)
        XCTAssertEqual(fixture.guideStateStore.markCount, 0)
        XCTAssertEqual(
            fixture.events.filter { $0 == "guide.restoreAfterDisplayLoss" }.count,
            1
        )

        fixture.postScreenChange()
        XCTAssertEqual(
            fixture.events.filter { $0 == "guide.restoreAfterDisplayLoss" }.count,
            2
        )
        XCTAssertFalse(fixture.guideStateStore.hasDismissedFirstUseGuide)
        XCTAssertEqual(fixture.guideStateStore.markCount, 0)
    }

    func testRepeatedStopIsIdempotentAndDoesNotReopenResources() throws {
        let fixture = LifecycleInteractionFixture(displayCount: 1)
        fixture.start()
        fixture.stop()
        let firstStop = try XCTUnwrap(fixture.controller.lastDisplayStopResult)
        let firstStopped = fixture.controller.resourceCheckpoint

        fixture.stop()

        XCTAssertEqual(fixture.controller.lastDisplayStopResult, firstStop)
        XCTAssertEqual(fixture.controller.resourceCheckpoint, firstStopped)
        XCTAssertEqual(
            fixture.coordinator.stop(),
            DisplayStopResult(
                closedOverlayCount: 0,
                remainingOverlayCount: 0,
                activeGestureCount: 0,
                clearedHandlerCount: 0,
                boundHandlerCount: 0
            )
        )
    }

    func testPendingShortcutTimerAndRegistrationAreCanceledBeforeStopReturns() throws {
        let fixture = LifecycleInteractionFixture(displayCount: 1)
        fixture.start()
        defer { fixture.stop() }

        fixture.shortcutController.setShortcut(.controlOptionCommandO)
        XCTAssertEqual(fixture.shortcutScheduler.activeTimerCount, 1)
        XCTAssertEqual(fixture.controller.resourceCheckpoint.timerCount, 1)
        XCTAssertNotNil(fixture.shortcutController.pendingToken)
        XCTAssertEqual(fixture.registrar.registrations.count, 2)

        fixture.stop()

        XCTAssertEqual(fixture.shortcutScheduler.activeTimerCount, 0)
        XCTAssertEqual(fixture.controller.resourceCheckpoint.timerCount, 0)
        XCTAssertNil(fixture.shortcutController.pendingToken)
        XCTAssertNil(fixture.shortcutController.pendingPreset)
        XCTAssertNil(fixture.shortcutController.activeToken)
        XCTAssertTrue(fixture.registrar.registrations.isEmpty)
        XCTAssertNil(fixture.registrar.onEvent)
        XCTAssertNil(fixture.shortcutController.onToggle)
        XCTAssertNil(fixture.shortcutController.onStateChange)
    }

    func testRestartRebuildsFreshRealOverlaysAndRetainsSessionCanvasExactlyOnce() throws {
        let fixture = LifecycleInteractionFixture(displayCount: 1)
        fixture.start()
        let display = try XCTUnwrap(fixture.provider.displays.first)
        let originalOverlay = try XCTUnwrap(
            fixture.coordinator.overlays[display.uuid] as? OverlayPanel
        )
        let originalCanvas = originalOverlay.canvasView
        let originalStatusItem = try XCTUnwrap(fixture.menuBar.statusItem)

        fixture.commandRouter.route(.setMode(.annotation))
        drawArrow(on: originalOverlay, in: fixture)
        fixture.stop()

        XCTAssertEqual(fixture.coordinator.session.canvas(for: display.uuid).marks.count, 1)

        fixture.start()
        defer { fixture.stop() }
        let restartedOverlay = try XCTUnwrap(
            fixture.coordinator.overlays[display.uuid] as? OverlayPanel
        )
        let restartedStatusItem = try XCTUnwrap(fixture.menuBar.statusItem)

        XCTAssertFalse(restartedOverlay === originalOverlay)
        XCTAssertFalse(restartedOverlay.canvasView === originalCanvas)
        XCTAssertFalse(restartedStatusItem === originalStatusItem)
        XCTAssertEqual(restartedOverlay.canvasView.session.mode, .standby)
        XCTAssertEqual(restartedOverlay.canvasView.session.canvas(for: display.uuid).marks.count, 1)
        assertRunningCheckpoint(fixture, displayCount: 1, guideVisible: false)

        let stableOverlay = restartedOverlay
        let stableCanvas = restartedOverlay.canvasView
        let stableStatusItem = restartedStatusItem
        fixture.controller.start()
        XCTAssertTrue(
            (fixture.coordinator.overlays[display.uuid] as? OverlayPanel) === stableOverlay
        )
        XCTAssertTrue(stableCanvas === restartedOverlay.canvasView)
        XCTAssertTrue(fixture.menuBar.statusItem === stableStatusItem)
        assertRunningCheckpoint(fixture, displayCount: 1, guideVisible: false)

        var syncCallbackCount = 0
        let existingDisplaySync = fixture.coordinator.onDisplaySync
        fixture.coordinator.onDisplaySync = { result in
            syncCallbackCount += 1
            existingDisplaySync?(result)
        }
        fixture.postScreenChange()
        XCTAssertEqual(syncCallbackCount, 1)

        var stateCallbackCount = 0
        let existingStateChange = fixture.commandRouter.onStateChange
        fixture.commandRouter.onStateChange = { session in
            stateCallbackCount += 1
            existingStateChange?(session)
        }
        let activeToken = try XCTUnwrap(fixture.shortcutController.activeToken)
        fixture.registrar.deliver(activeToken)
        XCTAssertEqual(stateCallbackCount, 1)
    }

    func testDisplayLossRestoresVisibleGuideOnlyAfterPaletteAndStopClearsRestoreIntent() throws {
        let fixture = LifecycleInteractionFixture(displayCount: 1)
        fixture.start()
        defer { fixture.stop() }
        fixture.events.removeAll()

        fixture.provider.displays = []
        fixture.postScreenChange()

        XCTAssertFalse(fixture.guide.isVisible)
        XCTAssertTrue(fixture.guideStateStore.hasDismissedFirstUseGuide)
        XCTAssertEqual(fixture.events, ["guide.hideForDisplayLoss"])
        XCTAssertEqual(fixture.controller.resourceCheckpoint.guideCount, 0)

        fixture.provider.displays = [fixture.displayDescriptors[0]]
        fixture.postScreenChange()

        XCTAssertTrue(fixture.guide.isVisible)
        XCTAssertEqual(
            fixture.events,
            [
                "guide.hideForDisplayLoss",
                "palette.show",
                "guide.restoreAfterDisplayLoss",
            ]
        )
        XCTAssertEqual(fixture.controller.resourceCheckpoint.guideCount, 1)

        fixture.controller.stop()
        XCTAssertFalse(fixture.guide.isVisible)
        XCTAssertTrue(fixture.events.contains("guide.hideForApplicationStop"))

        let eventsBeforeRestart = fixture.events
        fixture.controller.start()
        XCTAssertFalse(fixture.guide.isVisible)
        XCTAssertFalse(
            fixture.events
                .dropFirst(eventsBeforeRestart.count)
                .contains("guide.restoreAfterDisplayLoss")
        )
        XCTAssertEqual(fixture.controller.resourceCheckpoint.guideCount, 0)
    }

    private func assertRunningCheckpoint(
        _ fixture: LifecycleInteractionFixture,
        displayCount: Int,
        guideVisible: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let checkpoint = fixture.controller.resourceCheckpoint
        XCTAssertEqual(checkpoint.paletteCount, 1, file: file, line: line)
        XCTAssertEqual(checkpoint.menuCount, 1, file: file, line: line)
        XCTAssertEqual(checkpoint.screenObserverCount, 1, file: file, line: line)
        XCTAssertEqual(checkpoint.appearanceObserverCount, 1, file: file, line: line)
        XCTAssertEqual(checkpoint.shortcutWiringCount, 1, file: file, line: line)
        XCTAssertEqual(checkpoint.overlayCount, displayCount, file: file, line: line)
        XCTAssertEqual(checkpoint.callbackCount, 5, file: file, line: line)
        XCTAssertEqual(checkpoint.timerCount, 0, file: file, line: line)
        XCTAssertEqual(checkpoint.guideCount, guideVisible ? 1 : 0, file: file, line: line)
        XCTAssertEqual(fixture.menuBar.menuResourceCount, 1, file: file, line: line)
        XCTAssertEqual(fixture.menuBar.callbackBindingCount, 1, file: file, line: line)
        XCTAssertTrue(fixture.shortcutController.registrar.onEvent != nil, file: file, line: line)
        XCTAssertNotNil(fixture.shortcutController.onToggle, file: file, line: line)
        XCTAssertNotNil(fixture.shortcutController.onStateChange, file: file, line: line)
    }

    private func assertStoppedCheckpoint(
        _ fixture: LifecycleInteractionFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let checkpoint = fixture.controller.resourceCheckpoint
        XCTAssertEqual(checkpoint.paletteCount, 0, file: file, line: line)
        XCTAssertEqual(checkpoint.menuCount, 0, file: file, line: line)
        XCTAssertEqual(checkpoint.screenObserverCount, 0, file: file, line: line)
        XCTAssertEqual(checkpoint.appearanceObserverCount, 0, file: file, line: line)
        XCTAssertEqual(checkpoint.shortcutWiringCount, 0, file: file, line: line)
        XCTAssertEqual(checkpoint.overlayCount, 0, file: file, line: line)
        XCTAssertEqual(checkpoint.callbackCount, 0, file: file, line: line)
        XCTAssertEqual(checkpoint.timerCount, 0, file: file, line: line)
        XCTAssertEqual(checkpoint.guideCount, 0, file: file, line: line)
        XCTAssertNil(fixture.menuBar.statusItem, file: file, line: line)
        XCTAssertEqual(fixture.menuBar.callbackBindingCount, 0, file: file, line: line)
        XCTAssertNil(fixture.coordinator.onDisplaySync, file: file, line: line)
        XCTAssertNil(fixture.commandRouter.onStateChange, file: file, line: line)
        XCTAssertNil(fixture.commandRouter.onAnnotationEntry, file: file, line: line)
        XCTAssertNil(fixture.shortcutController.registrar.onEvent, file: file, line: line)
        XCTAssertNil(fixture.shortcutController.onToggle, file: file, line: line)
        XCTAssertNil(fixture.shortcutController.onStateChange, file: file, line: line)
    }

    private func drawArrow(on overlay: OverlayPanel, in fixture: LifecycleInteractionFixture) {
        fixture.commandRouter.route(.setMode(.annotation))
        overlay.canvasView.beginGesture(at: NSPoint(x: 120, y: 120))
        overlay.canvasView.continueGesture(to: NSPoint(x: 420, y: 300))
        overlay.canvasView.endGesture()
    }
}
