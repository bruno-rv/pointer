import XCTest
@testable import PointerAppKit

@MainActor
final class HotKeyControllerTests: XCTestCase {
    func testCandidateRegistrationKeepsPreviousTokenUntilDelivery() throws {
        let registrar = FakeHotKeyRegistrar()
        let store = FakeShortcutStore(stored: .controlOptionCommandP)
        let scheduler = FakeShortcutScheduler()
        let controller = HotKeyController(
            registrar: registrar,
            store: store,
            scheduler: scheduler
        )

        controller.start()
        let previousToken = try XCTUnwrap(controller.activeToken)

        controller.setShortcut(.controlOptionCommandO)

        let candidateToken = try XCTUnwrap(controller.pendingToken)
        XCTAssertEqual(controller.activePreset, .controlOptionCommandP)
        XCTAssertEqual(controller.pendingPreset, .controlOptionCommandO)
        XCTAssertTrue(registrar.isRegistered(previousToken))
        XCTAssertTrue(registrar.isRegistered(candidateToken))
        XCTAssertEqual(store.stored, .controlOptionCommandP)
    }

    func testDeliveryPersistsCandidateThenUnregistersPreviousToken() throws {
        let registrar = FakeHotKeyRegistrar()
        let store = FakeShortcutStore(stored: .controlOptionCommandP)
        let scheduler = FakeShortcutScheduler()
        let controller = HotKeyController(
            registrar: registrar,
            store: store,
            scheduler: scheduler
        )

        controller.start()
        let previousToken = try XCTUnwrap(controller.activeToken)
        controller.setShortcut(.controlOptionCommandO)
        let candidateToken = try XCTUnwrap(controller.pendingToken)

        registrar.deliver(candidateToken)

        XCTAssertEqual(controller.activePreset, .controlOptionCommandO)
        XCTAssertNil(controller.pendingPreset)
        XCTAssertEqual(store.stored, .controlOptionCommandO)
        XCTAssertFalse(registrar.isRegistered(previousToken))
        XCTAssertTrue(registrar.isRegistered(candidateToken))
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testTimeoutUnregistersCandidateAndLeavesPreviousPreferenceUntouched() throws {
        let registrar = FakeHotKeyRegistrar()
        let store = FakeShortcutStore(stored: .controlOptionCommandO)
        let scheduler = FakeShortcutScheduler()
        let controller = HotKeyController(
            registrar: registrar,
            store: store,
            scheduler: scheduler
        )

        controller.start()
        let previousToken = try XCTUnwrap(controller.activeToken)
        controller.setShortcut(.controlOptionCommandP)
        let candidateToken = try XCTUnwrap(controller.pendingToken)

        scheduler.fireNext()

        XCTAssertEqual(controller.activePreset, .controlOptionCommandO)
        XCTAssertNil(controller.pendingPreset)
        XCTAssertEqual(store.stored, .controlOptionCommandO)
        XCTAssertTrue(registrar.isRegistered(previousToken))
        XCTAssertFalse(registrar.isRegistered(candidateToken))
        XCTAssertEqual(scheduler.intervals, [5])
        XCTAssertEqual(
            controller.registrationError,
            "Control-Option-Command-P was not delivered within five seconds."
        )
    }

    func testLateCandidateEventAfterTimeoutCannotReplacePreviousShortcut() throws {
        let registrar = FakeHotKeyRegistrar()
        let store = FakeShortcutStore(stored: .controlOptionCommandP)
        let scheduler = FakeShortcutScheduler()
        let controller = HotKeyController(
            registrar: registrar,
            store: store,
            scheduler: scheduler
        )
        var toggleCount = 0
        controller.onToggle = { toggleCount += 1 }

        controller.start()
        controller.setShortcut(.controlOptionCommandO)
        let candidateToken = try XCTUnwrap(controller.pendingToken)
        scheduler.fireNext()

        registrar.deliver(candidateToken)

        XCTAssertEqual(controller.activePreset, .controlOptionCommandP)
        XCTAssertEqual(store.stored, .controlOptionCommandP)
        XCTAssertEqual(toggleCount, 0)
    }

    func testStartupFallsBackFromStoredToDefaultThenDisabled() {
        let fallbackRegistrar = FakeHotKeyRegistrar(
            failures: [.controlOptionCommandO]
        )
        let fallbackStore = FakeShortcutStore(stored: .controlOptionCommandO)
        let fallbackController = HotKeyController(
            registrar: fallbackRegistrar,
            store: fallbackStore,
            scheduler: FakeShortcutScheduler()
        )

        fallbackController.start()

        XCTAssertEqual(fallbackController.activePreset, .controlOptionCommandP)
        XCTAssertEqual(fallbackStore.stored, .controlOptionCommandO)
        XCTAssertNil(fallbackController.registrationError)

        let disabledRegistrar = FakeHotKeyRegistrar(
            failures: [.controlOptionCommandO, .controlOptionCommandP]
        )
        let disabledStore = FakeShortcutStore(stored: .controlOptionCommandO)
        let disabledController = HotKeyController(
            registrar: disabledRegistrar,
            store: disabledStore,
            scheduler: FakeShortcutScheduler()
        )

        disabledController.start()

        XCTAssertNil(disabledController.activePreset)
        XCTAssertEqual(disabledStore.stored, .controlOptionCommandO)
        XCTAssertNotNil(disabledController.registrationError)
    }
}

@MainActor
private final class FakeHotKeyRegistrar: HotKeyRegistering {
    var onEvent: ((HotKeyToken) -> Void)?
    private(set) var registrations: [HotKeyToken: ShortcutPreset] = [:]
    private var nextToken: UInt64 = 1
    var failures: Set<ShortcutPreset>

    init(failures: Set<ShortcutPreset> = []) {
        self.failures = failures
    }

    func register(_ preset: ShortcutPreset) throws -> HotKeyToken {
        if failures.contains(preset) {
            throw FakeHotKeyError.registrationFailed
        }
        let token = HotKeyToken(rawValue: nextToken)
        nextToken += 1
        registrations[token] = preset
        return token
    }

    func unregister(_ token: HotKeyToken) {
        registrations.removeValue(forKey: token)
    }

    func isRegistered(_ token: HotKeyToken) -> Bool {
        registrations[token] != nil
    }

    func deliver(_ token: HotKeyToken) {
        onEvent?(token)
    }
}

@MainActor
private final class FakeShortcutStore: ShortcutStoring {
    var stored: ShortcutPreset?

    init(stored: ShortcutPreset?) {
        self.stored = stored
    }

    func load() -> ShortcutPreset? { stored }
    func save(_ preset: ShortcutPreset) { stored = preset }
}

@MainActor
private final class FakeShortcutScheduler: ShortcutScheduling {
    private var nextToken: UInt64 = 1
    private var actions: [ShortcutScheduleToken: () -> Void] = [:]
    private var order: [ShortcutScheduleToken] = []
    private(set) var intervals: [TimeInterval] = []

    var pendingCount: Int { actions.count }
    var activeTimerCount: Int { actions.count }

    @discardableResult
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> ShortcutScheduleToken {
        let token = ShortcutScheduleToken(rawValue: nextToken)
        nextToken += 1
        intervals.append(interval)
        actions[token] = action
        order.append(token)
        return token
    }

    func cancel(_ token: ShortcutScheduleToken) {
        actions.removeValue(forKey: token)
        order.removeAll { $0 == token }
    }

    func fireNext() {
        guard let token = order.first,
              let action = actions.removeValue(forKey: token) else {
            return
        }
        order.removeFirst()
        action()
    }
}

private enum FakeHotKeyError: Error {
    case registrationFailed
}
