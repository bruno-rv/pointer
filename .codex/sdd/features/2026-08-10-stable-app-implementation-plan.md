# Stable Pointer App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` to implement this plan task by task.
> Every production behavior follows red-green-refactor; record the failing and
> passing command in the task report.

**Goal:** Turn the design-only branch into a native, source-built Pointer app
whose code, interaction flow, bundle, tests, benchmark, and CI are ready for a
merge review.

**Architecture:** `PointerCore` owns AppKit-free normalized models, display-local
canvases, transactional gestures, commands, and bounded undo. `PointerAppKit`
owns rendering, windows, screens, palette, keyboard routing, menu-bar state, and
Carbon registration. The `Pointer` executable only chooses smoke, benchmark, or
interactive launch and delegates to `PointerAppKit`.

**Tech Stack:** Swift 5.10 package manifest, XCTest, AppKit, Carbon Event
Manager, native macOS shell tools, GitHub Actions.

## Global Constraints

- Support Apple silicon on macOS 14 or later with Xcode 15.4 or later.
- Require no Apple account, package manager, generator, dependency, secret, or
  machine-specific path.
- Keep `PointerCore` free of AppKit, CoreGraphics, and Carbon imports; normalized
  geometry uses `Double` value types.
- Keep every canvas keyed by a stable display UUID. Never use a transient
  `CGDirectDisplayID` as model identity.
- Start in click-through standby with Arrow selected and red, 4-point, fully
  opaque styling.
- Keep one palette and one overlay per connected physical display; disconnected
  display canvases remain in memory until process exit.
- Treat every gesture as a transaction: preview during drag, create at most one
  undo entry on a meaningful commit, and restore exact pre-gesture state on
  cancel.
- Publish inspector or palette state only at gesture boundaries; continuation
  samples update preview geometry and request redraw only.
- Use `RegisterEventHotKey` only. Do not use global event monitors, event taps,
  Accessibility operations, input synthesis, or screen-capture APIs.
- Keep all new production files outside `.scratch/`; prototypes remain evidence,
  not dependencies.
- Preserve the dirty `README.md` in the primary `main` worktree. Documentation
  changes happen only in `codex/stable-app` and must incorporate its useful
  content rather than modifying the primary checkout.

---

### Task 1: AppKit-free domain, display canvases, and bounded undo

**Files:**

- Create: `Package.swift`
- Create: `Sources/PointerCore/NormalizedGeometry.swift`
- Create: `Sources/PointerCore/DisplayIdentity.swift`
- Create: `Sources/PointerCore/Mark.swift`
- Create: `Sources/PointerCore/ToolState.swift`
- Create: `Sources/PointerCore/Canvas.swift`
- Create: `Sources/PointerCore/UndoHistory.swift`
- Create: `Sources/PointerCore/PointerSession.swift`
- Create: `Sources/PointerCore/SessionCommand.swift`
- Create: `Tests/PointerCoreTests/NormalizedGeometryTests.swift`
- Create: `Tests/PointerCoreTests/CanvasTests.swift`
- Create: `Tests/PointerCoreTests/PointerSessionTests.swift`

**Interfaces:**

- Produces `DisplayUUID`, `NormalizedPoint`, `NormalizedSize`,
  `NormalizedRect`, `RGBAColor`, `MarkStyle`, `MarkGeometry`, `Mark`,
  `PointerTool`, `PointerMode`, `ToolState`, `Canvas`, `UndoHistory`,
  `PointerSession`, and `SessionCommand`.
- `DisplayUUID` is `RawRepresentable`, `Hashable`, `Codable`, and `Sendable`.
- `PointerSession.canvas(for:)` returns a display-local value snapshot; session
  commands are the sole production mutation path.
- `UndoHistory` keeps the most recent 100 snapshots and exposes no mutable
  storage.

- [ ] **Step 1: Create the package and write failing domain tests**

  Use Swift tools 5.10, a macOS 14 floor, `PointerCore`, `PointerAppKit`, and
  `Pointer` targets plus matching XCTest targets. Tests must include literal,
  hand-derived expectations like:

  ```swift
  func testNormalizedRectDenormalizesAgainstNewDisplaySize() {
      let rect = NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
      XCTAssertEqual(rect.denormalized(width: 1600, height: 900),
                     DenormalizedRect(x: 400, y: 450, width: 800, height: 225))
  }

  func testReconnectUsesCanvasOwnedByStableDisplayUUID() {
      let id = DisplayUUID(rawValue: "external-uuid")
      var session = PointerSession()
      session.ensureCanvas(for: id)
      session.apply(.append(fixtureArrow, to: id))
      session.disconnect(id)
      session.ensureCanvas(for: id)
      XCTAssertEqual(session.canvas(for: id).marks.map(\.id), [fixtureArrow.id])
  }
  ```

