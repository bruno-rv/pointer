import XCTest
@testable import PointerAppKit

@MainActor
final class ShortcutLifecycleTests: XCTestCase {
    func testCandidateTimeoutKeepsOldShortcutAndReportsActionableError() throws {
        let fakes = ShortcutFakes()
        let controller = HotKeyController(
            registrar: fakes.registrar,
            store: fakes.store,
            scheduler: fakes.scheduler
        )

        controller.start()
        let old = controller.activePreset
        controller.setShortcut(.controlOptionCommandO)
        fakes.scheduler.fireAll()

        XCTAssertEqual(controller.activePreset, old)
        XCTAssertTrue(controller.registrationError?.contains("Control-Option-Command-O") == true)
        XCTAssertTrue(controller.registrationError?.contains("five seconds") == true)

        fakes.registrar.send(preset: .controlOptionCommandO)
        XCTAssertEqual(controller.activePreset, old)
    }

    func testDeliveredCandidatePersistsAndTogglesOnce() throws {
        let fakes = ShortcutFakes()
        let controller = HotKeyController(
            registrar: fakes.registrar,
            store: fakes.store,
            scheduler: fakes.scheduler
        )
        var toggles = 0
        controller.onToggle = { toggles += 1 }

        controller.start()
        controller.setShortcut(.controlOptionCommandO)
        fakes.registrar.send(preset: .controlOptionCommandO)

        XCTAssertEqual(controller.activePreset, .controlOptionCommandO)
        XCTAssertEqual(fakes.store.saved, [.controlOptionCommandO])
        XCTAssertEqual(toggles, 1)
    }

    func testStopStartRebindsOneCallbackAndOneTogglePerEvent() throws {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        fixture.controller.stop()
        fixture.controller.start()

        var toggles = 0
        let existingToggle = fixture.shortcutController.onToggle
        fixture.shortcutController.onToggle = {
            toggles += 1
            existingToggle?()
        }
        let activeToken = try XCTUnwrap(fixture.shortcutController.activeToken)

        fixture.registrar.deliver(activeToken)

        XCTAssertEqual(toggles, 1)
    }

    func testStopClearsToggleAndReleasesAllPendingShortcutResources() {
        let fakes = ShortcutFakes()
        let controller = HotKeyController(
            registrar: fakes.registrar,
            store: fakes.store,
            scheduler: fakes.scheduler
        )
        controller.onToggle = {}

        controller.start()
        controller.setShortcut(.controlOptionCommandO)
        controller.stop()

        XCTAssertNil(controller.onToggle)
        XCTAssertNil(controller.activePreset)
        XCTAssertNil(controller.activeToken)
        XCTAssertNil(controller.pendingPreset)
        XCTAssertNil(controller.pendingToken)
        XCTAssertEqual(fakes.scheduler.pendingCount, 0)
        XCTAssertTrue(fakes.registrar.registered.isEmpty)
    }

    func testExposesInjectedShortcutCollaboratorIdentities() {
        let fakes = ShortcutFakes()
        let controller = HotKeyController(
            registrar: fakes.registrar,
            store: fakes.store,
            scheduler: fakes.scheduler
        )

        XCTAssertTrue(controller.registrar === fakes.registrar)
        XCTAssertTrue(controller.store === fakes.store)
        XCTAssertTrue(controller.scheduler === fakes.scheduler)
    }
}

@MainActor
private final class ShortcutFakes {
    let registrar = ShortcutTestRegistrar()
    let store = ShortcutTestStore(stored: .controlOptionCommandP)
    let scheduler = ShortcutTestScheduler()
}

@MainActor
private final class ShortcutTestRegistrar: HotKeyRegistering {
    var onEvent: ((HotKeyToken) -> Void)?
    private(set) var registered: [HotKeyToken: ShortcutPreset] = [:]
    private var nextToken: UInt64 = 1

    func register(_ preset: ShortcutPreset) throws -> HotKeyToken {
        let token = HotKeyToken(rawValue: nextToken)
        nextToken += 1
        registered[token] = preset
        return token
    }

    func unregister(_ token: HotKeyToken) {
        registered.removeValue(forKey: token)
    }

    func send(preset: ShortcutPreset) {
        guard let token = registered.first(where: { $0.value == preset })?.key else { return }
        send(token: token)
    }

    func send(token: HotKeyToken) {
        guard registered[token] != nil else { return }
        onEvent?(token)
    }
}

@MainActor
private final class ShortcutTestStore: ShortcutStoring {
    private(set) var saved: [ShortcutPreset] = []
    private var stored: ShortcutPreset?

    init(stored: ShortcutPreset?) {
        self.stored = stored
    }

    func load() -> ShortcutPreset? { stored }

    func save(_ preset: ShortcutPreset) {
        stored = preset
        saved.append(preset)
    }
}

@MainActor
private final class ShortcutTestScheduler: ShortcutScheduling {
    private var nextToken: UInt64 = 1
    private var actions: [ShortcutScheduleToken: () -> Void] = [:]

    var pendingCount: Int { actions.count }

    @discardableResult
    func schedule(after _: TimeInterval, _ action: @escaping () -> Void) -> ShortcutScheduleToken {
        let token = ShortcutScheduleToken(rawValue: nextToken)
        nextToken += 1
        actions[token] = action
        return token
    }

    func cancel(_ token: ShortcutScheduleToken) {
        actions.removeValue(forKey: token)
    }

    func fireAll() {
        let pending = Array(actions.values)
        actions.removeAll()
        pending.forEach { $0() }
    }
}
