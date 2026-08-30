# Pointer six-month quality campaign design

Date: August 23, 2026

Status: Approved for implementation

## Outcome

Pointer should feel like a small, deliberate native product: fast to
understand, hard to misuse, calm in standby, dependable during a presentation,
and accessible without sacrificing the compactness of the tool palette. The
campaign is complete only when a presenter can use Pointer for a long session,
across the supported display and Space cases, without encountering a
meaningful confusing interaction, broken state, missing affordance,
accessibility failure, performance annoyance, or unhandled edge case that the
team could reasonably have found.

The campaign improves the current annotation product. It does not broaden the
product into a document or distribution platform.

## Product boundary

The production architecture remains:

- `PointerCore` owns AppKit-free value models, normalized display-local
  geometry, gesture transactions, hit testing, tool state, selection, and undo.
- `PointerAppKit` owns the native application lifecycle, menu bar, palette,
  display coordination, transparent overlay panels, rendering, local keyboard
  routing, and Carbon shortcut registration.
- `PointerComposition` is an importable library containing the sole
  dependency-injected composition factory; it depends on `PointerCore` and
  `PointerAppKit` and is usable by composition tests without importing the
  executable.
- `Pointer` is the minimal launcher and CLI dispatcher. Its target depends
  directly on `PointerComposition` and `PointerAppKit`: it parses
  `--smoke`/`--format json` and `--benchmark-gestures`/`--format json` through
  the existing `PointerAppKit` diagnostics without constructing an interactive
  app, and only the no-flag path calls the `PointerComposition` factory. It
  owns no alternate interactive construction.
- There is one overlay and one in-memory display canvas per connected physical
  display. Canvas identity is a stable display UUID, never a transient display
  ID. `.scratch/` prototypes remain evidence and are not production
  dependencies.

In scope:

- Making annotation, standby, selection, resize, delete, erase, undo, clear,
  spotlight, emoji, palette, menu-bar, shortcut, display, and first-use flows
  coherent and resilient.
- Native iconography, a distinctive app icon, and one compact visual
  first-use guide that teaches the tools without becoming permanent chrome.
- Accessibility semantics, keyboard operation, focus behavior, visual
  contrast, Reduce Transparency, and Increase Contrast adaptation.
- Production-mirroring interaction, render/compositor, memory, and long-session
  measurements where they expose real bottlenecks.
- Deterministic seams that exercise the same command and model routes used by
  the app, plus direct/manual use of the built app for claims about physical
  interaction.

Explicitly out of scope:

- Saved canvases or restoration after process exit.
- Screenshots, export, text annotation, mark rotation, or a new annotation
  type.
- Intel support, Developer ID signing, notarization, a disk image, installer,
  automatic updates, or a downloadable public release.
- New network services, analytics, accounts, third-party dependencies, or
  additional privacy permissions.
- Guarantees over DRM-protected video, secure system UI, the lock screen, or
  future WindowServer policy.

Any proposed work outside this boundary is rejected or separately specified;
it is not smuggled into a polish task.

## Baseline and evidence model

The authoritative implementation checkout is
`/Users/bruno/Dev/pointer/.worktrees/stable-app`, branch `codex/stable-app`.
The primary `/Users/bruno/Dev/pointer` checkout has unrelated user-owned dirty
state, including its README and generated `graphify-out/`; the campaign must
not modify, stage, reset, or clean that state. Campaign documentation and
implementation changes belong in the stable-app worktree only.

