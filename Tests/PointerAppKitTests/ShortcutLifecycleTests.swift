import XCTest
import PointerCore
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

    func testControllerCompositionSharesShortcutGraphAndPublishesActiveStatus() {
        let fixture = GuideControllerFixture()

        XCTAssertTrue(fixture.controller.commandRouter === fixture.router)
        XCTAssertTrue(fixture.controller.shortcutController === fixture.shortcutController)
        XCTAssertTrue(fixture.controller.hotKeyRegistrar === fixture.registrar)
        XCTAssertTrue(fixture.controller.shortcutStore === fixture.shortcutStore)
        XCTAssertTrue(fixture.controller.shortcutScheduler === fixture.shortcutScheduler)

        fixture.controller.start()

        XCTAssertEqual(
            fixture.router.activeShortcutID,
            ShortcutPreset.defaultPreset.rawValue
        )
        XCTAssertNil(fixture.router.shortcutError)
    }

    func testCandidateRegistrationFailurePreservesOldShortcutAndReportsActionableError() throws {
        let fakes = ShortcutFakes(registrationFailures: [.controlOptionCommandO])
        let controller = HotKeyController(
            registrar: fakes.registrar,
            store: fakes.store,
            scheduler: fakes.scheduler
        )

        controller.start()
        let oldPreset = try XCTUnwrap(controller.activePreset)
        let oldToken = try XCTUnwrap(controller.activeToken)
        controller.setShortcut(.controlOptionCommandO)

        XCTAssertEqual(controller.activePreset, oldPreset)
        XCTAssertEqual(controller.activeToken, oldToken)
        XCTAssertEqual(fakes.registrar.registered[oldToken], oldPreset)
        XCTAssertTrue(fakes.store.saved.isEmpty)
        XCTAssertNil(controller.pendingPreset)
        XCTAssertNil(controller.pendingToken)
        XCTAssertEqual(fakes.scheduler.pendingCount, 0)
        XCTAssertTrue(controller.registrationError?.contains("Control-Option-Command-O") == true)
        XCTAssertTrue(controller.registrationError?.contains("five-second") == true)

        fakes.registrar.send(token: HotKeyToken(rawValue: oldToken.rawValue + 1))
        XCTAssertEqual(controller.activePreset, oldPreset)
        XCTAssertEqual(controller.activeToken, oldToken)
    }

    func testSetShortcutThroughCommandRouterPublishesPendingAndTimeoutStatus() throws {
        let fakes = ShortcutFakes()
        let screenProvider = ShortcutTestScreenProvider()
        let coordinator = DisplayCoordinator(screenProvider: screenProvider)
        let controller = HotKeyController(
            registrar: fakes.registrar,
            store: fakes.store,
            scheduler: fakes.scheduler
        )
        let router = CommandRouter(
            coordinator: coordinator,
            screenProvider: screenProvider,
            shortcutController: controller
        )

        controller.start()
        router.route(.setShortcut(.controlOptionCommandO))

        XCTAssertEqual(router.activeShortcutID, ShortcutPreset.defaultPreset.rawValue)
        XCTAssertNil(router.shortcutError)
        XCTAssertEqual(controller.pendingPreset, .controlOptionCommandO)

        fakes.scheduler.fireAll()

        XCTAssertEqual(router.activeShortcutID, ShortcutPreset.defaultPreset.rawValue)
        XCTAssertTrue(router.shortcutError?.contains("Control-Option-Command-O") == true)
        XCTAssertTrue(router.shortcutError?.contains("five seconds") == true)
    }

    func testStopStartRebindsOneCallbackAndOneTogglePerEvent() throws {
        let fixture = GuideControllerFixture()
        fixture.controller.start()
        fixture.controller.stop()
        fixture.controller.start()

        var stateChanges = 0
        let existingStateChange = fixture.router.onStateChange
        fixture.router.onStateChange = { session in
            stateChanges += 1
            existingStateChange?(session)
        }
        let activeToken = try XCTUnwrap(fixture.shortcutController.activeToken)

        fixture.registrar.deliver(activeToken)

        XCTAssertEqual(fixture.router.session.mode, .annotation)
        XCTAssertEqual(stateChanges, 1)
        XCTAssertEqual(
            fixture.router.activeShortcutID,
            ShortcutPreset.defaultPreset.rawValue
        )
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
    let registrar: ShortcutTestRegistrar
    let store: ShortcutTestStore
    let scheduler: ShortcutTestScheduler

    init(registrationFailures: Set<ShortcutPreset> = []) {
        registrar = ShortcutTestRegistrar(failures: registrationFailures)
        store = ShortcutTestStore(stored: .controlOptionCommandP)
        scheduler = ShortcutTestScheduler()
    }
}

@MainActor
private final class ShortcutTestRegistrar: HotKeyRegistering {
    var onEvent: ((HotKeyToken) -> Void)?
    private(set) var registered: [HotKeyToken: ShortcutPreset] = [:]
    private var nextToken: UInt64 = 1
    var failures: Set<ShortcutPreset>

    init(failures: Set<ShortcutPreset> = []) {
        self.failures = failures
    }

    func register(_ preset: ShortcutPreset) throws -> HotKeyToken {
        if failures.contains(preset) {
            throw ShortcutTestError.registrationFailed
        }
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
    var activeTimerCount: Int { actions.count }

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

@MainActor
private final class ShortcutTestScreenProvider: ScreenProviding {
    func currentDisplays() -> [DisplayDescriptor] { [] }
    func pointerDisplay() -> DisplayUUID? { nil }
}

private enum ShortcutTestError: Error {
    case registrationFailed
}