- [ ] **Step 2: Run the focused tests and confirm RED**

  Run:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
    --filter 'NormalizedGeometryTests|CanvasTests|PointerSessionTests'
  ```

  Expected: compilation fails because the new domain types do not exist.

- [ ] **Step 3: Implement the minimum value model and session commands**

  Preserve these public shapes so later tasks have one stable seam:

  ```swift
  public struct DisplayUUID: RawRepresentable, Hashable, Codable, Sendable {
      public let rawValue: String
      public init(rawValue: String)
  }

  public enum MarkGeometry: Equatable, Sendable {
      case arrow(start: NormalizedPoint, end: NormalizedPoint)
      case rectangle(NormalizedRect)
      case ellipse(NormalizedRect)
      case freehand([NormalizedPoint])
      case emoji(text: String, rect: NormalizedRect)
      case spotlight(center: NormalizedPoint, radius: Double, dimness: Double)
  }

  public struct PointerSession: Equatable, Sendable {
      public private(set) var mode: PointerMode
      public private(set) var toolState: ToolState
      public mutating func apply(_ command: SessionCommand)
      public func canvas(for display: DisplayUUID) -> Canvas
  }
  ```

  Clamp normalized inputs and style opacity/dimness to `0...1`, require
  nonnegative stroke widths/radii, replace the existing spotlight atomically,
  and make clear-all restoration include every canvas and its prior undo stack.

- [ ] **Step 4: Run focused and full tests and confirm GREEN**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
  ```

  Expected: all Task 1 tests pass and `PointerCore` contains no forbidden import.

- [ ] **Step 5: Commit the reviewed task**

  ```sh
  git add Package.swift Sources/PointerCore Tests/PointerCoreTests
  git commit -m "feat: add Pointer core session model"
  ```

---

### Task 2: Transactional gesture, hit-testing, resize, and erase engine

**Files:**

- Create: `Sources/PointerCore/GestureTransaction.swift`
- Create: `Sources/PointerCore/HitTesting.swift`
- Create: `Sources/PointerCore/ResizeGeometry.swift`
- Create: `Tests/PointerCoreTests/GestureTransactionTests.swift`
- Create: `Tests/PointerCoreTests/HitTestingTests.swift`
- Create: `Tests/PointerCoreTests/ResizeGeometryTests.swift`
- Modify: `Sources/PointerCore/PointerSession.swift`
- Modify: `Sources/PointerCore/SessionCommand.swift`

**Interfaces:**

- Consumes all Task 1 value types.
- Produces `GestureTransaction`, `GestureUpdate`, `GestureCommit`,
  `GestureCancellation`, `ResizeHandle`, and `HitTestTarget`.
- `GestureUpdate` contains preview marks, selection, and a redraw flag but never
  emits an observable boundary publication.
- `PointerSession` exposes `beginGesture`, `advanceGesture`, `commitGesture`, and
  `cancelGesture`, plus `previewCanvas(for:)` for rendering.

- [ ] **Step 1: Write failing transactional and geometry tests**

  Name the break each test catches. At minimum cover:

  ```swift
  func testCancelledShapeRestoresCanvasWithoutUndoEntry()
  func testZeroLengthShapeCommitIsDiscardedWithoutUndoEntry()
  func testFreehandAdvanceAppendsToGestureLocalDraft()
  func testBoundaryObserverFiresAtBeginAndCommitNotAdvance()
  func testSparseEraserSamplesRemoveMarkCrossedBySweptSegment()
  func testEmojiClickUsesDefaultSquareAndDragUsesSquareExtent()
  func testFreehandCornerResizeUsesUniformScaleFromOppositeAnchor()
  func testEraserDragCreatesOneUndoSnapshot()
  func testModeChangeCancelsActiveGestureBeforeStandby()
  ```

  Swept erase must prove a mark between `(0.1, 0.5)` and `(0.9, 0.5)` is removed
  even when neither endpoint hits it directly.