The current baseline at design time is:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/verify.sh`
  passes 64 Swift tests with zero failures, builds the Release bundle, checks
  its plist, ad-hoc signature, arm64 executable, and smoke output, and ends
  with `verification passed`.
- The Release production gesture benchmark uses 12 fixture marks, 240
  continuation samples, five warmups, and 30 measured trials. The prior audit
  recorded approximately 0.225 ms median and 0.275 ms p95; a fresh run on
  August 23 emitted 0.123 ms median and 0.248 ms p95. These numbers measure
  the model gesture path only. They do not measure AppKit event dispatch,
  rendering, compositing, launch, or multi-display behavior. The variance is
  a reason to use repeated measurements, not to claim an optimization from a
  single run.
- The built app launches with a visible standby palette on the observed host.
  The prior physical run exposed one online external display only, so it does
  not prove multi-display, full-screen, reconnect, shortcut-conflict, or
  denied-permission behavior.
- The live desktop automation harness can launch and capture the app but cannot
  reliably operate the accessibility-hidden menu-bar and non-activating
  overlay/palette surfaces. A screenshot or successful process launch is
  therefore not proof of a click, drag, keyboard, VoiceOver, or display
  interaction. This is a testability gap to fix and to supplement with direct
  manual evidence, not a reason to replace the product interaction path with a
  test-only implementation.

Two evidence classes are required:

| Evidence class | Can establish | Cannot establish |
| --- | --- | --- |
| Deterministic | Model invariants, command routing, gesture cancellation, stable display identity, layout plans, accessibility metadata inventories, benchmark checksums, bundle contracts, and repeatable state transitions | That a person could physically find a control, drag a mark, use VoiceOver against a live window, or operate Pointer across real displays and Spaces |
| Physical/manual | Visible palette and overlays, pointer and keyboard behavior, hit targets, focus, VoiceOver, display/Space transitions, reconnect, shortcut delivery, perceived latency, and long-session behavior | Hidden model invariants or coverage of every randomized state unless paired with deterministic tests |

Every campaign report labels which class supports each claim. A deterministic
pass never silently becomes a physical-use pass, and a screenshot never stands
in for an interaction sequence.

## Workstream map and ownership

The workstreams are disjoint write scopes. A dependency means that a worker may
consume an accepted interface or evidence artifact; it does not grant
permission to edit another workstream's files. Each worker must inspect shared
`git status` before writing, preserve unrelated changes, and leave commits and
publication to the coordinating agent.

| ID | Workstream | Owns | Depends on |
| --- | --- | --- | --- |
| A-foundation | Deterministic foundation and CLI smoke | `Sources/PointerAppKit/Diagnostics/SmokeRunner.swift`; `Tests/PointerAppKitTests/Support/**`; `Tests/PointerAppKitTests/SmokeRunnerTests.swift` | None; establishes phase-neutral contracts and smoke |
| B-core | Gesture, display, lifecycle, cursor, and public CanvasView gesture seams | `Sources/PointerCore/**`; `CanvasView.swift` gesture/cursor methods only; `DisplayCoordinator.swift`; `OverlayPanel.swift`; screen/display providers; matching model, gesture, and display tests (excluding `Tests/PointerAppKitTests/Support/**` and `Tests/PointerAppKitTests/Harness/**`) | A-foundation's accepted state/event contracts |
| C | Palette, commands, shortcuts, accessibility, guide composition, and placement | `Palette/**`; `Sources/PointerAppKit/Palette/ControlMetadataProvider.swift`; `Sources/PointerAppKit/Palette/GuidePlacementContext.swift`; `Sources/PointerAppKit/Palette/GuidePlacementProvider.swift`; `CommandRouter.swift`; `MenuBarController.swift`; `PointerApplication.swift`; `PointerApplicationController.swift`; shortcut files; `Sources/PointerAppKit/Help/FirstUseGuidePresenting.swift`; only app-controller/palette/command/shortcut tests such as `PointerApplicationControllerTests.swift` (excluding `Tests/PointerAppKitTests/Support/**` and `Tests/PointerAppKitTests/Harness/**`) | B-core's accepted lifecycle contracts and A-foundation support |
| D | Visual language, learning support, and render-plan contracts | `MarkRenderer.swift`; `Sources/PointerAppKit/Rendering/RenderPlan.swift`; `Sources/PointerAppKit/Rendering/HandleInventory.swift`; `Bundle/Assets.xcassets/**`; `Bundle/AppIconIdentity.json`; `Bundle/GuideAssetIdentity.json`; `Sources/PointerAppKit/Help/GuideAssetCatalog.swift`; `Sources/PointerAppKit/Help/FirstUseGuideController.swift`; `Sources/PointerAppKit/Help/FirstUseGuideViewController.swift`; `Sources/PointerAppKit/Help/FirstUseGuideStateStoring.swift`; `Sources/PointerAppKit/Help/UserDefaultsFirstUseGuideStateStore.swift`; `Tests/PointerAppKitTests/FirstUseGuideTests.swift`; `Tests/PointerAppKitTests/FirstUseGuideTestFixtures.swift`; `Tests/PointerAppKitTests/AssetIdentityTests.swift`; `Tests/PointerAppKitTests/RenderPlanTests.swift`; visual/accessibility snapshot tests and resources (excluding `Tests/PointerAppKitTests/Support/**` and `Tests/PointerAppKitTests/Harness/**`) | B-core geometry/lifecycle contracts and C's accepted control/guide interface |
| B-render-integration | CanvasView render-plan integration and standby live path | `CanvasView.swift` draw/render-plan integration only; `Tests/PointerAppKitTests/CanvasViewRenderIntegrationTests.swift` | D's accepted RenderPlan/HandleInventory and B-core CanvasView seam |
| A-harness | Real integrated interaction harness | `Sources/PointerAppKit/Diagnostics/DeterministicInteractionHarness.swift`; `Tests/PointerAppKitTests/Harness/**`; harness-only report fixtures | B-render-integration's accepted live rendering path and all prior phase contracts |
| E | Performance and resilience measurement | `Sources/PointerAppKit/Diagnostics/GestureBenchmark.swift`; `Sources/PointerAppKit/Diagnostics/PerformanceHarness.swift`; `Sources/PointerAppKit/Diagnostics/PerformanceComparisonHarness.swift`; `Tests/PointerAppKitTests/GestureBenchmarkTests.swift`; `Tests/PointerAppKitTests/PerformanceHarnessTests.swift`; `Tests/PointerAppKitTests/PerformanceComparisonHarnessTests.swift`; benchmark scripts; performance fixtures; `.codex/sdd/reports/quality-campaign/performance/measurements/**`; `.codex/sdd/reports/quality-campaign/performance/comparisons/**`; measured fixes only within prior phase-owned code through a returned finding | A-harness's converged production path |
| F | Integration, composition, manual use, and completion evidence | `Package.swift`; `Sources/PointerComposition/PointerCompositionRoot.swift`; `Sources/Pointer/main.swift`; `Tests/PointerCompositionTests/PointerCompositionRootTests.swift`; `PointerBuildScriptsTests` target; `Tests/BuildScripts/**` including `LauncherContractTests.swift`, `GuideAssetCatalogBuildTests.swift`, `CleanCloneContractTests.swift`, `IconResolutionProbe.swift`, and `test-build-contract.sh`; `.github/workflows/verify.yml`; `Bundle/Info.plist`; `scripts/build-app.sh`; `scripts/run-app.sh`; `scripts/verify.sh`; clean-clone/manual test harnesses; `.codex/sdd/reports/quality-campaign/final/**`; final validation matrix | E and all prior reconciled phases; owns composition and final aggregation, not product behavior |

The canonical phase graph is
`A-foundation → B-core → C → D → B-render-integration → A-harness → E → F`.
A-foundation establishes phase-neutral state/event contracts and CLI smoke;
B-core owns the public gesture/display/lifecycle seam without RenderPlan
integration; C consumes B-core; D consumes B-core/C and publishes the
RenderPlan/HandleInventory contract; B-render-integration consumes D and edits
only the CanvasView draw seam; A-harness consumes the converged real view path;
E consumes A-harness; F consumes every reconciled phase. There are no back
edges: D never edits B, B-render-integration never edits D, and A-harness
cannot change B-core APIs. Only disjoint work within one phase may run in
parallel, and a downstream phase cannot start until the upstream worker,
reviewer, and adversarial gate is reconciled. C owns the
`FirstUseGuidePresenting` interface and application/menu injection points; F
still owns the importable `PointerComposition` library and composition factory.
The `Pointer` executable retains its diagnostic and interactive paths, and
`PointerCompositionTests` imports `PointerComposition`/`PointerAppKit` rather
than the executable. E remains the sole owner of
`.codex/sdd/reports/quality-campaign/performance/measurements/**` and
`.codex/sdd/reports/quality-campaign/performance/comparisons/**`; F consumes those reports
and writes only final aggregation under
`.codex/sdd/reports/quality-campaign/final/**`.

## Workstream A-foundation — deterministic foundation and CLI smoke

Purpose: establish phase-neutral test contracts and deterministic CLI smoke
before any integrated CanvasView/render harness exists.

Acceptance criteria:

- A no-window smoke invocation reports exactly one palette, one overlay plan
  per supplied display, standby mode, the selected tool/style defaults, and a
  valid default shortcut. Its output is stable JSON suitable for a script and
  does not require Accessibility, Input Monitoring, or Screen Recording.
- `Tests/PointerAppKitTests/Support/**` inside the existing
  `PointerAppKitTests` target contains only phase-neutral fakes and fixtures for
  screens, clocks, shortcut registration, state stores, and command spies. It
  cannot instantiate CanvasView, OverlayPanel, DisplayCoordinator, or a second
  gesture engine. This support subtree requires no new SwiftPM target, product,
  or `Package.swift` wiring.
- The smoke schema and CLI contract are deterministic and versioned. The
  foundation tests prove `--smoke --format json` creates no interactive
  composition, requires no global input synthesis or privacy permission, and
  fails closed on invalid display fixtures.
- This phase gate is complete only when the worker, independent reviewer, and
  adversarial Codex have accepted the smoke output/schema and test-support
  seams. It does not claim physical interaction, render-plan convergence, or
  live CanvasView behavior; those belong to A-harness after B-render-integration.

## Workstream B-core — gesture, display, lifecycle, cursor, and public CanvasView seams

Purpose: remove the failures that can make a presenter lose control or lose
marks during a live presentation.

Acceptance criteria:

- B-core may edit CanvasView's public gesture methods, cursor plan, session
  update, and cancellation seam, but it must not edit `CanvasView.draw`,
  RenderPlan consumption, MarkRenderer integration, or standby pixel proof.
  Those edits belong exclusively to B-render-integration after D's render
  contract is accepted.
- `CanvasView` owns cursor selection and restoration. It exposes a deterministic
  cursor plan for select, drawing, eraser, emoji, and spotlight tools, restores
  the normal click-through cursor in standby, and never lets the palette or
  command router silently override the canvas cursor. `CanvasViewTests` cover
  every tool and the standby transition.
- Escape cancels an active draft before entering standby. A later stale
  `mouseUp` cannot commit the cancelled draft or create an undo entry.
- Switching mode, changing display parameters, closing an overlay, or losing a
  display cancels its active gesture and restores the exact pre-gesture model
  state. Entering standby always clears the selection while retaining
  committed marks and undo history. Standby overlays ignore mouse events while
  marks remain visible and all selection chrome, resize handles, hover
  indicators, active-draft pixels, and contextual Delete affordances stay
  absent. Re-entering annotation always starts with no selection; the
  presenter must explicitly select a mark before handles or Delete return.
- Arrow, rectangle, ellipse, pen, emoji, spotlight, select, and eraser preserve
  their documented pointer contracts. Zero-length shapes are discarded; sparse
  eraser samples sweep the segment between samples; one erase drag creates one
  undo snapshot; selection chooses the topmost hit and clears on empty canvas.
- Move, delete, and every supported resize handle preserve normalized geometry,
  aspect-ratio rules, selection ownership, and undo behavior. A display resize
  changes pixels, not the display-local mark meaning.
- Hit testing treats inclusive/epsilon geometry deliberately. Segment
  intersection tests cover collinear overlap and endpoint contact, a segment
  tangent to an ellipse or rectangle boundary, and the just-outside-
  epsilon miss case. `HitTestingTests` and gesture regressions include
  `testCollinearOverlapOnRectangleEdgeCountsAsHit`,
  `testTangentEllipseBoundaryCountsAsHit`,
  `testArrowEndpointContactWithinEpsilonCountsAsHit`, and
  `testSegmentOutsideEpsilonMisses`, so a future numeric change cannot turn a
  visible rectangle or arrow boundary hit into a miss.
- A disconnected display's canvas remains in memory for the process and is
  restored only when the same stable UUID reconnects. It never migrates marks
  to another display. A removed overlay is closed exactly once.
- One overlay exists per connected physical display, remains above the
  presentation, joins Spaces/full-screen as designed, and does not intercept
  clicks in standby. The palette remains above an interactive overlay when
  annotation mode is active.
- `DisplayCoordinator.synchronize()` returns a `DisplaySyncResult` containing
  connected UUIDs, added/removed UUIDs, pointer-display identity, and explicit
  `hasConnectedDisplays`/`enteredZeroDisplayState`/`reconnected` flags, and
  emits the same result through an `onDisplaySync` callback. The result is the
  only lifecycle signal consumed by C for palette behavior; B does not own or
  mutate palette visibility. `DisplayCoordinatorTests` assert added, removed,
  reconnect, pointer-display, and zero-display result flags plus exactly one
  callback per synchronization.
- B owns `DisplayCoordinator.stop() -> DisplayStopResult`. It cancels every
  active gesture, clears each CanvasView/overlay session and boundary handler,
  closes and removes every overlay exactly once, empties the overlay map, and
  returns `closedOverlayCount`, `remainingOverlayCount`,
  `activeGestureCount`, and `boundHandlerCount`. It preserves display-local
  session canvases but never retains a closed panel for reuse. A later
  `synchronize()` creates and shows fresh overlays from the factory. B's
  `DisplayCoordinatorTests` cover stop with zero/one/multiple displays,
  closed-panel non-reuse, exact handler clearing, and fresh overlay identity
  after restart.
- A zero-display transition is a supported, deterministic oracle: synchronizing
  from one display to `[]` cancels every active gesture, closes and removes
  every overlay exactly once, hides the palette, and leaves the in-memory
  session canvases, undo history, selected tool/style, working shortcut
  registration, and menu-bar item intact. With no display, mode is standby so
  no input can be intercepted. Synchronizing a display back in recreates its
  overlay and, if the palette was visible before the transition, restores and
  clamps it to the pointer display's visible frame; a palette that was hidden
  stays hidden until explicitly shown.
- Display churn, pointer-display changes, no-display transitions, Space
  changes, and reconnects leave the application in a usable mode with no
  orphaned gesture, overlay, timer, or event handler. The zero-display oracle
  has deterministic assertions for each retained and removed resource.
- B-core's phase gate is the accepted public CanvasView gesture/cursor seam,
  DisplaySyncResult/DisplayCoordinator.stop contract, and lifecycle/geometry
  test suite. The worker, independent reviewer, and adversarial Codex must
  reconcile this gate before C starts; no RenderPlan or draw integration is
  accepted in B-core.

## Workstream C — palette, commands, shortcuts, and accessibility

Purpose: make the most frequently touched surface legible, fast, and operable
without a mouse.

Acceptance criteria:

- C owns `FirstUseGuidePresenting.swift`, the `FirstUseGuidePresenting`
  protocol, and the application/menu wiring that calls
  `showIfNeeded(in:)`, `show(in:)`, `dismiss()`,
  `hideForDisplayLoss()`, `restoreAfterDisplayLoss(in:)`,
  `hideForApplicationStop()`, and
  `consumeEscape() -> Bool`. D receives that interface as an input and
  implements the guide panel; C does not import or depend on
  D's concrete view/controller. The menu-bar `Learn Pointer` command and the
  initial-palette composition are therefore testable without a dependency
  cycle. C owns only its app-controller/palette/command/shortcut tests;
  `Tests/PointerCompositionTests/PointerCompositionRootTests.swift` is
  exclusively F-owned.
- The presentation methods return the explicit `GuidePresentationResult` enum
  (`.shown`, `.notNeeded`, or `.failed(String)`). `.shown` means the guide is
  actually visible, not merely requested. The controller clears pending
  first-use or reconnect intent only for `.shown` or `.notNeeded`, retains it
  for `.failed`, and never advances it when the palette is hidden.
- C owns the `DisplaySyncResult` callback consumer. On
  `hasConnectedDisplays == false` it hides the palette, keeps the session and
  menu-bar/shortcut controls alive, and rejects every annotation-entry command
  (tool selection, toggle, menu, or shortcut) with standby plus actionable
  "No presentation display connected" feedback without mutating the selected
  tool or mode. It never creates or restores a palette at zero displays. On
  `reconnected == true`, it restores and clamps
  the palette only when it was visible before the zero-display transition;
  otherwise it leaves it hidden. Application-controller tests cover both
  callback branches and the no-display annotation rejection. It also calls
  `guide.hideForDisplayLoss()` on the zero-display branch; on reconnect it
  calls `guide.restoreAfterDisplayLoss(in:)` only after `palette.show(on:)`
  returns `.shown`.
- C tracks initial palette presentation independently of guide dismissal:
  zero-display startup leaves the initial presentation pending, while an
  ordinary connected-display sync never calls `palette.show(on:)` and keeps a
  manual drag. A palette that was hidden before the zero-display transition
  stays hidden on reconnect; a palette visible at the transition is restored
  and clamped. B owns the `PointerSession.selectedDisplay` handoff that C
  consumes read-only for selection/style controls; ownership changes return to
  B.
- Explicit Learn Pointer/showGuide success supersedes pending first-use or
  display-loss intent only when `.shown` is actually visible or `.notNeeded`;
  failures remain pending. Ordinary retries obtain a fresh placement context
  from the injected provider using the current display and palette frame, so a
  manual palette drag and display-frame changes are reflected without a
  palette re-show.
- C's public `PalettePresenting.show(on:)` returns a `PaletteShowResult` with
  `.shown(GuidePlacementContext)`, `.noDisplay`, or `.failed` rather than
  silently ordering a window; the guide timing and zero-display retry logic
  consume the placement context from the successful result. The public enum is
  equivalent to `PaletteShowResult.shown(GuidePlacementContext)`,
  `.noDisplay`, and `.failed(String)`; only `.shown(context)` permits guide
  show/restore.
- `PalettePresenting` exposes the placement identity without mutation through
  `var guidePlacementProvider: any GuidePlacementProviding { get }`. The
  composition root injects the same provider into the palette and the public
  `PointerComposition` container; no palette implementation may discover a
  second provider.
- C owns the public `GuidePlacementContext` and placement providers. The
  context includes the target display descriptor/UUID, visible display frame,
  actual palette frame, and avoidance frames for the palette, menu/guide, and
  presentation-safe regions. `GuidePlacementProvider` computes it from the
  current display and palette frame; `ControlMetadataProvider` supplies the
  deterministic menu/palette metadata inventory. C's tests assert that guide
  show/restore receives the same display, palette frame, and avoidance frames
  that placement computed, and that the guide never overlaps those frames.

  The public placement contract is equivalent to:

  ```swift
  public struct GuidePlacementContext: Equatable, Sendable {
      public let display: DisplayDescriptor
      public let visibleFrame: DisplayFrame
      public let paletteFrame: DisplayFrame
      public let avoidanceFrames: [DisplayFrame]
  }

  public protocol GuidePlacementProviding: AnyObject {
      func context(for display: DisplayDescriptor,
                   paletteFrame: DisplayFrame) -> GuidePlacementContext?
  }

  public protocol ControlMetadataProviding: AnyObject {
      func metadata() -> [ControlMetadata]
  }
  ```

  `FirstUseGuidePresenting.showIfNeeded(in:)`, `show(in:)`, and
  `restoreAfterDisplayLoss(in:)` all accept this same context; no overload may
  silently fall back to display-only placement.
- Guide timing is ordered and retryable: `PointerApplicationController` calls
  `palette.show(on:)` first and calls `guide.showIfNeeded(in:)` only after that
  operation returns `.shown` from the public `PaletteShowResult` contract. If
  startup has zero
  displays, it records the pending first-use attempt without showing or marking
  the guide; the first later `DisplaySyncResult.hasConnectedDisplays == true`
  retries palette show, then `guide.showIfNeeded(in:)` in that order. A
  display-loss intent from an already visible/pending guide instead uses
  `restoreAfterDisplayLoss(in:)`, never a second first-use request. A failed or
  hidden palette show never advances the guide state. Controller tests assert
  the order, zero-display retry, and that no guide is marked seen before a
  visible guide panel exists. The same controller tests assert display-loss
  hide, reconnect palette-show-before-guide-restore ordering, and unchanged
  mode and selected tool.
- C owns the visible-guide Escape precedence. `PointerApplication.sendEvent`
  receives the injected `FirstUseGuidePresenting` reference and asks it to
  consume Escape before calling `CommandRouter.routeLocalKeyEvent`; a visible
  guide dismisses and returns handled, so Pointer mode, selected tool, and
  canvas selection remain unchanged. A
  `PointerApplicationControllerTests` construction/route test proves the
  first-refusal ordering with a visible guide and a command spy.
- `UserDefaultsShortcutStore` requires an explicit `UserDefaults` instance and
  key, and `HotKeyController`'s production initializer requires its registrar,
  shortcut store, and scheduler. No production shortcut/store convenience
  initializer may discover global state; fakes may use a test-only factory.
- F's `PointerComposition.PointerCompositionRoot.make()` returns the
  inspectable `PointerComposition` container after constructing the concrete
  screen provider, display coordinator, command router, palette, menu bar,
  `ControlMetadataProvider`, `GuidePlacementProvider`, `GuideAssetCatalog`,
  Carbon registrar, scheduler, `UserDefaultsShortcutStore`, shortcut
  controller, D's guide, `GuideAssetCatalogProviding`, and
  `FirstUseGuideStateStoring`, then injecting them
  through C's protocols. C's application controller accepts these dependencies
  explicitly; its no-argument convenience construction is removed from the
  production target or restricted to test support. The canonical composition
  test must instantiate this graph and assert every dependency identity, the
  initial mode/tool are unchanged by guide construction, and no store or
  registrar is discovered implicitly.
- Same-process stop/start is a supported restart contract.
  `PointerApplicationController.stop()` calls B's
  `DisplayCoordinator.stop()` and requires its `DisplayStopResult` to report
  exact closure/handler counts; it then hides the palette, calls the guide's
  non-committing
  `hideForApplicationStop()` cleanup, removes the screen-parameter observer,
  releases shortcut timers and menu callbacks, and leaves no panel, observer,
  timer, or callback retained by the stopped controller. `start()` rebinds the
  `HotKeyController` callback exactly once, recreates one observer/menu/palette
  and calls `DisplayCoordinator.synchronize()` to create fresh overlays—never
  closed-panel instances—one per connected display, then restores usable state
  without duplicate delivery or windows. `HotKeyController` tests prove stop/start
  callback rebinding and exactly one toggle per active hotkey event;
  `PointerApplicationControllerTests` prove stop cleanup, non-committing guide
  state, cleared display-loss intent, and duplicate-free restart.
- The lifecycle checkpoints are separate resource oracles. While running, the
  expected bounded inventory is exactly one palette panel, one menu-bar item,
  one screen-parameter observer, one active shortcut callback/wiring, one
  overlay per connected display, and the documented timer inventory (zero
  timers normally, one provisional-delivery timer only during shortcut
  testing); a guide panel is zero or one according to its visible/pending
  state. At deliberate stop, the expected inventory is zero owned overlays,
  windows, timers, callbacks, observers, and visible guide panels, with the
  guide cleanup non-committing; the `DisplayStopResult` must report the same
  zero remaining/handler counts. After restart, the running inventory must be
  rebuilt exactly, one overlay per display and one callback delivery per
  hotkey event, with no duplicate palette/menu/observer/wiring. Tests name and
  assert the running, stopped, and restarted checkpoints independently.
- The palette communicates one clear current mode and one clear selected tool;
  the mode control is not visually confused with a tool. The current tool,
  active style, pending shortcut, and shortcut error are visible without
  opening a second settings flow.
- Tool controls use coherent native SF Symbols or equivalent icons paired with
  canonical labels/tooltips. Icon-only controls never carry the sole meaning;
  every control retains an accessible name, help, stable identifier, enabled
  state, keyboard route, and visible focus state.
- Undo, Clear, and other momentary actions look and behave like actions, not
  persistent selections. No-op actions are disabled or clearly explained.
  Clear All remains a menu-bar command with confirmation and a reversible Undo
  Clear All state.
- Selection has an explicit escape route and delete affordance. Clicking empty
  canvas clears selection and produces brief nonmodal feedback; while a mark is
  selected, a contextual `Delete` action is visible and routes to the same
  command as Delete/Backspace. The affordance disappears when nothing is
  selected and never covers the presentation canvas. Palette tests assert the
  full sequence: selected mark → visible/enabled Delete, enter standby →
  selection cleared and Delete absent, re-enter annotation → still absent,
  explicit selection click → visible/enabled Delete again.
- Color, stroke, opacity, emoji, radius, and dimness controls appear only when
  relevant or are clearly disabled with an explanation. Their values are
  visible and update both compatible selections and future marks according to
  the existing contract.
- The layout remains usable at the narrowest supported visible display width:
  all tools remain reachable, overflow has an obvious label, controls do not
  collapse to zero width, and the palette does not cover an essential
  presentation target. Normal refresh preserves a manual palette drag; an
  explicit Show Palette repositions and clamps it to the pointer display.
- Mode and tool changes provide explicit, brief feedback: entering annotation,
  returning to standby, and selecting a tool update the selected state and
  status message without stealing focus, moving the palette, or intercepting
  the presented application. The standby message explicitly says that
  overlays are click-through; a tool message names the newly selected tool.
- An active shortcut registration error remains higher priority than immediate
  success or no-op feedback. Once that error resolves, stale suppressed
  feedback is not replayed; the palette returns to the current normal mode and
  shortcut status without moving focus or frame.
- Palette and menu-bar flows are keyboard-operable in a logical order. Escape,
  Delete/Backspace, Undo, mode toggle, and tool selection behave consistently
  whether focus is in the palette or an overlay. The menu bar remains a full
  fallback when a shortcut is unavailable.
- VoiceOver announces role, name, value, selected/enabled state, and shortcut
  status in an order that teaches the task. Reduce Transparency and Increase
  Contrast produce usable visual states; selection, focus, hover, disabled,
  and error states do not rely on color alone.
- The shortcut transaction keeps the old working shortcut until a candidate
  is delivered, persists only after delivery within five seconds, rolls back on
  registration error or timeout, ignores late candidate events, and exposes an
  actionable error without resizing or hiding the palette.

## Workstream D — visual language and learning support

Purpose: use visual communication to shorten the learning curve and make state
changes feel intentional, while removing persistent chrome wherever context is
enough.

Acceptance criteria:

- Workstream D implements the concrete first-use guide in
  `FirstUseGuideController.swift` and
  `FirstUseGuideViewController.swift` against C's
  `FirstUseGuidePresenting` interface (`showIfNeeded(in:)`, `show(in:)`,
  `dismiss()`, `hideForDisplayLoss()`, `restoreAfterDisplayLoss(in:)`,
  `hideForApplicationStop()`,
  `consumeEscape() -> Bool`, and `isVisible`). D owns the panel, its show/dismiss behavior,
  and its tests; C owns the application/menu composition and passes the
  interface in. The guide appears once on the first successful launch, can be
  reopened from C's `Learn Pointer` command, and dismisses from its Close/Done
  button or Escape without changing mode or tool state.
  `FirstUseGuideController` requires an injected
  `FirstUseGuideStateStoring`; it never reads `UserDefaults.standard` itself.
  D owns `FirstUseGuideStateStoring` and
  `UserDefaultsFirstUseGuideStateStore`, whose initializer accepts an explicit
  `UserDefaults` instance and owns the single first-use dismissal key. D tests
  use a unique `UserDefaults(suiteName:)` suite and a fake store, prove failed
  panel creation or a non-visible panel does not mark the guide seen, and
  prove the flag is not saved canvas state. `showIfNeeded(in:)` marks the state
  store only from the panel's successful visible/order-front callback, never
  at request time. F's `PointerCompositionRoot` is the only production site
  that creates the store with `UserDefaults.standard`.
- D owns the public injected `GuideAssetCatalogProviding` contract. It covers
  every tool/example entry, its stable asset identifier, light/dark/high-
  contrast variants, each variant's source SHA-256, accessible name,
  accessible description, and decorative flag. `FirstUseGuideController`
  requires an `any GuideAssetCatalogProviding` in its initializer and resolves
  every image through that catalog; it has no `Bundle.main`, default image
  lookup, or silent fallback path. Missing entries, variants, hashes, or
  required accessible text are errors.

  The public schema is equivalent to:

  ```swift
  public enum GuideAssetVariant: String, Codable, CaseIterable {
      case light, dark, highContrast
  }

  public struct GuideAssetVariantDescriptor: Codable, Equatable, Sendable {
      public let variant: GuideAssetVariant
      public let assetIdentifier: String
      public let sourceSHA256: String
  }

  public struct GuideAssetDescriptor: Codable, Equatable, Sendable {
      public let id: String
      public let variants: [GuideAssetVariantDescriptor]
      public let accessibleName: String
      public let accessibleDescription: String
      public let isDecorative: Bool
  }

  public protocol GuideAssetCatalogProviding: AnyObject {
      var entries: [GuideAssetDescriptor] { get }
      func image(for assetIdentifier: String,
                 variant: GuideAssetVariant) throws -> NSImage
  }
  ```

  `Bundle/GuideAssetIdentity.json` is exactly this serialized catalog envelope
  with no alternate fields: top-level `schemaVersion` (integer),
  `catalogIdentifier` (string), and `entries` (array); each entry has `id`,
  `accessibleName`, `accessibleDescription`, `isDecorative`, and `variants`;
  each variant has `variant` (`light`, `dark`, or `highContrast`),
  `assetIdentifier`, and `sourceSHA256`. Every `sourceSHA256` must match the
  lowercase regex `^[0-9a-f]{64}$`. The manifest must include every
  tool/example and all three variants, and its decoded shape must equal the
  public structs above.
- `AssetIdentityTests.swift` and `FirstUseGuideTests.swift` deterministically
  enumerate every catalog entry/variant, validate identifiers and 64-hex
  source hashes, verify source bytes match each hash, resolve every compiled
  image through the injected catalog, and assert accessible names/
  descriptions/decorative behavior. F's Release and clean-clone gates compare
  every manifest entry and source hash to compiled `Assets.car` identifiers;
  missing, extra, or mismatched entries fail the build.
- `hideForDisplayLoss()` is non-committing: when the guide is visible or a
  first-use show is pending, it records that intent, orders out/closes the
  guide panel, leaves `FirstUseGuideStateStoring` unchanged, and does not
  mutate mode, selected tool, selection, or canvas. After reconnect, C may call
  `restoreAfterDisplayLoss(in:)` only after a successful `.shown(context)` palette
  result; it restores the prior visible/pending guide exactly once. The
  deterministic controller suite covers visible → zero displays → reconnect,
  asserts no orphan panel, no seen-state mutation, and unchanged mode/tool,
  and proves that failed palette restoration leaves the guide hidden and
  pending.
- `hideForApplicationStop()` is distinct from display loss: it orders out and
  closes the guide panel, clears any transient display-loss restoration intent,
  leaves `FirstUseGuideStateStoring` unchanged, and does not mutate mode,
  selected tool, selection, or canvas. A later same-process `start()` follows
  normal `showIfNeeded(in:)` and seen-state rules after successful palette show;
  it never restores stale pre-stop display-loss intent. Deterministic tests
  cover display-loss intent followed by deliberate stop/start, assert no stale
  guide restore, no orphan panel, no seen mutation, and normal first-use
  behavior for both unseen and already-seen state.
- D's guide gives every informative icon and visual example an accessible name
  and description (for example, `Arrow example — draws an attention arrow`);
  decorative background art is hidden from the accessibility tree. Its focus
  order is title → concise explanation → tool example/name/description →
  essential shortcut → accessible Close/Done action, with Escape performing
  the same dismiss command. `FirstUseGuideTests.swift` deterministically
  inspects that metadata, order, role, and enabled state for every example and
  for Close/Done. F records live VoiceOver evidence for first launch, guide
  reopen, example announcements, Close/Done, Escape, and post-dismissal focus
  return; deterministic metadata cannot substitute for that manual check.
- D supplies tracked `Bundle/Assets.xcassets/AppIcon.appiconset` contents,
  `Bundle/AppIconIdentity.json`, and the guide assets under
  `Bundle/Assets.xcassets/FirstUseGuide`. The identity manifest names the
  exact `AppIcon` asset, source-file SHA-256 values, canonical raster
  dimensions/color space/alpha policy, expected marker pixel coordinate/RGBA,
  and expected resolved-icon digest. The chosen executable
  strategy is Release `actool` compilation to
  `Contents/Resources/Assets.car` with `CFBundleIconName=AppIcon`; copying raw
  `.xcassets` into the bundle is not success. F owns the build assertion and
  fails if the compiled catalog, metadata, manifest, or icon set is missing.
  The guide
  shows each tool's icon and a representative result (for example, an arrow,
  shape, stroke, spotlight, emoji, and selection) with one concise explanation
  and any essential shortcut. The guide is a separate, non-modal help panel—
  not a presentation overlay—and is clamped beside the palette. It is
  automatically dismissed when annotation begins, never enters overlay Space
  collection behavior, never covers a canvas target during normal annotation,
  and does not reappear automatically after dismissal.
- Tool icons and visual examples are native-resolution, local assets with
  dark/light and contrast-aware variants where needed. They load without a
  network, do not depend on an untracked file, and do not turn into decorative
  wallpaper or a new onboarding subsystem.
- The palette, overlay marks, selection handles, spotlight dimming, hover/focus
  rings, disabled controls, shortcut errors, and empty/standby states share a
  small, documented visual language. The strongest visual emphasis is reserved
  for the selected tool, active mode, and actionable error.
- Renderer changes preserve normalized geometry, stroke/opacity semantics,
  click-through behavior, selection-handle contracts, and the one-spotlight
  rule. A visual change that makes a mark harder to see on a presentation is a
  regression even if a snapshot looks attractive.
- D defines the public `RenderPlan` and `HandleInventory` contracts and runs
  `MarkRenderer` offscreen for standby and annotation fixtures without editing
  `CanvasView.draw`. The plan contains committed marks, active draft,
  selection/resize/hover handles, and contextual Delete visibility; D proves
  marks remain in standby while the selection inventory is empty and explicit
  selection repopulates it. B-render-integration consumes this accepted plan;
  D's offscreen check never claims live CanvasView convergence.
- D's phase gate is the reviewed RenderPlan/HandleInventory schema, renderer
  output, asset/accessibility checks, and guide tests. The worker, independent
  reviewer, and adversarial Codex must reconcile it before B-render-integration
  may edit the CanvasView draw seam.
- Visual checks cover light/dark appearance, Increase Contrast, Reduce
  Transparency, narrow and wide palettes, full-screen presentation content,
  selected/unselected tools, and a dense canvas. Any intentional animation has
  a reduced-motion-safe behavior and does not delay the first usable state.
- Every added visual element has a specific learning or state-communication
  job. D supplies F with a before/after persistent-chrome inventory covering
  always-visible control count, palette rows, visible status elements, focus
  stops, and the additions/removals list. The candidate must reduce at least
  one persistent dimension and must not increase any other persistent
  dimension; contextual help does not excuse added permanent chrome.
- D and F run a common-path click inventory from fresh launch/standby through
  choose Arrow, draw one arrow, and return to standby. It records required
  pointer clicks, keyboard presses, mode/tool transitions, and required steps;
  the candidate must be no worse in every dimension and must reduce at least
  one persistent-complexity dimension. If the inventory shows a net increase
  in persistent complexity or common-path friction, the workstream remains
  `REVISE` regardless of visual polish.

## Workstream B-render-integration — CanvasView render-plan integration and standby live path

Purpose: connect B-core's live CanvasView to D's reviewed render contracts
without moving rendering policy back into gesture/lifecycle code.

Acceptance criteria:

- This phase may edit only `CanvasView.draw` and its render-plan adapter and
  integration tests. It consumes D's `RenderPlan` and `HandleInventory`; it
  does not edit B-core gesture methods, DisplayCoordinator lifecycle logic, or
  D-owned renderer/plan files.
- `CanvasView.draw` consumes the current session/mode and D's plan, renders
  committed marks and active drafts, and obeys the exact standby invariant:
  marks remain visible, selection is cleared, selection/resize/hover handles
  and contextual Delete are absent, and annotation re-entry remains
  unselected until an explicit selection click. Draw does not mutate session,
  selection, undo, or tool state.
- `CanvasViewRenderIntegrationTests.swift` attaches the real CanvasView to a
  non-visible window, exercises the accepted plan in standby and annotation,
  inspects the plan/handle inventory and rendered pixels, and proves the
  CanvasView adapter converges with D's RenderPlan contract. It includes the
  selected → standby → unselected annotation → explicit re-selection sequence.
- This phase gate requires the worker, independent reviewer, and adversarial
  Codex to approve the phase-scoped diff, offscreen visual output, and no-cycle
  check before A-harness may instantiate the fully integrated interaction
  harness. The gate does not replace F's live manual CanvasView proof.

## Workstream A-harness — real integrated interaction harness

Purpose: exercise the actual post-render-integration product path where live
automation previously could not operate non-activating native surfaces.

Acceptance criteria:

- All integrated coordinator/view fixtures and tests live under
  `Tests/PointerAppKitTests/Harness/**` and are created only after
  B-render-integration is accepted, with the canonical integration test at
  `Tests/PointerAppKitTests/Harness/CanvasIntegrationHarnessTests.swift`.
  A-foundation's `Support/**` remains
  phase-neutral and does not import or own these harness fixtures.
- The harness instantiates the real `CanvasView`, `OverlayPanel`, and
  `DisplayCoordinator` with only OS-facing screen/clock seams faked. It drives
  the public `CanvasView.beginGesture(at:)`, `continueGesture(to:)`,
  `endGesture()`, and `cancelGesture()` methods plus
  `DisplayCoordinator.synchronize()` and the public command route. After each
  begin/advance/commit/cancel and display sync, it asserts convergence between
  the `PointerSession`, CanvasView preview/render plan, overlay mode, and
  coordinator session. A fake CanvasView or parallel gesture engine cannot
  satisfy this criterion.
- The harness records gesture boundaries distinctly from continuation samples,
  asserts at most one meaningful commit/undo entry, and covers stale mouse-up,
  standby re-entry, zero-display, stop/reset, and reconnect behavior using the
  real production objects. It exposes control metadata—accessible name, help,
  identifier, value, enabled state, and keyboard reachability—for every menu
  and palette control without synthesizing global input.
- Test fixtures include empty state, one mark, overlapping marks, a full
  palette, a narrow display, no displays, invalid display identifiers, and a
  disconnected/reconnected display. Unsupported state fails closed with a
  useful diagnostic, and the harness cannot bypass validation, WindowServer
  layering, the command router, D's RenderPlan, or the real session mutation
  route merely to make a test green.
- The phase gate requires the worker, independent reviewer, and adversarial
  Codex to reconcile real-view convergence, standby render-plan behavior, and
  deterministic/manual evidence before E starts. A-harness owns the integrated
  evidence; it does not change B-core or B-render-integration APIs.

## Workstream E — performance and resilience measurement

Purpose: find and remove perceived sluggishness with production evidence, not
speculative caching or broad rewrites.

Acceptance criteria:

- The Release benchmark continues to exercise production `PointerSession` and
  gesture APIs with 12 fixture marks, 240 continuation samples, five warmups,
  and at least 30 measured trials. It reports median, p95, MAD, publication
  count, final-state validity, and a stable model checksum. The owned
  `PerformanceHarness.swift` emits a versioned Codable
  `PerformanceMeasurementReport` for one immutable build/variant with
  `reportKind: "measurement"`, `schemaVersion`, immutable `identity`, `host`,
  `fixture`, `model`,
  `renderer`, `compositor`, `combinedFrame`, `launch`, `allocations`,
  `redrawLayout`, `responsiveness`, `inputToVisible`, `memory`, and
  `disposition` fields. Every required measurement object has exactly one
  status from `measured`, `failed`, or `unmeasured`; missing fields, `failed`,
  and `unmeasured` statuses are invalid for completion, and
  `not_applicable` is not permitted for a required metric. Model includes
  trial samples, median, p95, MAD, publication count, checksum, and
  final-state validity; renderer and compositor include sample count, p95,
  frame count, missed-frame count, and instrumentation status; `combinedFrame`
  reports the measured render-plus-compositor frame work and missed-frame
  count; launch includes cold/warm timings; allocations includes bytes per
  gesture and peak allocation bytes; `redrawLayout` includes redraws per sample,
  layout passes, and p95 work; responsiveness includes stall count, maximum
  main-thread stall, and p95 response; `inputToVisible` includes sample count,
  p95 latency, and missed samples; memory includes `windowSeconds`,
  `sampleIntervalSeconds`, RSS samples, periodic aggregates, peak RSS,
  final-window delta bytes/percent, matched-baseline series/values, peak live
  resource counts, end live resource counts, and a `phase` for each sample
  (`running`, `stopping`, `stopped`, or `restarted`).
  `PerformanceHarnessTests` validates the complete schema and statuses and
  rejects missing fields rather than treating them as zero. E writes variant
  measurements and paired comparisons only under
  `.codex/sdd/reports/quality-campaign/performance/measurements/**` and
  `.codex/sdd/reports/quality-campaign/performance/comparisons/**`; F may
  consume them but does not edit either subtree.
- Every before/after comparison uses immutable baseline and candidate
  identities: a clean commit SHA or a SHA-256 content manifest covering source,
  tests, assets, scripts, and bundle resources. It records both identities,
  host model, macOS, Xcode/developer directory, power/display state, build
  configuration, and fixture. A label such as `current` or a dirty unrecorded
  checkout is not an identity.
- The fixed paired protocol runs five warmups per variant and 30 paired trials
  on the same host/fixture, with a fixed seed and 15 baseline→candidate plus
  15 candidate→baseline pairs. It computes the paired candidate/baseline ratio
  and a fixed-seed 10,000-resample bootstrap 95% interval for each metric.
  Improvement is claimable only when the interval for the paired delta is
  strictly below zero; otherwise the comparison says no proven improvement.
- `PerformanceComparisonHarness.swift` consumes two validated
  `PerformanceMeasurementReport` files and emits a versioned
  `PerformanceComparisonReport` under
  `.codex/sdd/reports/quality-campaign/performance/comparisons/**` with
  `reportKind: "comparison"`, baseline/candidate measurement identities,
  paired ratios, bootstrap intervals, budget results, and an unambiguous
  disposition. `Pointer --benchmark-gestures --format json` emits one
  `PerformanceMeasurementReport`; `scripts/benchmark-gestures.sh` orchestrates
  the two variant runs and writes the one paired comparison. No unsuffixed
  generic performance-report type is a valid schema or output.
- Model, renderer, compositor, launch, and memory are separate actual harness
  runs exposed by `PerformanceHarness` and covered by
  `PerformanceHarnessTests` (`measureModel`, `measureRenderer`,
  `measureCompositor`, `measureCombinedFrame`, `measureLaunch`,
  `measureAllocations`, `measureRedrawLayout`, `measureResponsiveness`,
  `measureInputToVisible`, and `measureMemory`); a report never presents
  model-only timing as an end-to-end frame-rate or launch guarantee. If an
  OS-level compositor metric cannot be instrumented, its schema status is
  `unmeasured`, the report is invalid, and the completion gate remains blocked.
- `PerformanceComparisonHarnessTests` validates the paired
  `PerformanceComparisonReport` against two `PerformanceMeasurementReport`
  inputs, including identity matching, fixed pair ordering, bootstrap
  intervals, budget outcomes, and `REVISE`/completion-blocking dispositions.
- Continuation samples mutate the gesture-local preview and request redraw
  without rebuilding the palette, publishing shared inspector state, or
  creating undo entries. Boundary publication remains limited to begin,
  commit, and cancel unless a measured requirement changes it.
- A realistic dense-canvas fixture and a long-session run measure allocations,
  memory growth, redraw/layout work, and responsiveness. A candidate that
  has a candidate/baseline median or p95 ratio greater than `1.10` must be
  returned to the owning worker as `REVISE`; there is no discretionary
  "explained" exception for a >10% regression.
- The frame budget is explicit: at a 60 Hz equivalent, p95 render plus
  compositor work must stay at or below 16.7 ms for the 12-mark and dense
  1,000-mark fixtures, with no repeatable active-gesture main-thread stall
  above 100 ms. A repeatable budget breach, visible multi-frame stall, or
  p95 input-to-visible delay above 100 ms is a blocker; if the OS compositor
  cannot be instrumented, that metric is recorded as unmeasured and manual
  stutter evidence remains required rather than being treated as a pass.
- Memory is a time series, not a before/after pair: the harness records a fixed
  `windowSeconds` and `sampleIntervalSeconds` (the campaign default is 600 and
  5), every RSS sample, periodic aggregates for each interval, peak RSS,
  final-window delta bytes and percent, a matched-baseline series and matched
  baseline values, plus peak and end live-resource counts for overlays, timers,
  handlers, windows, and observers. `PerformanceHarnessTests` validates the
  plateau/leak rules only over the `running` phase: after warmup the candidate's
  final-window RSS delta is
  no more than 10% and 50 MB over its matched baseline series, the post-warmup
  slope is not positive beyond measurement noise, end resource counts are
  the expected running-state bounded values, and peak counts match the
  expected bounded fixture. `PerformanceHarnessTests` calls
  `assertRunningResourceCheckpoint`, `assertStopCleanupCheckpoint`, and
  `assertRestartCheckpoint`; stop cleanup and restart counts are separate
  checkpoints, not plateau samples: stopping must reach zero owned resources,
  and restart must return to the running-state bounds. Any linear growth,
  leaked resource, missing sample/aggregate, mismatched baseline series, or
  unexplained unbounded increase is a blocker; the complete time-series schema
  and all three phase/checkpoint rules must be `measured` before completion.
- Performance fixes address a measured bottleneck in the owning workstream;
  speculative caches, premature concurrency, dependency additions, and
  abstractions without a second use are rejected.
- Disposition is evidence-gated: ratios ≤`1.10` with no budget breach, leak,
  or missing metric may be accepted as no regression and must retain the
  report; any ratio >`1.10`, budget breach, leak, invalid schema, or
  `unmeasured` required metric returns to the owning worker as `REVISE` and
  blocks campaign completion. An unmeasured metric is never an approval or a
  reason to claim completion.
- Resilience checks cover repeated mode toggles, rapid tool changes, 1,000-mark
  sessions, repeated clear/undo, palette show/hide, display churn, and
  shortcut candidate timeout without leaked timers, handlers, windows, or
  unexpected growth.

## Workstream F — integration, manual use, and completion evidence

Purpose: prove that the product works as experienced, not merely that its
isolated tests are green.

Acceptance criteria:

- The integrated gate runs the full Swift suite, Release build, bundle/plist/
  signature/arm64 validation, deterministic smoke, benchmark, and
  `git diff --check`. Workstream F owns `Bundle/Info.plist`,
  `scripts/build-app.sh`, `scripts/run-app.sh`, and
  `Tests/BuildScripts/test-build-contract.sh`; those contracts are verified in
  Release and by a clean-clone run, not assumed from a Debug test. The gate
  validates every tracked bundle resource—including the app icon,
  `GuideAssetIdentity.json`, and `FirstUseGuide` assets—after copying, checks `plutil`, executable
  architecture, ad-hoc signature, and resource existence, and proves a second
  build is idempotent. The Release build invokes `actool` for the tracked
  `AppIcon.appiconset`, asserts `Contents/Resources/Assets.car` contains the
  AppIcon set, and asserts `CFBundleIconName` is exactly `AppIcon`; a raw
  `.xcassets` directory or a missing icon metadata key fails the gate. The
  contract test compiles the owned `Tests/BuildScripts/IconResolutionProbe.swift`
  with `xcrun swiftc -framework AppKit -framework CoreServices`, then invokes
  the resulting probe with the Release bundle path, expected exact bundle URL,
  bundle identifier, and `Bundle/AppIconIdentity.json`. The probe calls
  `LSRegisterURL`, `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`,
  and `NSWorkspace.shared.icon(forFile:)`; it exits nonzero unless Launch
  Services resolves the exact expected standardized URL, `assetutil --info`
  reports the `AppIcon` identity, and the resolved icon's marker pixel/digest
  matches the tracked manifest. A generic system fallback, nonempty image with
  the wrong marker, or missing asset identity cannot pass. The build-contract
  probe canonicalizes the resolved `NSImage` by selecting a representation by
  pixel dimensions rather than points/backing scale, rendering exactly
  512×512 pixels into sRGB IEC 61966-2.1 RGBA8, normalizing premultiplied or
  straight alpha to straight alpha (zeroing RGB for zero-alpha pixels), and
  hashing row-major normalized RGBA bytes with SHA-256. It compares that digest
  and the manifest marker pixel, so 1× and Retina representations use the same
  deterministic identity; a missing exact-size representation is rendered by
  the same fixed-color-space path rather than accepted opportunistically. The
  build-contract test writes a tracked-resource/bundle manifest containing the
  source icon files, identity manifest, `Assets.car`, Info.plist,
  `GuideAssetIdentity.json`, and copied guide assets,
  rebuilds the Release bundle idempotently, and compares the manifests byte
  for byte (excluding only code-signature metadata). The clean-clone gate
  compiles and invokes this same probe and comparison, so icon identity and
  resource reproducibility are executable evidence rather than a manual-only
  assertion.
- The Release and clean-clone build contracts decode
  `GuideAssetIdentity.json`, require every tool/example and light/dark/
  high-contrast entry, compare each source SHA-256 and asset identifier to the
  injected `GuideAssetCatalog`, and verify every identifier resolves in the
  compiled `Assets.car` via `assetutil --info`. Missing, extra, mismatched, or
  fallback-resolved guide assets fail the gate; the decoded manifest and
  compiled catalog are included in the idempotent tracked-resource manifest.
- F owns the separate compiled-contract target `PointerBuildScriptsTests`.
  `Tests/BuildScripts/LauncherContractTests.swift` validates CLI dispatch,
  `Tests/BuildScripts/GuideAssetCatalogBuildTests.swift` decodes
  `GuideAssetIdentity.json` and compares every entry/variant/source hash to
  compiled `Assets.car`, and
  `Tests/BuildScripts/CleanCloneContractTests.swift` proves the same Release
  resource contract from a clean clone; `IconResolutionProbe.swift` and
  `test-build-contract.sh` are invoked by that gate. D's
  `Tests/PointerAppKitTests/AssetIdentityTests.swift` remains the source-asset
  catalog test; it does not replace or duplicate F's compiled-resource tests.
- The `Package.swift` acceptance is exact:

  ```swift
  .testTarget(
      name: "PointerBuildScriptsTests",
      dependencies: ["PointerAppKit"],
      path: "Tests/BuildScripts",
      exclude: ["IconResolutionProbe.swift", "test-build-contract.sh"],
      sources: [
          "LauncherContractTests.swift",
          "GuideAssetCatalogBuildTests.swift",
          "CleanCloneContractTests.swift",
      ]
  )
  ```

  These tests do not depend on `PointerComposition`; composition remains
  exclusively in `PointerCompositionTests`. `IconResolutionProbe.swift` and
  `test-build-contract.sh` are external helpers compiled/invoked by the shell
  contract, not SwiftPM sources. A clean checkout must compile and run
  `swift test --filter PointerBuildScriptsTests` before Release/clean-clone
  validation is accepted.
- `Package.swift` defines an importable `PointerComposition` library target
  depending on `PointerCore` and `PointerAppKit`. The `Pointer` executable
  target depends directly on both `PointerComposition` and `PointerAppKit`:
  `Sources/Pointer/main.swift` parses `--smoke` and
  `--benchmark-gestures` (with `--format json`) and dispatches to the
  `PointerAppKit` diagnostics before the interactive branch calls
  `let composition = PointerCompositionRoot.make()` and then calls
  `composition.application.run()`. The local `composition` must remain alive
  for the entire blocking run. A separate
  `PointerCompositionTests` test target depends directly on
  `PointerComposition`, `PointerAppKit`, and XCTest, and never imports or
  links the top-level `Pointer` executable.
  The existing `PointerAppKitTests` target remains the home of AppKit and
  diagnostic tests and does not own composition tests. The target graph and
  canonical `Tests/PointerCompositionTests/PointerCompositionRootTests.swift`
  construction test must compile this topology from a clean checkout.
- `scripts/verify.sh` must invoke the built executable's `--smoke --format
  json` branch, and `scripts/benchmark-gestures.sh` must invoke its
  `--benchmark-gestures --format json` branch. Their contract tests assert that
  both branches return without constructing `PointerComposition`; the
  no-argument path alone constructs the interactive application.
- `PointerCompositionRoot.make()` returns a public, `@MainActor`
  `PointerComposition` container—not only an `NSApplication`. The container
  exposes `application`, `controller`, and protocol/concrete identity views for
  screen provider, display coordinator, command router, palette, menu bar,
  `ControlMetadataProvider`, `GuidePlacementProvider`, `GuideAssetCatalog`,
  guide, guide asset catalog, guide state store, shortcut controller,
  `HotKeyRegistering`,
  `ShortcutScheduling`, and `NotificationCenter`; it exposes no global lookup
  and owns the same instances passed into the controller/application. The
  canonical construction test asserts concrete types and object identity for
  every connection, verifies the guide and both persistent stores are
  injected, proves
  `composition.application === (PointerApplication.shared as! PointerApplication)`,
  and proves the CLI diagnostic path does not construct this container. It
  holds weak probes for the controller, guide, stores, and coordinator while a
  retained composition is alive using `withExtendedLifetime(composition)`;
  the source-level launcher check proves that same strong local remains alive
  through `composition.application.run()` and is releasable afterward.

  Its mechanically testable public shape is equivalent to:

  ```swift
  @MainActor
  public struct PointerComposition {
      public let application: PointerApplication
      public let controller: PointerApplicationController
      public let screenProvider: any ScreenProviding
      public let displayCoordinator: DisplayCoordinator
      public let commandRouter: CommandRouter
      public let palette: any PalettePresenting
      public let menuBar: (any MenuBarPresenting)?
      public let controlMetadataProvider: any ControlMetadataProviding
      public let guidePlacementProvider: any GuidePlacementProviding
      public let guideAssetCatalog: any GuideAssetCatalogProviding
      public let guide: any FirstUseGuidePresenting
      public let guideStateStore: any FirstUseGuideStateStoring
      public let shortcutController: HotKeyController
      public let shortcutStore: any ShortcutStoring
      public let hotKeyRegistrar: any HotKeyRegistering
      public let shortcutScheduler: any ShortcutScheduling
      public let notificationCenter: NotificationCenter
  }
  ```
- `Sources/PointerComposition/PointerCompositionRoot.swift` is the sole
  production composition root. `PointerCompositionRoot.make() ->
  PointerComposition` first obtains the one application instance as
  `PointerApplication.shared as! PointerApplication`, then constructs the
  concrete screen provider, display
  coordinator, command router, palette, `ControlMetadataProvider`,
  `GuidePlacementProvider`, `GuideAssetCatalog` decoded from the tracked
  `GuideAssetIdentity.json`, menu bar, Carbon registrar, scheduler,
  `NotificationCenter.default`, termination action,
  `UserDefaultsShortcutStore` using `UserDefaults.standard`, shortcut
  controller, D's guide using the injected catalog, and
  `UserDefaultsFirstUseGuideStateStore` using the same explicitly chosen
  defaults object, then wires that singleton
  `PointerApplication` through C's application protocols and returns the
  inspectable container. The construction test asserts all dependencies are
  present and connected, guide construction leaves mode, selected tool, and
  canvas selection unchanged, provider/catalog identities are the same
  instances wired into palette/guide placement/guide rendering, and no store,
  registrar, scheduler, provider, catalog,
  or guide is discovered implicitly.
- Production `PointerApplicationController` and `HotKeyController` expose only
  dependency-injected construction. If a no-argument convenience initializer
  is retained, it is test-support-only and unavailable to the production
  target. A source-level gate scans production `Sources/**` and fails if it
  finds `UserDefaults.standard`, `UserDefaults(suiteName:)`, a default
  `UserDefaults` argument, or a production no-argument controller/store
  construction outside `PointerCompositionRoot.swift`. The same source-level
  check permits `UserDefaults.standard`, `NotificationCenter.default`, and
  the production termination closure only in that composition root.
- The clean-clone gate runs the literal documented build/run and verifier from
  a fresh scoped directory with no untracked assets, local paths, or inherited
  build products. It must prove that the Release bundle contains the same
  tracked resources and that deterministic smoke can run before any live
  window is opened.
- A person directly uses the built app through the complete matrix: launch in
  standby; toggle annotation; create every mark type; select, move, resize,
  delete, undo, clear, and swept-erase; use emoji and spotlight; drag and
  re-show the palette; use Escape and the menu bar; change and recover the
  shortcut; and repeat the common arrow path without unnecessary clicks.
- The manual first-use guide matrix runs from fresh, isolated app defaults and
  covers every entry/exit path: (1) first successful launch after the palette
  is ready shows the guide while recording the exact mode, selected tool,
  shortcut, canvas state, and `GuidePlacementContext` display/visible-frame,
  palette-frame, and avoidance-frame values; the guide is visibly clamped to
  that context without overlap; (2) Close/Done dismisses it without changing any
  of those values and leaves the palette usable; (3) `Learn Pointer` reopens
  it and Close/Done plus Escape each dismiss it without mutation; (4) an
  explicit mode/tool/shortcut action that begins annotation dismisses it, but
  only that explicit command may change mode/tool and the guide never captures
  the CanvasView gesture; (5) a subsequent refresh/relaunch does not show it
  automatically after dismissal; and (6) the guide can be reopened while in
  standby without changing mode/tool and can be dismissed before drawing.
  The same run records live `CanvasView` proof: explicitly select a committed
  mark, enter standby, and verify selection is cleared while the mark and undo
  history remain, selection chrome/handles and contextual Delete are absent;
  re-enter annotation and verify it still starts unselected; then explicitly
  select the mark again before handles and Delete appear. The same run enables
  VoiceOver and records each example's spoken
  name/description, Close/Done and Escape dismissal, and focus returning to
  the palette or CanvasView with no hidden guide element left in the focus
  order. Offscreen renderer or deterministic accessibility metadata cannot
  close this live row. With the guide visible or pending, the manual run then
  removes all displays, verifies the guide hides without a seen-state,
  mode/tool, or canvas mutation and leaves no orphan panel, reconnects a
  display, verifies successful palette show precedes guide restoration, and
  confirms the prior guide intent is restored exactly once. A deliberate
  same-process application stop/start then clears any remaining display-loss
  intent, hides the guide without marking it seen, and verifies restart follows
  normal seen/unseen first-use rules rather than restoring stale guide state.
- F performs a host-capability preflight before physical use and writes under
  `.codex/sdd/reports/quality-campaign/final/**` a mandatory evidence-ledger
  row for every supported case with host/model,
  macOS/Xcode, connected displays and relevant permissions, date/time, exact
  steps, result, and evidence path. A capable host is required for the case:
  two-display cases require two connected displays, VoiceOver cases require
  VoiceOver, and full-screen/reconnect cases require those capabilities. A
  supported case that is capable but untested, failed, or missing any ledger
  field keeps the goal active; it cannot be marked "not applicable" or inferred
  from deterministic evidence. If the current host lacks a required capability,
  the coordinator must obtain a capable host or report the goal incomplete.
- F writes a `ChromeFrictionReport` with baseline/candidate identities,
  persistent control count, palette row count, always-visible status count,
  focus-stop count, required common-path clicks/keys/steps, additions,
  removals, and disposition. Completion requires at least one persistent
  dimension to decrease, no increase in any persistent dimension, and no
  increase in required common-path interaction; a missing inventory or a net
  increase keeps the campaign in `REVISE`.
- Where hardware and host state allow, the manual matrix also covers two
  connected displays, pointer-display palette placement, per-display marks,
  full-screen Spaces, display disconnect/reconnect, no-display transitions,
  shortcut conflict/fallback/relaunch, denied privacy permissions, VoiceOver,
  keyboard-only operation, Reduce Transparency, Increase Contrast, and a
  long session. Unsupported physical cases are recorded as exact gaps, never
  inferred as passes.
- Each finding in the campaign ledger includes reproduction, evidence class,
  severity, owner, fix, reviewer result, adversarial result, and verification.
  Blockers and high-severity interaction/accessibility failures cannot be
  waived as polish. Lower-severity findings require a stated reason and a
  follow-up boundary if they remain.
- The final report distinguishes current-host proof, deterministic proof, and
  unverified platform claims. It does not claim support for DRM, secure UI,
  lock screen, future WindowServer behavior, or unsupported hardware.

## Required review and reconciliation loop

Every workstream follows the same evidence-gated loop:

1. The configured Luna worker subagent is mandatory for every workstream. It
   reads this design, the current code, local instructions, and the current
   shared status; implements only its owned scope; writes focused tests or
   evidence; and reports files, checks, known gaps, and scope pressure.
2. A separate configured Luna reviewer subagent is also mandatory for every
   worker. It receives the worker's diff and evidence read-only and checks the
   user-facing behavior, architecture boundaries, accessibility, error
   handling, security/permission constraints, and overbuilding controls. It
   returns `REVISE` with exact findings or `APPROVED` only when the result is
   genuinely impressive and supported by current evidence; a green unit test
   alone is not approval.
3. If the configured Luna worker or reviewer is unavailable, the coordinator
   stops that workstream and reports the exact availability failure. It must
   obtain explicit authorization before using another model or doing the work
   inline; silently substituting a model, reviewer, or evidence standard is
   prohibited.
4. After reviewer approval, an adversarial Codex pass re-reads the original
   objective and this design, challenges the acceptance interpretation, probes
   edge cases and unsupported claims, and runs the narrowest useful checks. It
   is specifically looking for regressions, missing affordances, test seams
   that diverge from production, accessibility omissions, and scope creep.
5. Any adversarial finding returns to the original worker. The worker revises
   within its scope; the reviewer rechecks; Codex rechecks. The loop continues
   until worker, reviewer, and adversarial Codex findings reconcile. A finding
   is not closed by relabeling it, moving it to another workstream, or claiming
   that the test harness cannot see it.
6. The coordinating agent integrates only reconciled workstreams, reruns the
   cross-workstream checks, and records the exact evidence. No worker pushes,
   publishes, resets, or cleans the primary dirty checkout.

If a worker discovers that its change requires another scope, it stops at the
interface and reports the dependency. The coordinating agent assigns the
smallest explicit follow-up; workers do not broaden their write scope.

## Overbuilding controls

- Preserve the current `PointerCore`/`PointerAppKit`/`Pointer` architecture;
  do not replace native AppKit controls with a new framework or design system
  without a measured product problem.
- Prefer deletion, contextual visibility, native SF Symbols, native menus,
  and existing command/model seams before adding controls, files, assets,
  dependencies, or settings.
- Every new control or visual asset must state the user problem it solves, the
  common path it affects, and why an existing affordance cannot solve it. If
  it is not needed during a presentation, it belongs behind an explicit help
  or menu action.
- Keep the default palette compact and the standby surface calm. Additions are
  expected to be offset by removing persistent or redundant chrome. The
  before/after inventory must show no net persistent complexity or common-path
  friction increase; a contextual control is not permission to add permanent
  chrome.
- Do not add saved-state, distribution, analytics, network, or permission
  infrastructure under the name of polish.
- Do not claim a performance improvement without before/after measurements from
  the same production path and fixture. Prototype-only numbers remain
  prototype evidence.
- Keep deterministic seams on the same command and validation routes as the
  app. Do not add global event monitors, Quartz event taps, input synthesis,
  screen capture, or accessibility workarounds to make automation easier.
- Preserve all unrelated dirty files and generated artifacts outside the
  stable-app worktree. No destructive cleanup is part of this campaign.

## Completion audit

The goal is complete only after the coordinating agent performs a fresh,
requirement-by-requirement audit against this design and the original request.
The audit must show:

| Original requirement | Required proof before completion |
| --- | --- |
| Use the app extensively | Direct/manual matrix for every supported tool, mode, editing action, palette flow, shortcut path, and available display/Space condition, with exact untestable gaps |
| Find confusing, ugly, missing, inconsistent, costly, inaccessible, slow, and edge-case behavior | Reviewed issue ledger with reproduction and disposition; no unresolved blocker/high-severity item; a second fresh audit finds no meaningful new issue or reopens the loop |
| Fix the findings | Diff plus focused regression test or direct evidence for each accepted finding; no symptom-only workaround where a root-cause fix is in scope |
| Preserve executable composition and injection | F's `Package.swift` target graph proves `PointerComposition` and `PointerAppKit` are directly importable by `PointerCompositionTests` without tests importing the executable, while `Pointer` preserves pre-composition `--smoke`/`--benchmark-gestures` diagnostic dispatch; canonical `Tests/PointerCompositionTests/PointerCompositionRootTests.swift` proves the sole factory injects every production dependency, `ControlMetadataProvider`, `GuidePlacementProvider`, `GuideAssetCatalogProviding`, `UserDefaultsShortcutStore`, guide store, registrar, and scheduler, uses `PointerApplication.shared as! PointerApplication`, and keeps the graph alive through `let composition` and `application.run()` |
| Preserve phase ownership and ordering | The reconciled graph is exactly `A-foundation → B-core → C → D → B-render-integration → A-harness → E → F`; CanvasView gesture/cursor edits remain B-core-owned, draw/RenderPlan consumption is B-render-owned, real integrated views are A-harness-owned, and no downstream phase starts before its upstream gate |
| Preserve marks and control through mode/display lifecycle | B's `DisplayCoordinator.stop()`/`DisplayStopResult` plus deterministic standby, zero-display, and same-process running/stopped/restarted checkpoints prove entering standby clears selection while retaining marks/undo/shortcut/menu-bar state, hidden standby selection chrome, exact-once hotkey rebinding, bounded running counts, zero stop cleanup, cleared handlers, fresh-overlay restart/no closed-panel reuse, observer/timer release, distinct non-committing display-loss versus application-stop guide cleanup, palette hide, and duplicate-free reconnect/restart restoration |
| Preserve geometric boundary behavior | B's inclusive/epsilon hit-testing suite covers collinear overlap, endpoint/tangent contact, rectangle-edge and arrow-endpoint regressions, and just-outside misses |
| Prove standby rendering rather than only model state | D's offscreen `MarkRenderer`/RenderPlan check, B-render-integration's real CanvasView draw test, A-harness convergence proof, palette affordance test, and F's live built-app CanvasView manual proof all agree that marks remain visible while standby selection/handles/Delete stay absent and explicit re-selection is required |
| Make actions teachable and operable | B's CanvasView cursor tests plus manual/deterministic proof for explicit mode/tool feedback, empty-canvas deselection, contextual Delete, keyboard routing, VoiceOver semantics, and contrast/transparency states |
| Add images and icons that support learning | Tracked `AppIcon.appiconset` plus `AppIconIdentity.json` compiled to `Assets.car`, exact Launch Services bundle URL and real AppIcon marker/digest proof using canonical 512×512 sRGB RGBA8 alpha-normalized SHA-256 pixels, injected `GuideAssetCatalogProviding` decoded from exact `GuideAssetIdentity.json`, all tool/example variants/source hashes/accessibility flags resolved in compiled `Assets.car`, idempotent tracked-resource/bundle manifest comparison, correct `CFBundleIconName`, executable `IconResolutionProbe.swift`, coherent tool icons, compact visual first-use guide, dark/light/contrast checks, accessible descriptions, and proof that the common path gained no unnecessary click |
| Make first-use support safe and reversible | Fresh-defaults manual matrix proves guide show only after successful palette show, first-display retry after zero-display startup, visible-panel-before-seen marking, non-committing display-loss hide and reconnect restore after palette show, distinct application-stop intent clearing with normal seen/unseen restart rules, no orphan panel/seen mutation/mode-tool mutation, Close/Done, reopen, Escape, annotation-triggered dismissal, no automatic reappearance, no CanvasView interference, deterministic guide metadata, and live VoiceOver evidence |
| Add delight while removing more than adding | User-facing diff review showing contextual feedback or micro-details with a clear job, removal/collapse of redundant chrome, and no net increase to common-path friction |
| Keep iterating until meaningful improvements are hard to find | Worker/reviewer/Codex reconciliation records plus a final adversarial pass with no unresolved meaningful finding; remaining lower-severity items are explicit and bounded |
| Prove performance and resource health | Variant `PerformanceMeasurementReport` plus paired `PerformanceComparisonReport` under the separate performance measurement/comparison paths, immutable commit/content-manifest identities, fixed paired A/B measurements and bootstrap rule, required model/renderer/compositor/combined-frame/launch/allocation/redraw-layout/responsiveness/input-to-visible/memory schemas with measured statuses, memory phase/window/sample/RSS-series/aggregate/peak/final-delta/matched-baseline/resource-count fields, running-only plateau validation plus separate stop/restart checkpoints, frame/input budgets, leak validation, and `REVISE` plus completion block for missing, failed, or unmeasured metrics |
| Complete supported physical evidence | A capable-host preflight and mandatory host/date/steps/result/evidence ledger covers every supported physical case; any capable but untested or failed case keeps the goal active |
| Preserve validation, security, accessibility, architecture, and scope | Full verifier, Release bundle, clean-clone, manual, keyboard/VoiceOver, appearance, permission, performance, and boundary checks; no new forbidden dependency, permission, or production import |
| Preserve project boundaries | Stable-app-only diff, untouched primary dirty README/`graphify-out`, no unapproved commit/push/publication, and a clean final status for the campaign-owned paths |

An unchecked or indirect row means the goal remains active. The campaign must
continue from the highest-value unresolved evidence gap rather than being
declared complete because the automated suite is green.
