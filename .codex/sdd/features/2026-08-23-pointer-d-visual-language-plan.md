# Pointer D — Visual Language and Learning Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking. The coordinating agent owns commits and publication; worker tasks end with evidence/status handoff instead of commit steps.

**Goal:** Add a distinctive compiled app icon, a compact accessible first-use guide, and a coherent visual language while reducing persistent chrome and preserving normalized mark readability.

**Architecture:** Implement the concrete guide behind C's FirstUseGuidePresenting protocol with an injected state store and non-modal panel. Define public top-level RenderPlan and HandleInventory values in standalone Rendering files; B wires them through CanvasView only in its D-gated render-integration phase, and A consumes them only in its later Harness phase.

**Tech Stack:** Swift tools 5.10, macOS 14+, AppKit, CoreGraphics, PointerCore, PointerAppKit, XCTest, PNG raster assets, actool.

**Spec:** .codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md (Workstream D and its C/F interfaces).

## Global Constraints

- The campaign improves the current annotation product. It does not broaden the product into a document or distribution platform.
- D implements the guide against C's FirstUseGuidePresenting interface and never imports or edits C's composition/controller code.
- D implements the guide against C's `GuidePresentationResult` return contract:
  `.shown` is returned only after the panel is visible, `.notNeeded` when no
  presentation is required, and `.failed(String)` when a request cannot be
  fulfilled. C retains pending intent on failures, so D must not report
  `.shown` for an order-front request that remains hidden.
- C may ask for a later retry after an explicit Learn Pointer request or a
  display change; D receives the fresh `GuidePlacementContext` supplied by C
  and must not assume a cached display or palette frame.
