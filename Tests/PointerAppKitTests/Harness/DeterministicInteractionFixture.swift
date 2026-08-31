import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class HarnessClockAdapter: InteractionClock {
    private let clock: DeterministicClock

    init(clock: DeterministicClock = DeterministicClock()) {
        self.clock = clock
    }

    var nowNanoseconds: UInt64 {
        clock.nowNanoseconds
    }

    func advance(by nanoseconds: UInt64) {
        clock.advance(by: nanoseconds)
    }
}

@MainActor
final class DeterministicInteractionFixture {
    let screenProvider: DeterministicScreenProvider
    let displayCoordinator: DisplayCoordinator
    let commandRouter: CommandRouter
    let palette: PalettePanel
    let menuBar: MenuBarController
    let shortcutController: HotKeyController
    let metadataProvider: any ControlMetadataProviding
    let interactionClock: HarnessClockAdapter
    let reconnectedDescriptor: DisplayDescriptor?
    let otherDescriptor: DisplayDescriptor?

    private init(
        displays: [DisplayDescriptor],
        pointerDisplay: DisplayUUID?,
        reconnectedDescriptor: DisplayDescriptor? = nil,
        otherDescriptor: DisplayDescriptor? = nil
    ) {
        let screenProvider = DeterministicScreenProvider(
            displays: displays,
            pointerUUID: pointerDisplay
        )
        let coordinator = DisplayCoordinator(
            screenProvider: screenProvider,
            overlayFactory: { descriptor in OverlayPanel(descriptor: descriptor) }
        )
        let shortcutController = HotKeyController(
            registrar: HarnessHotKeyRegistrar(),
            store: HarnessShortcutStore(),
            scheduler: HarnessShortcutScheduler()
        )
        let router = CommandRouter(
            coordinator: coordinator,
            screenProvider: screenProvider,
            shortcutController: shortcutController
        )
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: GuidePlacementProvider()
        )
        let menuBar = MenuBarController(
            router: router,
            shortcutController: shortcutController,
            terminate: {}
        )

        self.screenProvider = screenProvider
        displayCoordinator = coordinator
        commandRouter = router
        self.palette = palette
        self.menuBar = menuBar
        self.shortcutController = shortcutController
        metadataProvider = ControlMetadataInventory(palette: palette, menuBar: menuBar)
        interactionClock = HarnessClockAdapter()
        self.reconnectedDescriptor = reconnectedDescriptor
        self.otherDescriptor = otherDescriptor