- [ ] **Step 2: Run and confirm RED for missing gesture APIs**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
    --filter 'GestureTransactionTests|HitTestingTests|ResizeGeometryTests'
  ```

- [ ] **Step 3: Implement a gesture-local draft and exact cancellation**

  Keep this contract:

  ```swift
  public mutating func beginGesture(
      tool: PointerTool,
      at point: NormalizedPoint,
      on display: DisplayUUID
  ) -> GestureUpdate

  public mutating func advanceGesture(to point: NormalizedPoint) -> GestureUpdate
  public mutating func commitGesture() -> GestureCommit
  public mutating func cancelGesture() -> GestureCancellation
  ```

  Store the base canvas once and mutate a gesture-local preview. Freehand points
  append to one contiguous draft buffer and become an immutable mark only at
  commit. Eraser hit-testing uses the segment from the previous sample to the
  new sample. Selection move/resize, arrow endpoints, eight bounds handles, four
  aspect-preserving freehand/emoji handles, and spotlight center/radius handles
  all resolve in Core.

- [ ] **Step 4: Run focused tests, then the entire suite**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
  ```

- [ ] **Step 5: Commit the reviewed task**

  ```sh
  git add Sources/PointerCore Tests/PointerCoreTests
  git commit -m "feat: add transactional annotation gestures"
  ```

---

### Task 3: AppKit rendering and stable multi-display overlays

**Files:**

- Create: `Sources/PointerAppKit/ScreenProviding.swift`
- Create: `Sources/PointerAppKit/NSScreenProvider.swift`
- Create: `Sources/PointerAppKit/DisplayUUIDProvider.swift`
- Create: `Sources/PointerAppKit/OverlayPresenting.swift`
- Create: `Sources/PointerAppKit/OverlayPanel.swift`
- Create: `Sources/PointerAppKit/DisplayCoordinator.swift`
- Create: `Sources/PointerAppKit/CanvasView.swift`
- Create: `Sources/PointerAppKit/MarkRenderer.swift`
- Create: `Tests/PointerAppKitTests/DisplayCoordinatorTests.swift`
- Create: `Tests/PointerAppKitTests/CanvasViewTests.swift`
- Create: `Tests/PointerAppKitTests/MarkRendererTests.swift`

**Interfaces:**

- `ScreenProviding.currentDisplays()` returns `[DisplayDescriptor]` with UUID,
  frame, visible frame, and scale factor.
- `DisplayCoordinator` owns one `OverlayPresenting` per connected UUID and never
  removes the corresponding session canvas.
- `CanvasView` maps points into normalized display-local coordinates and drives
  Task 2. It invalidates display for continuation samples but calls its boundary
  callback only for begin, commit, or cancel.
- `MarkRenderer` draws committed marks plus the active draft without owning or
  mutating model state.

- [ ] **Step 1: Write failing coordinator and view tests**

  ```swift
  func testReconnectWithSameUUIDReusesCanvasAcrossChangedFrame()
  func testRemovingScreenClosesOnlyItsOverlayAndRetainsItsCanvas()
  func testCanvasContinuationRequestsRedrawWithoutPublishingBoundary()
  func testStandbyOverlayIgnoresMouseEvents()
  func testSpotlightDimsOutsideFocusCircle()
  ```

  Coordinator tests use fake descriptors and overlay presenters. Canvas tests
  attach the real view to a non-visible `NSWindow` only where AppKit requires it.

- [ ] **Step 2: Run AppKit tests and confirm RED**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
    --filter PointerAppKitTests
  ```

- [ ] **Step 3: Implement UUID lookup, panels, mapping, and renderer**

  ```swift
  public struct DisplayDescriptor: Equatable, Sendable {
      public let uuid: DisplayUUID
      public let frame: DisplayFrame
      public let visibleFrame: DisplayFrame
      public let scaleFactor: Double
  }

  @MainActor public protocol ScreenProviding {
      func currentDisplays() -> [DisplayDescriptor]
      func pointerDisplay() -> DisplayUUID?
  }
  ```

  Production UUIDs come from `CGDisplayCreateUUIDFromDisplayID`. Unsupported
  descriptors are reported and skipped rather than keyed by transient display
  ID. `OverlayPanel` is transparent, borderless, non-activating, screen-saver
  level, joins every Space/full-screen app, and toggles `ignoresMouseEvents` from
  session mode.

- [ ] **Step 4: Run all tests and a Release build**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release
  ```

- [ ] **Step 5: Commit the reviewed task**

  ```sh
  git add Sources/PointerAppKit Tests/PointerAppKitTests
  git commit -m "feat: render display-local overlays"
  ```

