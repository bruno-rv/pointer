import AppKit
import Foundation
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

    func testIntegratedControllerOwnsRealGuideAcrossStartStopAndExplicitReopen() throws {
        let fixture = try IntegratedRealGuideLifecycleFixture()
        fixture.start()
        defer { fixture.cleanup() }

        let firstPanel = try XCTUnwrap(fixture.visibleGuidePanel)
        let firstViewController = try XCTUnwrap(
            firstPanel.contentViewController as? FirstUseGuideViewController
        )
        XCTAssertTrue(fixture.guide.isVisible)
        XCTAssertTrue(firstPanel.isKeyWindow)
        XCTAssertTrue(
            firstPanel.firstResponder === firstViewController.doneButton,
            "The integrated first-use guide should give focus to Done"
        )
        XCTAssertEqual(firstViewController.exampleImageViews.count, 8)
        XCTAssertTrue(firstViewController.exampleImageViews.allSatisfy { $0.image != nil })
        XCTAssertTrue(firstViewController.resolutionErrors.isEmpty)
        XCTAssertTrue(firstViewController.isAppearanceObservationActive)
        XCTAssertTrue(fixture.guideStateStore.hasDismissedFirstUseGuide)
        XCTAssertEqual(fixture.guideStateStore.markCount, 1)
        assertIntegratedRunningCheckpoint(fixture, guideVisible: true)

        fixture.controller.stop()
        XCTAssertFalse(fixture.guide.isVisible)
        XCTAssertFalse(firstPanel.isVisible)
        XCTAssertFalse(firstPanel.isKeyWindow)
        XCTAssertFalse(firstViewController.isAppearanceObservationActive)
        assertIntegratedStoppedCheckpoint(fixture)

        fixture.controller.start()
        XCTAssertFalse(fixture.guide.isVisible)
        XCTAssertNil(fixture.visibleGuidePanel)
        XCTAssertEqual(fixture.guideStateStore.markCount, 1)
        assertIntegratedRunningCheckpoint(fixture, guideVisible: false)

        XCTAssertEqual(fixture.controller.showGuide(), .shown)
        let secondPanel = try XCTUnwrap(fixture.visibleGuidePanel)
        let secondViewController = try XCTUnwrap(
            secondPanel.contentViewController as? FirstUseGuideViewController
        )
        XCTAssertFalse(secondPanel === firstPanel)
        XCTAssertTrue(fixture.guide.isVisible)
        XCTAssertTrue(secondPanel.isKeyWindow)
        XCTAssertTrue(secondViewController.isAppearanceObservationActive)
        XCTAssertEqual(secondViewController.exampleImageViews.count, 8)
        XCTAssertEqual(fixture.guideStateStore.markCount, 1)

        XCTAssertEqual(
            fixture.controller.applicationShouldTerminate(NSApp),
            .terminateNow
        )
        XCTAssertFalse(fixture.guide.isVisible)
        XCTAssertFalse(secondPanel.isVisible)
        XCTAssertFalse(secondPanel.isKeyWindow)
        XCTAssertFalse(secondViewController.isAppearanceObservationActive)
        assertIntegratedStoppedCheckpoint(fixture)
    }

    func testStopCancelsUnfinishedRealGesturesWithoutCommittingDraftsOnOneAndTwoDisplays() throws {
        for displayCount in [1, 2] {
            let fixture = LifecycleInteractionFixture(displayCount: displayCount)
            fixture.start()
            defer { fixture.stop() }

            let display = fixture.displayDescriptors[0]
            let overlay = try XCTUnwrap(
                fixture.coordinator.overlays[display.uuid] as? OverlayPanel
            )
            drawArrow(on: overlay, in: fixture)
            let committedBeforeGesture = fixture.coordinator.session.canvas(for: display.uuid)
            overlay.canvasView.beginGesture(at: NSPoint(x: 180, y: 160))
            overlay.canvasView.continueGesture(to: NSPoint(x: 500, y: 360))

            XCTAssertTrue(overlay.canvasView.hasActiveGesture)
            XCTAssertNotNil(overlay.canvasView.renderPlan.activeDraft)
            XCTAssertEqual(
                fixture.coordinator.session.canvas(for: display.uuid),
                committedBeforeGesture
            )

            fixture.stop()

            let stopResult = try XCTUnwrap(fixture.controller.lastDisplayStopResult)
            XCTAssertEqual(stopResult.closedOverlayCount, displayCount)
            XCTAssertEqual(stopResult.activeGestureCount, 1)
            XCTAssertEqual(stopResult.clearedHandlerCount, displayCount * 2)
            XCTAssertEqual(stopResult.remainingOverlayCount, 0)
            XCTAssertEqual(stopResult.boundHandlerCount, 0)
            XCTAssertEqual(
                fixture.coordinator.session.canvas(for: display.uuid),
                committedBeforeGesture
            )
            XCTAssertNil(overlay.canvasView.renderPlan.activeDraft)
            assertStoppedCheckpoint(fixture)
        }
    }

    func testStaleShortcutEventsAfterStopCannotMutateStoppedCheckpointOrSession() throws {
        let fixture = LifecycleInteractionFixture(displayCount: 1)
        fixture.start()
        fixture.shortcutController.setShortcut(.controlOptionCommandO)
        let candidateToken = try XCTUnwrap(
            fixture.shortcutController.pendingToken,
            "Expected a captured pending token"
        )
        let activeToken = try XCTUnwrap(
            fixture.shortcutController.activeToken,
            "Expected a captured active token"
        )
        let storedBeforeStop = fixture.shortcutStore.stored

        fixture.stop()
        defer { fixture.stop() }
        let stoppedSession = fixture.coordinator.session
        let stoppedEvents = fixture.events
        let stoppedResult = try XCTUnwrap(fixture.controller.lastDisplayStopResult)

        fixture.shortcutScheduler.fireCanceled()
        fixture.registrar.deliver(candidateToken)
        fixture.registrar.deliver(activeToken)

        XCTAssertEqual(fixture.coordinator.session, stoppedSession)
        XCTAssertEqual(fixture.shortcutStore.stored, storedBeforeStop)
        XCTAssertEqual(fixture.events, stoppedEvents)
        XCTAssertEqual(fixture.controller.lastDisplayStopResult, stoppedResult)
        assertStoppedCheckpoint(fixture)
    }

    func testUnseenPendingGuideStopStartClearsRestoreIntentAndKeepsStateUntilVisible() throws {
        let fixture = LifecycleInteractionFixture(
            displayCount: 1,
            guideBecomesVisibleOnShow: false,
            guideShowIfNeededResult: .shown,
            guideRestoreAfterDisplayLossResult: .failed("panel unavailable")
        )
        fixture.start()
        let mark = Mark(
            geometry: .rectangle(
                NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.25)
            ),
            style: .default
        )
        fixture.coordinator.apply(.setTool(.rectangle))
        fixture.coordinator.apply(.append(mark, to: fixture.display.uuid))
        let sessionBeforeDisplayLoss = fixture.coordinator.session
        XCTAssertFalse(fixture.guide.isVisible)
        XCTAssertFalse(fixture.guideStateStore.hasDismissedFirstUseGuide)
        XCTAssertEqual(fixture.guideStateStore.markCount, 0)

        fixture.provider.displays = []
        fixture.postScreenChange()
        XCTAssertFalse(fixture.guide.isVisible)
        XCTAssertFalse(fixture.guideStateStore.hasDismissedFirstUseGuide)
        XCTAssertEqual(fixture.guideStateStore.markCount, 0)

        fixture.controller.stop()
        assertStoppedCheckpoint(fixture)
        fixture.provider.displays = [fixture.display]
        fixture.events.removeAll()

        fixture.controller.start()
        defer { fixture.stop() }

        XCTAssertEqual(fixture.events, ["palette.show", "guide.showIfNeeded"])
        XCTAssertFalse(fixture.events.contains("guide.restoreAfterDisplayLoss"))
        XCTAssertFalse(fixture.guide.isVisible)
        XCTAssertFalse(fixture.guideStateStore.hasDismissedFirstUseGuide)
        XCTAssertEqual(fixture.guideStateStore.markCount, 0)
        XCTAssertEqual(fixture.coordinator.session, sessionBeforeDisplayLoss)
        assertRunningCheckpoint(fixture, displayCount: 1, guideVisible: false)
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

    private func assertIntegratedRunningCheckpoint(
        _ fixture: IntegratedRealGuideLifecycleFixture,
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
        XCTAssertEqual(
            checkpoint.overlayCount,
            fixture.displayDescriptors.count,
            file: file,
            line: line
        )
        XCTAssertEqual(checkpoint.callbackCount, 5, file: file, line: line)
        XCTAssertEqual(checkpoint.timerCount, 0, file: file, line: line)
        XCTAssertEqual(checkpoint.guideCount, guideVisible ? 1 : 0, file: file, line: line)
        XCTAssertEqual(fixture.menuBar.menuResourceCount, 1, file: file, line: line)
        XCTAssertEqual(fixture.menuBar.callbackBindingCount, 1, file: file, line: line)
        XCTAssertNotNil(fixture.shortcutController.registrar.onEvent, file: file, line: line)
        XCTAssertNotNil(fixture.shortcutController.onToggle, file: file, line: line)
        XCTAssertNotNil(fixture.shortcutController.onStateChange, file: file, line: line)
        XCTAssertEqual(fixture.palette.appearanceObserverCount, 1, file: file, line: line)
    }

    private func assertIntegratedStoppedCheckpoint(
        _ fixture: IntegratedRealGuideLifecycleFixture,
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
        XCTAssertEqual(fixture.palette.appearanceObserverCount, 0, file: file, line: line)
        XCTAssertNil(fixture.menuBar.statusItem, file: file, line: line)
        XCTAssertEqual(fixture.menuBar.callbackBindingCount, 0, file: file, line: line)
        XCTAssertNil(fixture.visibleGuidePanel, file: file, line: line)
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