        // The controller is the real production object; the registrar is only
        // a deterministic OS-facing seam owned by this fixture.
        shortcutController.start()
    }

    static func oneDisplay() -> DeterministicInteractionFixture {
        let descriptor = DisplayFixtures.oneDisplay()[0]
        return DeterministicInteractionFixture(
            displays: [descriptor],
            pointerDisplay: descriptor.uuid
        )
    }

    static func standard() -> DeterministicInteractionFixture {
        oneDisplay()
    }

    static func clamped() -> DeterministicInteractionFixture {
        let descriptor = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "display-clamped"),
            frame: DisplayFrame(x: 0, y: 0, width: 792, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 792, height: 1_056),
            scaleFactor: 2
        )
        return DeterministicInteractionFixture(
            displays: [descriptor],
            pointerDisplay: descriptor.uuid
        )
    }

    static func narrow() -> DeterministicInteractionFixture {
        let descriptor = DisplayFixtures.narrowDisplay()[0]
        return DeterministicInteractionFixture(
            displays: [descriptor],
            pointerDisplay: descriptor.uuid
        )
    }

    static func twoDisplays() -> DeterministicInteractionFixture {
        let descriptors = DisplayFixtures.twoDisplays()
        return DeterministicInteractionFixture(
            displays: descriptors,
            pointerDisplay: descriptors[0].uuid,
            otherDescriptor: descriptors[1]
        )
    }

    static func empty() -> DeterministicInteractionFixture {
        DeterministicInteractionFixture(displays: [], pointerDisplay: nil)
    }

    static func malformedDisplay() -> DeterministicInteractionFixture {
        DeterministicInteractionFixture(
            displays: DisplayFixtures.invalidDisplayIdentifier(),
            pointerDisplay: nil
        )
    }

    static func disconnectedAndReconnected() -> DeterministicInteractionFixture {
        let fixtures = DisplayFixtures.disconnectedAndReconnected()
        let otherDescriptor = DisplayFixtures.twoDisplays()[1]
        return DeterministicInteractionFixture(
            displays: fixtures.disconnected + [otherDescriptor],
            pointerDisplay: fixtures.reconnectUUID,
            reconnectedDescriptor: fixtures.reconnected[0],
            otherDescriptor: otherDescriptor
        )
    }

    @discardableResult
    func assertConvergence(
        _ harness: DeterministicInteractionHarness,
        on display: DisplayUUID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> DeterministicInteractionSnapshot {
        let snapshot = harness.snapshot()
        let coordinatorSession = displayCoordinator.session
        let connectedDisplays = displayCoordinator.overlays.keys.sorted {
            $0.rawValue < $1.rawValue
        }
        XCTAssertTrue(connectedDisplays.contains(display), file: file, line: line)

        var expectedOwnerDraftID: Mark.ID?
        var selectedPlan: RenderPlan?
        for connectedDisplay in connectedDisplays {
            guard let overlay = displayCoordinator.overlays[connectedDisplay] as? OverlayPanel else {
                XCTFail(
                    "Expected a real OverlayPanel for \(connectedDisplay.rawValue)",
                    file: file,
                    line: line
                )
                continue
            }
            let canvas = overlay.canvasView
            let canvasSession = canvas.session
            XCTAssertEqual(canvasSession.mode, coordinatorSession.mode, file: file, line: line)
            XCTAssertEqual(canvasSession.toolState, coordinatorSession.toolState, file: file, line: line)
            XCTAssertEqual(canvasSession.selection, coordinatorSession.selection, file: file, line: line)
            XCTAssertEqual(canvasSession.selectedDisplay, coordinatorSession.selectedDisplay, file: file, line: line)
            XCTAssertEqual(
                canvasSession.canvas(for: connectedDisplay),
                coordinatorSession.canvas(for: connectedDisplay),
                file: file,
                line: line
            )
            if connectedDisplays.count == 1,
               Set(snapshot.marksByDisplay.keys) == Set(connectedDisplays),
               !canvas.hasActiveGesture
            {
                XCTAssertEqual(canvasSession, coordinatorSession, file: file, line: line)
            }

            let committedCanvas = coordinatorSession.canvas(for: connectedDisplay)
            let previewCanvas = canvasSession.previewCanvas(for: connectedDisplay)
            let committedIDs = Set(committedCanvas.marks.map(\.id))
            let draftCandidates = previewCanvas.marks.filter {
                !committedIDs.contains($0.id)
            }
            XCTAssertLessThanOrEqual(draftCandidates.count, 1, file: file, line: line)
            let expectedDraft = draftCandidates.count == 1 ? draftCandidates[0] : nil
            let plan = canvas.renderPlan
            let expectedPlanCommittedMarks = previewCanvas.marks.filter {
                $0.id != expectedDraft?.id
            }
            XCTAssertEqual(plan.committedMarks, expectedPlanCommittedMarks, file: file, line: line)
            XCTAssertEqual(plan.activeDraft, expectedDraft, file: file, line: line)
            XCTAssertEqual(
                Set(plan.committedMarks.map(\.id)).intersection(Set(draftCandidates.map(\.id))),
                [],
                file: file,
                line: line
            )
            let isGestureOwner = canvas.hasActiveGesture
                && coordinatorSession.hasActiveGesture(on: connectedDisplay)
            if !isGestureOwner {
                XCTAssertEqual(previewCanvas, committedCanvas, file: file, line: line)
            }
            XCTAssertEqual(
                plan.committedMarks.count + (plan.activeDraft == nil ? 0 : 1),
                previewCanvas.marks.count,
                file: file,
                line: line
            )
            XCTAssertEqual(
                snapshot.marksByDisplay[connectedDisplay],
                committedCanvas.marks,
                file: file,
                line: line
            )
            XCTAssertEqual(
                snapshot.previewMarksByDisplay[connectedDisplay],
                previewCanvas.marks,
                file: file,
                line: line
            )
            XCTAssertEqual(
                canvasSession.mode == .standby,
                overlay.ignoresMouseEvents,
                file: file,
                line: line
            )

            if canvas.hasActiveGesture,
               coordinatorSession.hasActiveGesture(on: connectedDisplay),
               let expectedDraft
            {
                XCTAssertNil(expectedOwnerDraftID, file: file, line: line)
                expectedOwnerDraftID = expectedDraft.id
            }
            if coordinatorSession.selectedDisplay == connectedDisplay,
               let selection = coordinatorSession.selection,
               plan.handles.selection.selectedMarkID == selection {
                selectedPlan = plan
            }
        }

        XCTAssertEqual(snapshot.activeDraftMarkID, expectedOwnerDraftID, file: file, line: line)
        XCTAssertEqual(
            snapshot.handleInventory,
            selectedPlan?.handles ?? Self.hiddenHandleInventory,
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.connectedDisplays,
            Set(displayCoordinator.overlays.keys),
            file: file,
            line: line
        )
        return snapshot
    }

    private static let hiddenHandleInventory = HandleInventory(
        selection: SelectionInventory(selectedMarkID: nil, isVisible: false),
        hover: HoverInventory(hoveredMarkID: nil, isVisible: false),
        resize: ResizeInventory(handles: [], isVisible: false),
        contextualDeleteVisible: false
    )

    func makeHarness() -> DeterministicInteractionHarness {
        DeterministicInteractionHarness(
            screenProvider: screenProvider,
            displayCoordinator: displayCoordinator,
            commandRouter: commandRouter,
            palette: palette,
            menuBar: menuBar,
            shortcutController: shortcutController,
            metadataProvider: metadataProvider,
            clock: interactionClock
        )
    }
}

@MainActor
private final class HarnessHotKeyRegistrar: HotKeyRegistering {
    var onEvent: ((HotKeyToken) -> Void)?
    private var nextToken: UInt64 = 1

    func register(_ preset: ShortcutPreset) throws -> HotKeyToken {
        defer { nextToken += 1 }
        return HotKeyToken(rawValue: nextToken)
    }

    func unregister(_ token: HotKeyToken) {}
}

@MainActor
private final class HarnessShortcutStore: ShortcutStoring {
    private var preset: ShortcutPreset?

    func load() -> ShortcutPreset? {
        preset
    }

    func save(_ preset: ShortcutPreset) {
        self.preset = preset
    }
}

@MainActor
private final class HarnessShortcutScheduler: ShortcutScheduling {
    private var nextToken: UInt64 = 1
    private var actions: [ShortcutScheduleToken: () -> Void] = [:]

    var activeTimerCount: Int {
        actions.count
    }

    @discardableResult
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> ShortcutScheduleToken {
        let token = ShortcutScheduleToken(rawValue: nextToken)
        nextToken += 1
        actions[token] = action
        return token
    }

    func cancel(_ token: ShortcutScheduleToken) {
        actions.removeValue(forKey: token)
    }
}