---

### Task 4: Rollback-safe Carbon shortcut transaction

**Files:**

- Create: `Sources/PointerAppKit/Shortcuts/ShortcutPreset.swift`
- Create: `Sources/PointerAppKit/Shortcuts/HotKeyRegistering.swift`
- Create: `Sources/PointerAppKit/Shortcuts/CarbonHotKeyRegistrar.swift`
- Create: `Sources/PointerAppKit/Shortcuts/ShortcutStoring.swift`
- Create: `Sources/PointerAppKit/Shortcuts/UserDefaultsShortcutStore.swift`
- Create: `Sources/PointerAppKit/Shortcuts/ShortcutScheduling.swift`
- Create: `Sources/PointerAppKit/Shortcuts/HotKeyController.swift`
- Create: `Tests/PointerAppKitTests/HotKeyControllerTests.swift`

**Interfaces:**

- Produces two presets: Control-Option-Command-P (default) and
  Control-Option-Command-O.
- `HotKeyRegistering` returns opaque `HotKeyToken` values and delivers the token
  with each event, allowing the old registration to remain active while a new
  candidate is tested.
- Candidate persistence occurs only after its event arrives within five seconds.
- On failure or timeout, the candidate unregisters and the prior token and stored
  preference remain unchanged.

- [ ] **Step 1: Write failing state-machine tests with deterministic fakes**

  ```swift
  func testCandidateRegistrationKeepsPreviousTokenUntilDelivery()
  func testDeliveryPersistsCandidateThenUnregistersPreviousToken()
  func testTimeoutUnregistersCandidateAndLeavesPreviousPreferenceUntouched()
  func testLateCandidateEventAfterTimeoutCannotReplacePreviousShortcut()
  func testStartupFallsBackFromStoredToDefaultThenDisabled()
  ```

  Assertions target controller state and real fake-store contents, not calls on
  a mock object.

- [ ] **Step 2: Run and confirm RED**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
    --filter HotKeyControllerTests
  ```

- [ ] **Step 3: Implement controller first, Carbon adapter second**

  ```swift
  @MainActor public protocol HotKeyRegistering: AnyObject {
      var onEvent: ((HotKeyToken) -> Void)? { get set }
      func register(_ preset: ShortcutPreset) throws -> HotKeyToken
      func unregister(_ token: HotKeyToken)
  }
  ```

  Install one Carbon application event handler. Give active and provisional
  registrations distinct `EventHotKeyID` values, forward events by token, and
  remove every Carbon reference on termination.

- [ ] **Step 4: Run focused tests, full tests, and Release build**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release
  ```

- [ ] **Step 5: Commit the reviewed task**

  ```sh
  git add Sources/PointerAppKit/Shortcuts Tests/PointerAppKitTests/HotKeyControllerTests.swift
  git commit -m "feat: add verified global shortcut flow"
  ```

---

### Task 5: Lifecycle, command router, menu bar, and accessible adaptive palette

**Files:**

- Create: `Sources/PointerAppKit/CommandRouter.swift`
- Create: `Sources/PointerAppKit/MenuBarController.swift`
- Create: `Sources/PointerAppKit/Palette/PalettePanel.swift`
- Create: `Sources/PointerAppKit/Palette/PaletteLayout.swift`
- Create: `Sources/PointerAppKit/Palette/PaletteViewController.swift`
- Create: `Sources/PointerAppKit/PointerApplicationController.swift`
- Create: `Sources/PointerAppKit/PointerApplication.swift`
- Create: `Sources/Pointer/main.swift`
- Create: `Tests/PointerAppKitTests/CommandRouterTests.swift`
- Create: `Tests/PointerAppKitTests/PaletteLayoutTests.swift`
- Create: `Tests/PointerAppKitTests/PointerApplicationControllerTests.swift`

**Interfaces:**

- `CommandRouter` is the only keyboard/menu/palette mutation route for Escape,
  Delete/Backspace, Undo, Clear, Clear All, tool selection, style, and mode.
- `PaletteLayout` returns a deterministic two-row or compact-overflow plan from
  available visible width; every tool remains reachable.
- Explicit show moves the palette to the pointer display and clamps it. Normal
  session changes never overwrite a manual drag position.

