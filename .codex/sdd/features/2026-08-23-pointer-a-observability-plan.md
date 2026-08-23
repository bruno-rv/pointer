# Pointer A — Observability and Deterministic Use Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking. The coordinating agent owns commits and publication; worker tasks end with evidence/status handoff instead of commit steps.

**Goal:** Make Pointer's real command, session, canvas, overlay, and display paths inspectable through stable JSON and a deterministic interaction seam without adding a second interaction engine or synthetic global input.

**Architecture:** Stage A-foundation independently extends the no-window SmokeRunner report and creates only phase-neutral screen/clock/value fakes under Tests/PointerAppKitTests/Support/**. After B core, B-render-integration, C, and D contracts are accepted, the later A-harness phase owns real integrated fixtures/tests under Tests/PointerAppKitTests/Harness/** and the production diagnostic harness; foundation files never construct a coordinator, palette, menu, overlay, or harness.

**Tech Stack:** Swift tools 5.10, macOS 14+, AppKit, PointerCore, PointerAppKit, XCTest, JSONEncoder, ContinuousClock-compatible injected clock, Swift concurrency.

**Spec:** .codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md (Workstream A — observability and deterministic use; Workstream B/C accepted contracts consumed only by their documented interfaces).

## Global Constraints

- The campaign improves the current annotation product. It does not broaden the product into a document or distribution platform.
- PointerCore owns AppKit-free value models, normalized display-local geometry, gesture transactions, hit testing, tool state, selection, and undo.
- PointerAppKit owns the native application lifecycle, menu bar, palette, display coordination, transparent overlay panels, rendering, local keyboard routing, and Carbon shortcut registration.
- PointerComposition is an importable library containing the sole dependency-injected composition factory; it depends on PointerCore and PointerAppKit and is usable by composition tests without importing the executable.
- There is one overlay and one in-memory display canvas per connected physical display. Canvas identity is a stable display UUID, never a transient display ID. .scratch/ prototypes remain evidence and are not production dependencies.
- Deterministic evidence cannot establish that a person could physically find a control, drag a mark, use VoiceOver against a live window, or operate Pointer across real displays and Spaces; reports must label evidence class.
- Keep deterministic seams on the same command and validation routes as the app. Do not add global event monitors, Quartz event taps, input synthesis, screen capture, or accessibility workarounds to make automation easier.
- Work only in /Users/bruno/Dev/pointer/.worktrees/stable-app; preserve unrelated dirty files and generated artifacts in /Users/bruno/Dev/pointer.
- A-foundation owns Sources/PointerAppKit/Diagnostics/SmokeRunner.swift, Tests/PointerAppKitTests/SmokeRunnerTests.swift, and phase-neutral fakes/tests under Tests/PointerAppKitTests/Support/**. A-harness, scheduled only after B-render-integration/C/D handoffs, owns Sources/PointerAppKit/Diagnostics/DeterministicInteractionHarness.swift and integrated fixtures/tests under Tests/PointerAppKitTests/Harness/**, including CanvasIntegrationHarnessTests.swift. Neither phase edits B–F production or test scopes.

---

## Dependency and handoff contract

Tasks 1–2 are independent and must finish before B starts. Task 3 is a scheduled follow-up, not part of the independent A foundation: it starts only after B core, the separate B-render-integration phase, C's PalettePresenting/CommandRouter/metadata/active-shortcut contracts, and D's public RenderPlan/HandleInventory contracts are accepted. A never edits B/C/D files to make the harness compile. If a read-only query is missing, the coordinator assigns the smallest interface follow-up to its owner before resuming Task 3.

The harness must use these names and types:

    @MainActor
    public struct DeterministicInteractionSnapshot: Equatable, Sendable {
        public let mode: PointerMode
        public let selectedTool: PointerTool
        public let selectedStyle: MarkStyle
        public let selection: Mark.ID?
        public let marksByDisplay: [DisplayUUID: [Mark]]
        public let previewMarksByDisplay: [DisplayUUID: [Mark]]
        public let activeDraftMarkID: Mark.ID?
        public let handleInventory: HandleInventory
        public let undoAvailable: Bool
        public let shortcutID: String?
        public let shortcutError: String?
        public let connectedDisplays: Set<DisplayUUID>
    }

    @MainActor
    public protocol InteractionClock: AnyObject {
        var nowNanoseconds: UInt64 { get }
    }

    @MainActor
    public final class DeterministicInteractionHarness {
        public init(
            screenProvider: any ScreenProviding,
            displayCoordinator: DisplayCoordinator,
            commandRouter: CommandRouter,
            palette: any PalettePresenting,
            menuBar: (any MenuBarPresenting)?,
            shortcutController: HotKeyController,
            metadataProvider: any ControlMetadataProviding,
            clock: any InteractionClock
        )
        public func synchronizeDisplays() -> DisplaySyncResult
        public func route(_ command: CommandRouter.Command)
        public func routeLocalKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> Bool
        public func beginGesture(at point: NSPoint, on display: DisplayUUID) throws
        public func continueGesture(to point: NSPoint, on display: DisplayUUID) throws
        public func endGesture(on display: DisplayUUID) throws
        public func cancelGesture(on display: DisplayUUID) throws
        public func snapshot() -> DeterministicInteractionSnapshot
        public func metadata() -> [ControlMetadata]
    }

The foundation fakes are phase-neutral values only. The later Harness/DeterministicInteractionFixture constructs the exact real DisplayCoordinator, CommandRouter, PalettePanel, MenuBarController, HotKeyController, deterministic ScreenProviding, and HarnessClockAdapter wrapping the Support DeterministicClock; no Support file exposes a coordinator, palette, menu, overlay, harness, or makeHarness method.

## Task 1: Lock the no-window smoke contract

**Files:**

- Modify: Sources/PointerAppKit/Diagnostics/SmokeRunner.swift
- Modify: Tests/PointerAppKitTests/SmokeRunnerTests.swift
- Create: Tests/PointerAppKitTests/Support/SmokeFixtures.swift

**Interfaces:**

- Preserve SmokeRunner.report(displays:) -> SmokeRunner.Report and SmokeRunner.json(displays:) throws -> Data.
- Extend SmokeRunner.Report with selectedToolID: String, styleColorRGBA: [Double], strokeWidth: Double, and opacity: Double; keep paletteCount, overlayCount, mode, and shortcutID.
- Encode mode as "standby", selectedToolID as "arrow", and the default style as [1.0, 0.0, 0.0, 1.0], 4.0, and 1.0. Keep sorted-key JSON and no AppKit window construction.

- [ ] **Step 1: Add the failing report assertions.**

    func testSmokeReportIncludesStableDefaultToolAndStyle() throws {
        let report = SmokeRunner.report(displays: [.builtIn, .external])
        XCTAssertEqual(report.paletteCount, 1)
        XCTAssertEqual(report.overlayCount, 2)
        XCTAssertEqual(report.mode, .standby)
        XCTAssertEqual(report.selectedToolID, "arrow")
        XCTAssertEqual(report.styleColorRGBA, [1, 0, 0, 1])
        XCTAssertEqual(report.strokeWidth, 4)
        XCTAssertEqual(report.opacity, 1)
        XCTAssertEqual(report.shortcutID, "control-option-command-p")
    }

    func testSmokeJSONIsStableAndContainsNoWindowRequirement() throws {
        let first = try SmokeRunner.json(displays: [.builtIn, .external])
        let second = try SmokeRunner.json(displays: [.builtIn, .external])
        XCTAssertEqual(first, second)
        XCTAssertEqual(String(decoding: first, as: UTF8.self),
                       "{\"mode\":\"standby\",\"opacity\":1,\"overlayCount\":2,\"paletteCount\":1,\"selectedToolID\":\"arrow\",\"shortcutID\":\"control-option-command-p\",\"strokeWidth\":4,\"styleColorRGBA\":[1,0,0,1]}")
    }

- [ ] **Step 2: Run the focused test and verify RED.**

Run:

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      swift test --filter 'SmokeRunnerTests.testSmokeReportIncludesStableDefaultToolAndStyle|SmokeRunnerTests.testSmokeJSONIsStableAndContainsNoWindowRequirement'

Expected: compilation fails because the new report fields and exact encoding are absent. A failure caused by a missing Xcode toolchain is an environment failure and must be reported separately.

- [ ] **Step 3: Implement the minimum report extension.**

Use one private coding key enum and literal model defaults rather than constructing PointerApplication, DisplayCoordinator, PalettePanel, or NSApplication:

    fileprivate init(overlayCount: Int) {
        paletteCount = 1
        self.overlayCount = overlayCount
        mode = .standby
        selectedToolID = "arrow"
        styleColorRGBA = [1, 0, 0, 1]
        strokeWidth = 4
        opacity = 1
        shortcutID = ShortcutPreset.defaultPreset.rawValue
    }

The manual encoder writes all eight keys with the exact raw values above. Reject no display arguments only in the CLI layer; report(displays: []) remains a valid deterministic zero-overlay fixture for later edge-case tests.

- [ ] **Step 4: Run focused and full AppKit tests.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      swift test --filter SmokeRunnerTests
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

Expected: both smoke tests pass and all existing tests pass. Hand off the exact JSON string, test output, and scope check to the coordinator.

## Task 2: Add shared deterministic screen, clock, and metadata fixtures

**Files:**

- Create: Tests/PointerAppKitTests/Support/DeterministicScreenProvider.swift
- Create: Tests/PointerAppKitTests/Support/DeterministicClock.swift
- Create: Tests/PointerAppKitTests/Support/DisplayFixtures.swift
- Create: Tests/PointerAppKitTests/Support/DeterministicFixtureTests.swift

**Interfaces:**

- DeterministicScreenProvider: ScreenProviding exposes var displays: [DisplayDescriptor], var pointerUUID: DisplayUUID?, and returns snapshots without querying NSScreen.
- DeterministicClock exposes var nowNanoseconds: UInt64 and advance(by nanoseconds: UInt64), performs no wall-clock or sleep operation, and remains protocol-independent until the later Harness phase.
- DisplayFixtures exposes empty(), oneDisplay(), twoDisplays(), narrowDisplay(), invalidDisplayIdentifier(), and disconnectedAndReconnected() as stable descriptors and UUIDs only.
- DeterministicScreenProvider conforms to ScreenProviding with mutable displays/pointerUUID; DeterministicClock is a phase-neutral class exposing nowNanoseconds and advance(by:) without adopting a later harness protocol, and neither constructs a production object or sleeps.

- [ ] **Step 1: Write fixture invariant tests.**

    final class DeterministicFixtureTests: XCTestCase {
        @MainActor
        func testFixtureCoversEmptyOneTwoNarrowInvalidAndReconnectStates() {
        XCTAssertTrue(DisplayFixtures.empty().isEmpty)
        XCTAssertEqual(DisplayFixtures.oneDisplay().count, 1)
        XCTAssertEqual(DisplayFixtures.twoDisplays().count, 2)
        XCTAssertLessThan(DisplayFixtures.narrowDisplay()[0].visibleFrame.width, 500)
        XCTAssertEqual(DisplayFixtures.invalidDisplayIdentifier()[0].uuid.rawValue, "")
        XCTAssertEqual(DisplayFixtures.disconnectedAndReconnected().reconnectUUID.rawValue, "display-a")
        }
    }

- [ ] **Step 2: Run the fixture test and verify RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      swift test --filter 'DeterministicFixtureTests.testFixtureCoversEmptyOneTwoNarrowInvalidAndReconnectStates'

Expected: compilation fails because DeterministicFixtureTests and the fixture source files do not exist.

- [ ] **Step 3: Implement fixture values with no production imports beyond public protocols.**

Use descriptors with frames (0,0,1920,1080) and visible frames (0,24,1920,1056), a second display at x=1920, a narrow display width of 420, and the empty-UUID invalid fixture. The reconnect fixture changes frame and scale while preserving UUID "display-a"; it must not migrate marks or rewrite UUIDs.

- [ ] **Step 4: Run fixture and existing tests.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      swift test --filter 'DeterministicFixtureTests|SmokeRunnerTests'

Expected: PASS. Hand off the fixture names and descriptor values; do not add a second test-only gesture engine.

## Task 3: Build the real-path deterministic interaction harness (A-harness, scheduled after B-render-integration/C/D acceptance)

**Files:**

- Create: Sources/PointerAppKit/Diagnostics/DeterministicInteractionHarness.swift
- Create: Tests/PointerAppKitTests/Harness/CanvasIntegrationHarnessTests.swift
- Create: Tests/PointerAppKitTests/Harness/DeterministicInteractionFixture.swift

**Prerequisite handoff:** The coordinator records accepted B core plus B-render-integration CanvasView contracts, C PalettePresenting/CommandRouter/activeShortcutID/shortcutError/metadata contracts, and D's public RenderPlan/HandleInventory contracts before dispatching this task. Until that handoff exists, do not write or run this task's production harness.

**Interfaces:**

- Consumes ScreenProviding, DisplayCoordinator, CommandRouter, PalettePresenting, MenuBarPresenting, HotKeyController, ControlMetadataProviding, InteractionClock, CanvasView.beginGesture(at:), continueGesture(to:), endGesture(), cancelGesture(), B core plus B-render-integration contracts, C's activeShortcutID/shortcutError contract, and D's public RenderPlan/HandleInventory.
- Produces DeterministicInteractionHarness and the two public snapshot types in this plan.
- The Harness/DeterministicInteractionFixture constructs the exact real DisplayCoordinator, CommandRouter, PalettePanel, MenuBarController, HotKeyController, ControlMetadataInventory, and OverlayPanel factory and passes them to the production harness. It exposes interactionClock: HarnessClockAdapter. Its route(_:) calls CommandRouter.route(_:); gesture methods call the real CanvasView; synchronizeDisplays() calls DisplayCoordinator.synchronize(); metadata() delegates to the injected read-only ControlMetadataProviding.
- The Harness/DeterministicInteractionFixture defines a local @MainActor HarnessClockAdapter: InteractionClock that wraps the phase-neutral Support DeterministicClock and forwards nowNanoseconds; Support types remain protocol-independent.
- Unsupported UUIDs throw DeterministicInteractionError.invalidDisplay(UUID) rather than selecting another display or mutating the session.

- [ ] **Step 1: Write the failing real-path tests.**

    @MainActor
    final class CanvasIntegrationHarnessTests: XCTestCase {

    @MainActor
    func testHarnessDrivesRealCanvasAndCommandRoutes() throws {
        let fixture = DeterministicInteractionFixture.oneDisplay()
        let harness = DeterministicInteractionHarness(screenProvider: fixture.screenProvider,
                                                       displayCoordinator: fixture.displayCoordinator,
                                                       commandRouter: fixture.commandRouter,
                                                       palette: fixture.palette,
                                                       menuBar: fixture.menuBar,
                                                       shortcutController: fixture.shortcutController,
                                                       metadataProvider: fixture.metadataProvider,
                                                       clock: fixture.interactionClock)
        _ = harness.synchronizeDisplays()
        let display = try XCTUnwrap(harness.snapshot().connectedDisplays.first)

        harness.route(.setMode(.annotation))
        try harness.beginGesture(at: NSPoint(x: 100, y: 100), on: display)
        try harness.continueGesture(to: NSPoint(x: 300, y: 240), on: display)
        try harness.endGesture(on: display)

        let snapshot = harness.snapshot()
        XCTAssertEqual(snapshot.mode, .annotation)
        XCTAssertEqual(snapshot.marksByDisplay[display]?.count, 1)
        XCTAssertTrue(snapshot.undoAvailable)
        XCTAssertNil(snapshot.activeDraftMarkID)
    }

    @MainActor
    func testHarnessSeparatesCancelBoundaryFromContinuationSamplesAndStaleMouseUp() throws {
        let fixture = DeterministicInteractionFixture.oneDisplay()
        let harness = DeterministicInteractionHarness(screenProvider: fixture.screenProvider,
                                                       displayCoordinator: fixture.displayCoordinator,
                                                       commandRouter: fixture.commandRouter,
                                                       palette: fixture.palette,
                                                       menuBar: fixture.menuBar,
                                                       shortcutController: fixture.shortcutController,
                                                       metadataProvider: fixture.metadataProvider,
                                                       clock: fixture.interactionClock)
        _ = harness.synchronizeDisplays()
        let display = try XCTUnwrap(harness.snapshot().connectedDisplays.first)
        harness.route(.setMode(.annotation))
        try harness.beginGesture(at: NSPoint(x: 80, y: 80), on: display)
        try harness.continueGesture(to: NSPoint(x: 160, y: 160), on: display)
        try harness.cancelGesture(on: display)
        try harness.endGesture(on: display)
        let snapshot = harness.snapshot()
        XCTAssertTrue(snapshot.marksByDisplay[display, default: []].isEmpty)
        XCTAssertFalse(snapshot.undoAvailable)
        XCTAssertNil(snapshot.activeDraftMarkID)
    }

    @MainActor
    func testStandbySnapshotRetainsMarksButRemovesSelectionChromeAndDelete() throws {
        let fixture = DeterministicInteractionFixture.oneDisplay()
        let harness = DeterministicInteractionHarness(screenProvider: fixture.screenProvider,
                                                       displayCoordinator: fixture.displayCoordinator,
                                                       commandRouter: fixture.commandRouter,
                                                       palette: fixture.palette,
                                                       menuBar: fixture.menuBar,
                                                       shortcutController: fixture.shortcutController,
                                                       metadataProvider: fixture.metadataProvider,
                                                       clock: fixture.interactionClock)
        _ = harness.synchronizeDisplays()
        let display = try XCTUnwrap(harness.snapshot().connectedDisplays.first)
        harness.route(.setMode(.annotation))
        try harness.beginGesture(at: NSPoint(x: 100, y: 100), on: display)
        try harness.continueGesture(to: NSPoint(x: 300, y: 240), on: display)
        try harness.endGesture(on: display)
        harness.route(.setTool(.select))
        try harness.beginGesture(at: NSPoint(x: 200, y: 170), on: display)
        try harness.endGesture(on: display)
        XCTAssertNotNil(harness.snapshot().selection)

        harness.route(.setMode(.standby))
        let standby = harness.snapshot()
        XCTAssertEqual(standby.marksByDisplay[display]?.count, 1)
        XCTAssertNil(standby.activeDraftMarkID)
        XCTAssertNil(standby.selection)
        XCTAssertTrue(standby.handleInventory.resize.handles.isEmpty)
        XCTAssertFalse(standby.handleInventory.contextualDeleteVisible)
    }
    }

- [ ] **Step 2: Run the focused tests and verify RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      swift test --filter CanvasIntegrationHarnessTests

Expected: compilation fails because the prerequisite B/C/D contracts and production harness are absent. Do not add a fake CanvasView or test-only router/palette/menu to make the test compile.

- [ ] **Step 3: Implement the harness around the production path.**

Store the injected exact production objects; do not construct an alternate router, palette, menu, or gesture engine. After synchronization, downcast only the known production overlay to obtain its canvasView; reject any other display UUID. Route commands through CommandRouter, not PointerSession.apply. After every operation compute the snapshot from coordinator.session, the real canvas preview, D's real renderer plan/handle inventory, the router's shortcut fields, the injected palette/menu metadata, and the coordinator's connected UUIDs. Keep the harness @MainActor; never call NSEvent posting, CGEvent, global monitors, event taps, Accessibility APIs, or screen capture.

For undo availability, consume the accepted read-only session query exposed by the coordinating B worker. If B names it canUndo(on:) rather than undoAvailable(on:), update this plan's call site and handoff signature consistently; do not reflect private storage or infer availability from mark counts.

- [ ] **Step 4: Run focused tests and verify GREEN.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      swift test --filter 'CanvasIntegrationHarnessTests|DeterministicFixtureTests'

Expected: all harness tests pass, with one meaningful boundary event for begin/commit/cancel and zero committed marks after cancel plus stale endGesture.

## Task 4: Expose control metadata and deterministic display edge cases

**Files:**

- Modify: Sources/PointerAppKit/Diagnostics/DeterministicInteractionHarness.swift
- Modify: Tests/PointerAppKitTests/Harness/CanvasIntegrationHarnessTests.swift

**Interfaces:**

- metadata() delegates to the injected C-owned ControlMetadataProviding and returns one entry per menu and palette control; it never invents a control absent from the production view hierarchy.
- Metadata reads the production control's identifier, accessibility label/help, displayed value, enabled state, and focus/keyboard route. It returns entries in production keyboard order.
- Empty displays, invalid identifiers, narrow palette, overlapping marks, and disconnect/reconnect are explicit test states.

- [ ] **Step 1: Add failing metadata and edge-case tests.**

    @MainActor
    func testControlMetadataHasUniqueIdentifiersNamesHelpAndKeyboardReachability() {
        let fixture = DeterministicInteractionFixture.oneDisplay()
        let harness = fixture.makeHarness()
        _ = harness.synchronizeDisplays()
        let metadata = harness.metadata()
        XCTAssertGreaterThan(metadata.count, 0)
        XCTAssertEqual(Set(metadata.map(\.identifier)).count, metadata.count)
        XCTAssertTrue(metadata.allSatisfy { !$0.accessibleName.isEmpty && $0.isKeyboardReachable })
    }

    @MainActor
    func testNoDisplayAndInvalidDisplayFailClosedWithDiagnostic() {
        let empty = DeterministicInteractionFixture.empty().makeHarness()
        let sync = empty.synchronizeDisplays()
        XCTAssertFalse(sync.hasConnectedDisplays)
        XCTAssertThrowsError(try empty.beginGesture(at: .zero, on: DisplayUUID(rawValue: "missing"))) { error in
            XCTAssertEqual(error as? DeterministicInteractionError,
                           .invalidDisplay(DisplayUUID(rawValue: "missing")))
        }
    }

    @MainActor
    func testReconnectKeepsMarksOnSameUUIDAndDoesNotMigrateThem() throws {
        let fixture = DeterministicInteractionFixture.disconnectedAndReconnected()
        let harness = DeterministicInteractionHarness(screenProvider: fixture.screenProvider,
                                                       displayCoordinator: fixture.displayCoordinator,
                                                       commandRouter: fixture.commandRouter,
                                                       palette: fixture.palette,
                                                       menuBar: fixture.menuBar,
                                                       shortcutController: fixture.shortcutController,
                                                       metadataProvider: fixture.metadataProvider,
                                                       clock: fixture.interactionClock)
        _ = harness.synchronizeDisplays()
        harness.route(.setMode(.annotation))
        try harness.beginGesture(at: NSPoint(x: 100, y: 100), on: fixture.reconnectUUID)
        try harness.continueGesture(to: NSPoint(x: 240, y: 180), on: fixture.reconnectUUID)
        try harness.endGesture(on: fixture.reconnectUUID)
        fixture.screenProvider.displays = []
        _ = harness.synchronizeDisplays()
        fixture.screenProvider.displays = [fixture.reconnectedDescriptor]
        _ = harness.synchronizeDisplays()
        let snapshot = harness.snapshot()
        XCTAssertEqual(snapshot.marksByDisplay[fixture.reconnectUUID]?.count, 1)
        XCTAssertEqual(snapshot.marksByDisplay[fixture.otherUUID, default: []].count, 0)
    }

- [ ] **Step 2: Run the focused tests and verify RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      swift test --filter 'CanvasIntegrationHarnessTests.testControlMetadataHasUniqueIdentifiersNamesHelpAndKeyboardReachability|CanvasIntegrationHarnessTests.testNoDisplayAndInvalidDisplayFailClosedWithDiagnostic|CanvasIntegrationHarnessTests.testReconnectKeepsMarksOnSameUUIDAndDoesNotMigrateThem'

Expected: failures identify missing metadata enumeration, error type, or reconnect oracle; do not weaken assertions to accept missing accessibility metadata.

- [ ] **Step 3: Implement metadata and edge-state reporting.**

Enumerate PaletteViewController.controls and the menu status item/menu hierarchy through the production object references. For sliders and popups, encode the displayed value/title; for buttons, encode selected/enabled state. Set isKeyboardReachable only when the control is an enabled focusable AppKit control with a stable identifier and local command route. Return a useful error for empty/invalid displays. Use display UUID keys for every mark snapshot and preserve disconnected canvases.

- [ ] **Step 4: Run all A tests and verify GREEN.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'SmokeRunnerTests|DeterministicFixtureTests|CanvasIntegrationHarnessTests'

Expected: PASS. Hand off the metadata inventory and fixture matrix as deterministic evidence; explicitly label it as not physical VoiceOver or live hit-target proof.

## Task 5: Worker/reviewer/adversarial reconciliation gate

**Files:**

- Modify only files listed in Tasks 1–4 after a finding is accepted.
- Evidence handoff: coordinator-owned review record; no commit or publication from this worker.

Task 5 has two checkpoints: first reconcile Tasks 1–2 independently before B starts; then, after B-core, the D-gated B-render-integration phase, C, and D accepted-interface handoffs, dispatch the same A worker for Tasks 3–4 and reconcile the harness. The independent checkpoint must not claim harness completion.

- [ ] **Step 1: Run the scope and document checks.**

    git status --short
    git diff --check
    git diff --name-only -- Sources/PointerAppKit/Diagnostics/SmokeRunner.swift Tests/PointerAppKitTests/Support Tests/PointerAppKitTests/Harness Tests/PointerAppKitTests/SmokeRunnerTests.swift

Expected: only A-owned paths are changed; the design document may remain an existing untracked input, and no B–F source/test path appears in the worker diff.

- [ ] **Step 2: Run A's full verification.**

Independent checkpoint:

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'SmokeRunnerTests|DeterministicFixtureTests'

After B/C/D handoffs and Tasks 3–4:

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'SmokeRunnerTests|DeterministicFixtureTests|CanvasIntegrationHarnessTests'

Expected: PASS with zero failures. Record the exact output and the JSON report bytes.

- [ ] **Step 3: Handoff to the configured Luna reviewer.**

Handoff must include changed paths, test commands/output, deterministic-only evidence labels, the real CanvasView/OverlayPanel construction proof, unsupported-host limitations, and any requested B interface. Reviewer returns REVISE with exact path/test findings or APPROVED only if the seam cannot bypass production validation or global input rules.

- [ ] **Step 4: After reviewer approval, run adversarial Codex review.**

The adversarial pass must re-read the objective and Workstream A acceptance criteria, inspect the diff read-only, run the focused tests, and challenge: fake versus real canvas construction, stale mouse-up, standby selection-handle inventory, invalid UUID fail-closed behavior, control metadata completeness, stable JSON, and evidence-class labeling.

- [ ] **Step 5: Reconcile findings with the worker and reviewer.**

For every finding, return to the smallest A-owned file, rerun the focused RED/GREEN checks, obtain reviewer re-approval, and rerun adversarial checks. Handoff status must state RECONCILED only when worker, reviewer, and adversarial findings agree; otherwise state the exact unresolved interface and stop before widening scope.

## Plan self-check

- Smoke JSON and independent screen/clock fixture coverage land in Tasks 1–2 before B. The scheduled post-B/C/D harness then covers real-path gestures, boundary/cancel separation, standby render-plan inventory, controls metadata, invalid/no-display fail-closed behavior, and stable UUID reconnect in Tasks 3–4.
- No task contains a commit instruction, source outside A's ownership, an alternate gesture engine, global input synthesis, or a physical-use claim.
- Public names are consistent: DeterministicInteractionHarness, DeterministicInteractionSnapshot, ControlMetadataProviding, ControlMetadata, HandleInventory, HarnessClockAdapter, DeterministicInteractionFixture, CanvasIntegrationHarnessTests, DisplaySyncResult, CommandRouter.activeShortcutID, and CommandRouter.shortcutError are used identically throughout.
- All verification commands use the documented DEVELOPER_DIR; the final evidence remains deterministic and is not presented as manual proof.
