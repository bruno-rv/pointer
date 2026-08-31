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
        let menuBar = MenuBarController(router: router, terminate: {})

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
        guard let overlay = displayCoordinator.overlays[display] as? OverlayPanel else {
            XCTFail("Expected a real OverlayPanel for \(display.rawValue)", file: file, line: line)
            return snapshot
        }

        let coordinatorSession = displayCoordinator.session
        let canvas = overlay.canvasView
        if canvas.hasActiveGesture {
            XCTAssertEqual(canvas.session.mode, coordinatorSession.mode, file: file, line: line)
            XCTAssertEqual(canvas.session.toolState, coordinatorSession.toolState, file: file, line: line)
            XCTAssertEqual(canvas.session.selection, coordinatorSession.selection, file: file, line: line)
            XCTAssertEqual(canvas.session.selectedDisplay, coordinatorSession.selectedDisplay, file: file, line: line)
            XCTAssertEqual(
                canvas.session.canvas(for: display),
                coordinatorSession.canvas(for: display),
                file: file,
                line: line
            )
        } else {
            XCTAssertEqual(canvas.session.mode, coordinatorSession.mode, file: file, line: line)
            XCTAssertEqual(canvas.session.toolState, coordinatorSession.toolState, file: file, line: line)
            XCTAssertEqual(canvas.session.selection, coordinatorSession.selection, file: file, line: line)
            XCTAssertEqual(canvas.session.selectedDisplay, coordinatorSession.selectedDisplay, file: file, line: line)
            XCTAssertEqual(
                canvas.session.canvas(for: display),
                coordinatorSession.canvas(for: display),
                file: file,
                line: line
            )
        }

        XCTAssertEqual(
            snapshot.marksByDisplay[display],
            coordinatorSession.canvas(for: display).marks,
            file: file,
            line: line
        )
        let previewCanvas = canvas.session.previewCanvas(for: display)
        XCTAssertEqual(snapshot.previewMarksByDisplay[display], previewCanvas.marks, file: file, line: line)

        let plan = canvas.renderPlan
        let expectedCommittedMarks = previewCanvas.marks.filter {
            $0.id != plan.activeDraft?.id
        }
        XCTAssertEqual(plan.committedMarks, expectedCommittedMarks, file: file, line: line)
        XCTAssertEqual(
            snapshot.activeDraftMarkID,
            plan.activeDraft?.id,
            file: file,
            line: line
        )
        if coordinatorSession.selectedDisplay == display,
           plan.handles.selection.selectedMarkID == coordinatorSession.selection {
            XCTAssertEqual(snapshot.handleInventory, plan.handles, file: file, line: line)
        }
        XCTAssertEqual(
            canvas.session.mode == .standby,
            overlay.ignoresMouseEvents,
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

    func makeHarness() -> DeterministicInteractionHarness {
        DeterministicInteractionHarness(
            displayCoordinator: displayCoordinator,
            commandRouter: commandRouter,
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