- [ ] **Step 1: Write failing integration and layout tests**

  ```swift
  func testEscapeCancelsDraftThenEntersStandbyFromPaletteFocus()
  func testDeleteRoutesToSelectedMarkOnPointerDisplay()
  func testNarrowLayoutKeepsAllEightToolsReachableThroughOverflow()
  func testExplicitShowMovesAndClampsPaletteToPointerDisplay()
  func testNormalRefreshPreservesManualPaletteDrag()
  func testEveryPaletteControlHasLabelHelpIdentifierAndEnabledState()
  ```

- [ ] **Step 2: Run and confirm RED**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
    --filter 'CommandRouterTests|PaletteLayoutTests|PointerApplicationControllerTests'
  ```

- [ ] **Step 3: Implement the single application flow**

  Use a local, Pointer-process key event route (never a global monitor) so
  overlay and palette focus share commands. The native menu exposes Show
  Palette, Enter/Exit Annotation, two shortcut presets, Clear All Displays,
  Undo Clear All when available, and Quit. All icon-only controls have native
  accessibility labels, help, stable identifiers, keyboard routes, and visible
  enabled/focus states. Respect Reduce Transparency and Increase Contrast.

- [ ] **Step 4: Run all tests and launch the debug executable once**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
  ```

  Launch validation is interactive and occurs after Task 6 creates the bundle;
  this step only proves compilation and test integration.

- [ ] **Step 5: Commit the reviewed task**

  ```sh
  git add Sources/PointerAppKit Sources/Pointer Tests/PointerAppKitTests
  git commit -m "feat: wire Pointer application controls"
  ```

---

### Task 6: One-command bundle, deterministic smoke mode, and repository verifier

**Files:**

- Create: `Bundle/Info.plist`
- Create: `Sources/PointerAppKit/Diagnostics/SmokeRunner.swift`
- Create: `Tests/PointerAppKitTests/SmokeRunnerTests.swift`
- Create: `Tests/BuildScripts/test-build-contract.sh`
- Create: `scripts/build-app.sh`
- Create: `scripts/run-app.sh`
- Create: `scripts/verify.sh`
- Modify: `.gitignore`

**Interfaces:**

- `Pointer --smoke --format json` creates no windows and emits exactly one
  palette plan, one overlay plan per supplied display, standby mode, and a valid
  default shortcut preset.
- `scripts/build-app.sh` idempotently creates `build/Pointer.app`, validates the
  plist and arm64 executable, ad-hoc signs, and validates the signature.
- `scripts/run-app.sh` builds then opens that exact bundle.
- `scripts/verify.sh` is the single local and CI gate.

- [ ] **Step 1: Write failing smoke and shell-contract tests**

  ```swift
  func testSmokeReportPlansOnePaletteAndOverlayPerDisplay() {
      let report = SmokeRunner.report(displays: [.builtIn, .external])
      XCTAssertEqual(report.paletteCount, 1)
      XCTAssertEqual(report.overlayCount, 2)
      XCTAssertEqual(report.mode, .standby)
      XCTAssertEqual(report.shortcutID, "control-option-command-p")
  }
  ```

  The shell test runs the build twice, validates the same bundle path, executes
  smoke JSON, and fails first because scripts and bundle metadata do not exist.