- The guide appears once after successful palette show, reopens from Learn Pointer, dismisses with Close/Done or Escape, and never changes mode, tool, selection, or canvas.
- Display-loss hiding is non-committing; application-stop cleanup clears restoration intent without marking the guide seen.
- Informative icons/examples have accessible names and descriptions; decorative art is hidden; focus order teaches the task.
- Local raster assets must compile through actool into Assets.car with CFBundleIconName=AppIcon; raw xcassets copying is not success.
- Preserve normalized geometry, stroke/opacity, click-through, selection handles, one-spotlight behavior, and standby mark visibility. Persistent complexity must not increase and at least one persistent dimension must decrease.
- Work only in /Users/bruno/Dev/pointer/.worktrees/stable-app; preserve unrelated dirty files and generated artifacts in /Users/bruno/Dev/pointer.
- D owns Sources/PointerAppKit/Rendering/RenderPlan.swift, Sources/PointerAppKit/Rendering/HandleInventory.swift, MarkRenderer.swift, Bundle/Assets.xcassets/**, Bundle/AppIconIdentity.json, its concrete Help implementation/catalog files listed below, RenderPlanTests.swift, FirstUseGuideTests.swift, and visual/accessibility snapshot tests/resources; D consumes the C-predeclared `Sources/PointerAppKit/Help/FirstUseGuideStateStoring.swift` seam and does not redeclare or extend it. It does not edit A's Support/** or Harness/** or other workstreams.

---

## Interfaces

D's public top-level RenderPlan and HandleInventory are consumed by B's CanvasView follow-up, not drawn only in a D test. After D accepts them, B wires CanvasView.renderPlan and the live draw sequence: session update or gesture boundary -> preview canvas/mode/selection/active draft -> RenderPlan.make(...) -> CanvasView.renderPlan -> CanvasView.draw(_:) -> MarkRenderer.draw(plan:in:context:). A's later Harness phase consumes the same values for deterministic inventory assertions; C and F consume only the guide protocol. D does not edit B's CanvasView.

    // Existing C-predeclared seam consumed by D:
    // Sources/PointerAppKit/Help/FirstUseGuideStateStoring.swift
    @MainActor
    public protocol FirstUseGuideStateStoring: AnyObject {
        var hasDismissedFirstUseGuide: Bool { get }
        func markFirstUseGuideDismissed()
    }

    public enum GuideAssetVariant: String, CaseIterable, Codable, Sendable {
        case light
        case dark
        case highContrast
    }

    public struct GuideAssetVariantDescriptor: Codable, Equatable, Sendable {
        public let variant: GuideAssetVariant
        public let assetIdentifier: String
        public let sourceSHA256: String
    }

    public struct GuideAssetDescriptor: Codable, Equatable, Sendable {
        public let id: String
        public let accessibleName: String
        public let accessibleDescription: String
        public let isDecorative: Bool
        public let variants: [GuideAssetVariantDescriptor]
    }

    public struct GuideAssetCatalogEnvelope: Codable, Equatable, Sendable {
        public let schemaVersion: Int
        public let entries: [GuideAssetDescriptor]
    }

    @MainActor
    public protocol GuideAssetCatalogProviding: AnyObject {
        var entries: [GuideAssetDescriptor] { get }
        func image(for identifier: String, variant: GuideAssetVariant) throws -> NSImage
    }

    @MainActor
    public final class GuideAssetCatalog: GuideAssetCatalogProviding {
        public let entries: [GuideAssetDescriptor]
        public init(envelope: GuideAssetCatalogEnvelope, bundle: Bundle)
        public func image(for identifier: String, variant: GuideAssetVariant) throws -> NSImage
    }

    public enum GuideAssetSourceMapping {
        public static func sourcePath(for assetIdentifier: String,
                                     variant: GuideAssetVariant) -> String
    }

    @MainActor
    public init(userDefaults: UserDefaults, key: String)

    @MainActor
    public final class FirstUseGuideController: FirstUseGuidePresenting {
        public let placementProvider: any GuidePlacementProviding
        public let assetCatalog: any GuideAssetCatalogProviding
        public init(stateStore: any FirstUseGuideStateStoring,
                    placementProvider: any GuidePlacementProviding,
                    assetCatalog: any GuideAssetCatalogProviding)
    }

    D consumes the C-owned FirstUseGuidePresenting declaration unchanged; D does
    not redeclare, extend, or add an assetCatalog requirement to that protocol.
    assetCatalog is read-only only on this concrete FirstUseGuideController and
    is not visible through C's catalog-agnostic interface.

    @MainActor
    internal protocol FirstUseGuidePanel: AnyObject {
        var isVisible: Bool { get }
        func show(in context: GuidePlacementContext, onVisible: @escaping () -> Void)
        func close()
    }

    @MainActor
    internal init(stateStore: any FirstUseGuideStateStoring,
                  placementProvider: any GuidePlacementProviding,
                  assetCatalog: any GuideAssetCatalogProviding,
                  panelFactory: @escaping (GuidePlacementContext) -> any FirstUseGuidePanel)

    public struct SelectionInventory: Equatable, Sendable {
        public let selectedMarkID: Mark.ID?
        public let isVisible: Bool
    }

    public struct HoverInventory: Equatable, Sendable {
        public let hoveredMarkID: Mark.ID?
        public let isVisible: Bool
    }

    public struct ResizeInventory: Equatable, Sendable {
        public let handles: [ResizeHandle]
        public let isVisible: Bool
    }

    public struct HandleInventory: Equatable, Sendable {
        public let selection: SelectionInventory
        public let hover: HoverInventory
        public let resize: ResizeInventory
        public let contextualDeleteVisible: Bool
    }

    public struct RenderPlan: Equatable, Sendable {
        public let committedMarks: [Mark]
        public let activeDraft: Mark?
        public let handles: HandleInventory

        public static func make(canvas: Canvas, mode: PointerMode,
                                selectedID: Mark.ID?, activeDraft: Mark?,
                                hover: HoverInventory) -> RenderPlan
    }

    public enum MarkRenderer {
        public static func draw(plan: RenderPlan, in bounds: CGRect, context: CGContext)
    }


## Task 1: Lock standby render-plan and offscreen pixel semantics

**Files:**

- Create: Sources/PointerAppKit/Rendering/RenderPlan.swift
- Create: Sources/PointerAppKit/Rendering/HandleInventory.swift
- Modify: Sources/PointerAppKit/MarkRenderer.swift
- Create: Tests/PointerAppKitTests/RenderPlanTests.swift
- Create: Tests/PointerAppKitTests/VisualFixtures.swift

- [ ] **Step 1: Write failing tests.**

    func testStandbyRenderPlanKeepsMarksButClearsSelectionHoverResizeAndDelete()
    func testAnnotationSelectionRestoresSelectionAndResizeInventory()
    func testOffscreenStandbyPixelsContainMarkButNoHandleSentinel()

The first two tests use the same canonical rectangle fixture and assert the public shape directly:

    let standby = RenderPlan.make(canvas: canvas, mode: .standby,
                                  selectedID: mark.id, activeDraft: mark,
                                  hover: HoverInventory(hoveredMarkID: mark.id, isVisible: true))
    XCTAssertNil(standby.activeDraft)
    XCTAssertNil(standby.handles.selection.selectedMarkID)
    XCTAssertFalse(standby.handles.selection.isVisible)
    XCTAssertNil(standby.handles.hover.hoveredMarkID)
    XCTAssertFalse(standby.handles.hover.isVisible)
    XCTAssertTrue(standby.handles.resize.handles.isEmpty)
    XCTAssertFalse(standby.handles.resize.isVisible)
    XCTAssertFalse(standby.handles.contextualDeleteVisible)

    let annotation = RenderPlan.make(canvas: canvas, mode: .annotation,
                                     selectedID: mark.id, activeDraft: nil,
                                     hover: HoverInventory(hoveredMarkID: mark.id, isVisible: true))
    XCTAssertEqual(annotation.handles.selection.selectedMarkID, mark.id)
    XCTAssertTrue(annotation.handles.selection.isVisible)
    XCTAssertFalse(annotation.handles.resize.handles.isEmpty)
    XCTAssertTrue(annotation.handles.resize.isVisible)

Create a 512 x 512 sRGB RGBA8 bitmap with bounds (0,0,512,512). The canonical rectangle is normalized (x: 0.25, y: 0.25, width: 0.5, height: 0.5), so its centerline edges are x/y 128 and 384; use the default red 4-point stroke. Assert alpha > 0 at (256,128) and (128,256), alpha == 0 at (256,120) and (120,256), and no white/black handle sentinel within a 9-pixel radius of (128,128), (384,128), (128,384), and (384,384), with a one-pixel coordinate tolerance. Record the resulting standby bitmap's lowercase 64-character SHA-256 as the literal expectedStandbyDigest in VisualFixtures.swift; the test must compare bytes to that literal rather than compute its expected value from the candidate at runtime.


- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RenderPlanTests

Expected: the public top-level RenderPlan, HandleInventory, and mode-aware draw path are missing.

- [ ] **Step 3: Implement the plan.**

RenderPlan.make uses the supplied selection, hover, and active draft; any mode other than annotation, including standby, discards the draft so activeDraft is nil. Standby retains committed marks and sets selection.selectedMarkID/isVisible, hover.hoveredMarkID/isVisible, resize.handles/isVisible, and contextualDeleteVisible to empty/false. Annotation restores only explicit selection and a supplied hover target. MarkRenderer.draw(plan:) draws committed marks, then an annotation draft, then only the inventory's visible resize handles. Keep normalized mapping and style/opacity unchanged.

- [ ] **Step 4: Run GREEN and appearance fixtures.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'RenderPlanTests|MarkRendererTests|CanvasViewTests'

Expected: light/dark, Increase Contrast, Reduce Transparency, dense-canvas, selected/unselected, narrow/wide, and full-screen-content fixtures pass; record bitmap digest.

Handoff to the coordinator is the accepted public RenderPlan/HandleInventory signatures, the fixed bitmap geometry/coordinates/tolerance/literal digest, and the exact CanvasView sequence for the separate B-render-integration phase. D does not edit CanvasView or claim the live draw path is complete until that B phase passes.

## Task 2: Implement injected first-use storage and guide state machine

**Files:**

- Existing/Consume: Sources/PointerAppKit/Help/FirstUseGuideStateStoring.swift
- Create: Sources/PointerAppKit/Help/UserDefaultsFirstUseGuideStateStore.swift
- Create: Sources/PointerAppKit/Help/FirstUseGuideController.swift
- Create: Sources/PointerAppKit/Help/FirstUseGuideViewController.swift
- Create: Sources/PointerAppKit/Help/GuideAssetCatalog.swift
- Create: Tests/PointerAppKitTests/FirstUseGuideTests.swift
- Create: Tests/PointerAppKitTests/FirstUseGuideTestFixtures.swift

- [ ] **Step 1: Write failing tests.**

    func testFailedOrHiddenPanelDoesNotMarkGuideSeen()
    func testVisiblePanelMarksSeenOnlyAfterOrderFrontCallback()
    func testCloseDoneAndEscapeDismissWithoutModeToolOrCanvasMutation()
    func testDisplayLossHideAndReconnectRestoreOnceAfterPaletteShown()
    func testApplicationStopClearsDisplayLossIntentWithoutSeenMutation()
    func testSeenAndUnseenRestartRulesDoNotAutomaticallyReopenDismissedGuide()
    func testGuidePlacementProviderReceivesDisplayFramesAndClamps()
    func testEveryGuideExampleResolvesThroughInjectedCatalog()
    func testGuideProtocolIsDeclaredOnlyInCAndConcreteCatalogStaysDLocal()

Use exact test-only types from FirstUseGuideTestFixtures.swift: FirstUseGuideTestStateStore conforms to FirstUseGuideStateStoring; FirstUseGuideTestCatalog conforms to GuideAssetCatalogProviding and records image(for:variant:) calls; FirstUseGuideTestPanel conforms to FirstUseGuidePanel, records show/visible/close events, and asserts the received GuidePlacementContext.display identity; FirstUseGuideTestFixture owns the isolated UserDefaults suite, state store, catalog, panel, and controller factory. Assert no orphan panel and no mode/tool/selection/canvas mutation.

- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests

Expected: missing protocol, state store, controller, view controller, and test panel seam.

- [ ] **Step 3: Implement the minimal state machine.**

FirstUseGuideController implements the C-owned FirstUseGuidePresenting protocol without redeclaring or extending it. It requires the injected GuideAssetCatalogProviding and exposes that catalog only through its concrete read-only assetCatalog property; C's protocol remains catalog-agnostic. It resolves every example image only through assetCatalog.image(for:variant:), and never performs a named-image lookup, bundle fallback, UserDefaults lookup, or default catalog construction. It consumes the C-owned GuidePlacementProviding identity and exposes it through placementProvider. showIfNeeded(in:)/show(in:)/restoreAfterDisplayLoss(in:) receive GuidePlacementContext containing visibleFrame, paletteFrame, and avoidanceFrames; D positions the panel inside the supplied visibleFrame while avoiding every supplied frame, without requiring C to supply a list of future guide obstacles or known guide frames. The controller requests a panel and marks the store only after the panel is visible/order-front, returning `.shown` only then and `.failed(String)` otherwise. dismiss clears transient intent and orders out. hideForDisplayLoss records visible/pending intent without committing; restore restores exactly once; hideForApplicationStop clears that intent and does not commit.

The source-contract test resolves paths from #filePath and asserts exactly one
FirstUseGuidePresenting protocol declaration in
`Sources/PointerAppKit/Help/FirstUseGuidePresenting.swift`, no protocol
declaration or extension in D's Help sources, exactly one
FirstUseGuideStateStoring declaration in
`Sources/PointerAppKit/Help/FirstUseGuideStateStoring.swift`, no state-store
protocol declaration or extension in D's Help sources, and `assetCatalog`
appears only on the concrete D controller/catalog implementation—not on either
protocol or C controller.

- [ ] **Step 4: Implement guide panel and accessible examples.**

Show Arrow, Rectangle, Ellipse, Pen, Spotlight, Emoji, Select, and Eraser icons plus one concise explanation and essential shortcut. Focus order is title, explanation, example/name/description, shortcut, Close/Done. Decorative art has accessibilityElementsHidden=true; every informative image has an accessibility label/help.

- [ ] **Step 5: Run GREEN.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests

Expected: all controller, focus-order, metadata, failure, display-loss, stop, Close/Done, Escape, state-isolation, deterministic placement/avoidance, and injected-catalog image-resolution tests pass. F's manual matrix separately verifies guide placement beside the palette without covering a presentation target.

## Task 3: Add tracked app icon and guide raster assets

**Files:**

- Create: Bundle/Assets.xcassets/AppIcon.appiconset/Contents.json
- Create: Bundle/Assets.xcassets/AppIcon.appiconset/*.png
- Create: Bundle/Assets.xcassets/FirstUseGuide/*.imageset/Contents.json
- Create: Bundle/Assets.xcassets/FirstUseGuide/*.png
- Create: Bundle/AppIconIdentity.json
- Create: Bundle/GuideAssetIdentity.json
- Create: Tests/PointerAppKitTests/AssetIdentityTests.swift

- [ ] **Step 1: Add failing manifest tests.**

    func testAppIconIdentityNamesExactAssetAndRasterPolicy()
    func testGuideAssetsHaveCanonicalIdentifiersAndTrackedFiles()
    func testEveryGuideExampleLoadsItsMappedRasterWithNSImageNamed()

Expected: missing asset catalog/identity manifest, GuideAssetCatalog entries/mapping, or direct source-PNG loads fail.

- [ ] **Step 2: Create raster assets with exact manifest fields.**

AppIconIdentity.json must name AppIcon, SHA-256 every source PNG, canonical dimensions, sRGB color space, straight-alpha policy, marker pixel coordinate/RGBA, and expected resolved-icon digest. GuideAssetCatalog.swift and Bundle/GuideAssetIdentity.json use the GuideAssetCatalogEnvelope schemaVersion/entries envelope and define every example entry with GuideAssetDescriptor.id/accessibleName/accessibleDescription/isDecorative/variants. Every descriptor has exactly light, dark, and highContrast GuideAssetVariantDescriptor entries with variant/assetIdentifier/sourceSHA256 only. Source paths and dimensions are derived by the deterministic GuideAssetSourceMapping for each assetIdentifier/variant and inspected from the source PNG, never serialized in the JSON envelope. The catalog's tracked source mapping must equal the local PNGs below Bundle/Assets.xcassets/FirstUseGuide; guide assets must have no SVG or network reference.

- [ ] **Step 3: Run asset tests and inspect catalogs.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'AssetIdentityTests|FirstUseGuideTests'

Expected: PASS for tracked files, dimensions, color space, alpha policy, canonical mapping, and accessible guide asset references. AssetIdentityTests iterates every GuideAssetDescriptor and every GuideAssetVariantDescriptor, asserts all example IDs are present, accessibleName/accessibleDescription are nonempty for informative entries, isDecorative is explicit, derives each source PNG path with GuideAssetSourceMapping, verifies source SHA-256 against sourceSHA256, and inspects dimensions/pixels with CGImageSourceCreateWithURL (or NSImage(contentsOf:)). It fails if a tracked guide PNG is unused or a variant is missing. It does not use compiled asset names; F validates the injected catalog implementation after actool.

## Task 4: Prove deletion and common-path friction reduction

**Files:**

- Modify: Tests/PointerAppKitTests/RenderPlanTests.swift
- Modify: Tests/PointerAppKitTests/FirstUseGuideTests.swift
- Create: Tests/PointerAppKitTests/ChromeFrictionTests.swift

- [ ] **Step 1: Write failing inventory tests.**

    func testCandidatePersistentChromeDoesNotIncreaseAndOneDimensionDecreases()
    func testFreshLaunchArrowDrawStandbyPathNeedsNoAdditionalClickOrKey()

Inventory always-visible control count, palette rows, status elements, focus stops, required clicks/keys/steps, additions, and removals. Require no persistent dimension increase, at least one decrease, and no common-path interaction increase.

- [ ] **Step 2: Run RED, then implement deletion/collapse.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ChromeFrictionTests

Remove redundant permanent labels/status/chrome where contextual state or a tooltip does the job; retain accessible names and relevant feedback. Do not hide essential keyboard controls merely to lower counts.

- [ ] **Step 3: Run GREEN and hand inventory to F.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'ChromeFrictionTests|FirstUseGuideTests|RenderPlanTests'

Expected: PASS and a concrete baseline/candidate inventory for F's ChromeFrictionReport.

## Task 5: Reconciliation gate

- [ ] **Step 1:** Run git diff --check and confirm only D-owned paths changed.
- [ ] **Step 2:** Run DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test; record renderer digests, guide metadata, asset hashes, and friction inventory.
- [ ] **Step 3:** Send worker diff/evidence to the configured Luna reviewer; reviewer returns REVISE with exact findings or APPROVED only with visual, accessibility, state, and scope evidence.
- [ ] **Step 4:** After approval, adversarial Codex re-reads the design and probes standby pixels, selection restoration, asset identity, guide seen-state timing, display loss/stop distinction, accessibility descriptions, dark/light/contrast, common-path clicks, and scope creep.
- [ ] **Step 5:** Return every finding to the smallest D-owned file, rerun RED/GREEN checks, obtain reviewer approval, and repeat Codex review until status is RECONCILED.

## Plan self-check

Render semantics, guide interfaces/state, accessible examples, tracked raster assets, app icon manifest, friction reduction, and visual verification are covered. No task edits C composition, F build scripts, B lifecycle, A diagnostics, or E performance files; no commit step is present.