- [ ] **Step 2: Run and confirm RED**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
    --filter SmokeRunnerTests
  /bin/bash Tests/BuildScripts/test-build-contract.sh
  ```

- [ ] **Step 3: Implement portable scripts and metadata**

  `build-app.sh` validates Darwin, arm64, active/full Xcode >= 15.4, `swift`,
  `plutil`, `codesign`, `lipo`, and `open`; uses `swift build --show-bin-path -c
  release`; replaces only repository-local `build/Pointer.app`; copies tracked
  metadata; signs with `codesign --force --sign -`; and validates every step.
  `run-app.sh` calls the builder then `/usr/bin/open` on the bundle. No script
  embeds `/Users/...` or assumes shell profile state.

- [ ] **Step 4: Run smoke, script contract, and full verifier**

  ```sh
  /bin/bash Tests/BuildScripts/test-build-contract.sh
  ./scripts/verify.sh
  ```

- [ ] **Step 5: Commit the reviewed task**

  ```sh
  git add Bundle Sources/PointerAppKit/Diagnostics Tests/BuildScripts \
    Tests/PointerAppKitTests/SmokeRunnerTests.swift scripts .gitignore
  git commit -m "build: add reproducible Pointer app bundle"
  ```

---

### Task 7: CI, production benchmark, documentation, and release evidence

**Files:**

- Create: `.github/workflows/verify.yml`
- Create: `Sources/PointerAppKit/Diagnostics/GestureBenchmark.swift`
- Create: `Tests/PointerAppKitTests/GestureBenchmarkTests.swift`
- Create: `scripts/benchmark-gestures.sh`
- Create: `.codex/sdd/reports/stable-source-build/validation.md`
- Modify: `Sources/Pointer/main.swift`
- Modify: `README.md`
- Modify: `scripts/verify.sh`

**Interfaces:**

- `Pointer --benchmark-gestures --format json` exercises Task 2 production APIs
  in Release with 12 existing marks, 240 continuation samples, literal checksum
  gates, and exactly two boundary publications.
- JSON includes trial count, median, p95, MAD, publication counts, and model
  checksum. Rendering/compositing claims are explicitly excluded unless timed.
- GitHub Actions runs `scripts/verify.sh` on `macos-15` arm64 and temporary
  `macos-14` arm64 while that public image remains available, asserting
  `uname -m` is `arm64`.

- [ ] **Step 1: Write the failing production benchmark test**

  ```swift
  func testGestureBenchmarkUsesProductionPathAndBoundaryPublication() {
      let result = GestureBenchmark.run(trials: 1, samples: 240)
      XCTAssertEqual(result.fixtureMarkCount, 12)
      XCTAssertEqual(result.samplesPerGesture, 240)
      XCTAssertEqual(result.publicationsPerGesture, [2])
      XCTAssertTrue(result.checksumIsStable)
  }
  ```

- [ ] **Step 2: Run and confirm RED**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
    --filter GestureBenchmarkTests
  ```

- [ ] **Step 3: Implement benchmark, CI, README, and evidence template**

  README quick start is exactly `./scripts/run-app.sh`; document tools, mode
  toggle, Escape, menu fallback, verification, benchmark, boundaries, and the
  difference between deployment target, CI runners, and observed physical host.
  Preserve useful domain/prototype evidence from the primary checkout's README
  while replacing the obsolete “no installable app” claim.

  The validation report records date, commit, macOS, Xcode, architecture,
  displays, commands, results, and evidence for automated, clean-clone, and
  physical-host checks. Unknown physical cases remain explicit unchecked rows,
  never implied passes.

- [ ] **Step 4: Run current verification and measured Release benchmark**

  ```sh
  ./scripts/verify.sh
  ./scripts/benchmark-gestures.sh
  git diff --check
  ```

  Run at least five warmups and 30 trials. Report production numbers as a
  baseline. Do not compare them numerically to the disposable prototype as if
  they measured the same system.

- [ ] **Step 5: Perform interactive and clean-clone gates**

  Launch `build/Pointer.app`; inspect the palette and overlays; exercise standby,
  annotation, every tool, selection, resize, delete, swept erase, undo, clear,
  spotlight, palette relocation, and shortcut fallback. Test connected displays,
  Spaces/full-screen, reconnect, alternate shortcut/relaunch/conflict, and denied
  privacy permissions where the host makes them observable. Record exact gaps.

  Clone the candidate branch into a fresh temporary directory and run the README
  commands there. Do not push or create a PR without separate publication
  authorization.

- [ ] **Step 6: Commit the reviewed task**

  ```sh
  git add .github README.md Sources/Pointer Sources/PointerAppKit/Diagnostics \
    Tests/PointerAppKitTests/GestureBenchmarkTests.swift scripts \
    .codex/sdd/reports/stable-source-build
  git commit -m "ci: verify the source-built Pointer app"
  ```

---

## Plan self-review

- Spec coverage: all production modules, tools, flow, shortcut, bundle,
  verification, CI, and release-evidence requirements map to Tasks 1–7.
- Scope: saved canvases, screenshots/export, text, rotation, Intel, Developer ID
  signing, notarization, DMG/installer, updates, downloadable releases, and
  DRM/secure-UI guarantees remain out of scope.
- Performance: only the proven boundary-publication policy and gesture-local
  draft are built in. Renderer/index caches require a measured production
  bottleneck and are not speculative work in this plan.
- Type consistency: Task 2 builds on Task 1 value types; Task 3 consumes Task 2;
  Task 5 consumes Tasks 1–4; Tasks 6–7 operate on the integrated executable.
- Merge safety: implementation stays on `codex/stable-app`; the primary worktree's
  dirty README is neither staged nor rewritten.
