# Pointer F — Integration, Composition, Manual Use, and Completion Evidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking. The coordinating agent owns commits and publication; worker tasks end with evidence/status handoff instead of commit steps.

**Goal:** Prove the reconciled Pointer product through its real package graph, Release bundle, deterministic CLI, clean-clone gate, manual interaction matrix, and evidence-led completion report.

**Architecture:** Add importable PointerComposition with the sole dependency-injected factory and keep Pointer as a minimal diagnostic dispatcher/interactive launcher. Build tracked Info.plist/assets through actool, validate exact icon resolution and idempotence, run the full Swift/Release/smoke/benchmark gate, and write final evidence under the F-owned report subtree.

**Tech Stack:** Swift tools 5.10, macOS 14+, SwiftPM, AppKit, Carbon, XCTest, xcodebuild/swift/actool/assetutil/Launch Services, shell scripts, GitHub Actions, Markdown evidence ledgers.

**Spec:** .codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md (Workstream F and completion audit).

## Global Constraints

- PointerComposition depends on PointerCore and PointerAppKit and is usable by composition tests without importing the executable.
- Pointer parses --smoke/--format json and --benchmark-gestures/--format json before composition; only the no-flag path calls PointerCompositionRoot.make().
- Every tracked bundle resource, including AppIcon and FirstUseGuide assets, is compiled/copied and validated in Release; raw xcassets copying is not success.
- Evidence distinguishes deterministic proof, current-host physical proof, and unverified platform claims. A capable but untested supported case keeps the goal active; it cannot be marked not applicable.
- The manual matrix covers every supported tool, mode, edit action, palette flow, shortcut path, display/Space condition, guide path, VoiceOver path, appearance state, permission condition, and long session available on the host.
- Work only in /Users/bruno/Dev/pointer/.worktrees/stable-app; preserve the primary checkout's unrelated README/graphify-out and do not reset/clean it.
- F owns Package.swift, Sources/PointerComposition/PointerCompositionRoot.swift, Sources/Pointer/main.swift, Tests/PointerCompositionTests/**, .github/workflows/verify.yml, Bundle/Info.plist, scripts/build-app.sh, scripts/run-app.sh, scripts/verify.sh, scripts/test-clean-clone.sh, Tests/BuildScripts/**, clean-clone/manual harnesses, and .codex/sdd/reports/quality-campaign/final/**. A's Support/Harness test files remain inside the existing PointerAppKitTests target path; F does not add a support target or alter their ownership.
- F consumes A-E accepted interfaces/reports and does not edit their product behavior, performance subtree, shared fixtures, or guide/palette implementation to make integration pass.
- F's final aggregation consumes E's variant reports only from .codex/sdd/reports/quality-campaign/performance/measurements/**, paired reports from comparisons/**, and resilience evidence from resilience/**; F writes links/summaries under final/** and never creates direct-root performance JSON.
- The clean-clone gate is unavailable until the coordinator records a committed campaign source identity containing the reconciled implementation, tests, assets, scripts, and plan/design inputs required by the branch. The current uncommitted plan/design state is a precondition failure, not a clean-clone result.

---

## Interfaces

    @MainActor
    public struct PointerComposition {
        public let application: PointerApplication
        public let controller: PointerApplicationController
        public let screenProvider: any ScreenProviding
        public let displayCoordinator: DisplayCoordinator
        public let commandRouter: CommandRouter
        public let palette: any PalettePresenting
        public let menuBar: (any MenuBarPresenting)?
        public let guide: any FirstUseGuidePresenting
        public let guideAssetCatalog: any GuideAssetCatalogProviding
        public let controlMetadataProvider: any ControlMetadataProviding
        public let guidePlacementProvider: any GuidePlacementProviding
        public let guideStateStore: any FirstUseGuideStateStoring
        public let shortcutController: HotKeyController
        public let shortcutStore: any ShortcutStoring
        public let hotKeyRegistrar: any HotKeyRegistering
        public let shortcutScheduler: any ShortcutScheduling
        public let notificationCenter: NotificationCenter
    }

    @MainActor
    public enum PointerCompositionRoot {
        public static func make() -> PointerComposition
    }

The root obtains PointerApplication.shared as PointerApplication, constructs concrete screen provider, coordinator, router, menu, ControlMetadataInventory, GuidePlacementProvider, an explicit D-owned GuideAssetCatalog(envelope:bundle:) using the tracked GuideAssetIdentity.json and the PointerAppKit resource bundle, then constructs PalettePanel(router:guidePlacementProvider:) with that same provider, Carbon registrar, scheduler, NotificationCenter.default, UserDefaultsShortcutStore with UserDefaults.standard, shortcut controller, D's guide and guide store, then wires provider/store/metadata dependencies into palette/controller and the catalog/provider/store directly into D's guide; the catalog is not passed to C's controller.

## Task 1: Add the importable composition target and canonical identity test

**Files:**

- Modify: Package.swift
- Create: Sources/PointerComposition/PointerCompositionRoot.swift
- Create: Tests/PointerCompositionTests/PointerCompositionRootTests.swift

- [ ] **Step 1: Add failing target-graph and identity tests.**

    @MainActor
    func testCompositionRootExposesEveryInjectedIdentity() {
        let composition = PointerCompositionRoot.make()
        XCTAssertTrue(composition.application === PointerApplication.shared as! PointerApplication)
        XCTAssertTrue(composition.application.commandRouter === composition.commandRouter)
        XCTAssertTrue(composition.application.localKeyRouter === composition.commandRouter)
        XCTAssertTrue(composition.application.firstUseGuide === composition.guide)
        XCTAssertTrue(composition.application.commandRouter === composition.controller.commandRouter)
        XCTAssertTrue(composition.application.firstUseGuide === composition.controller.guide)
        guard let guide = composition.guide as? FirstUseGuideController else {
            return XCTFail("Composition must inject D's FirstUseGuideController")
        }
        XCTAssertTrue(guide.assetCatalog === composition.guideAssetCatalog)
        XCTAssertTrue(composition.controller.screenProvider === composition.screenProvider)
        XCTAssertTrue(composition.controller.displayCoordinator === composition.displayCoordinator)
        XCTAssertTrue(composition.controller.commandRouter === composition.commandRouter)
        XCTAssertTrue(composition.controller.palette === composition.palette)
        XCTAssertTrue(composition.controller.menuBar === composition.menuBar)
        XCTAssertTrue(composition.palette.guidePlacementProvider === composition.guidePlacementProvider)
        XCTAssertTrue(composition.controller.guide === composition.guide)
        XCTAssertTrue(composition.guide.placementProvider === composition.guidePlacementProvider)
        XCTAssertTrue(composition.controller.controlMetadataProvider === composition.controlMetadataProvider)
        XCTAssertTrue(composition.controller.guidePlacementProvider === composition.guidePlacementProvider)
        XCTAssertTrue(composition.controller.guideStateStore === composition.guideStateStore)
        XCTAssertTrue(composition.controller.shortcutStore === composition.shortcutStore)
        XCTAssertTrue(composition.controller.hotKeyRegistrar === composition.hotKeyRegistrar)
        XCTAssertTrue(composition.controller.shortcutScheduler === composition.shortcutScheduler)
        XCTAssertTrue(composition.controller.notificationCenter === composition.notificationCenter)
        XCTAssertTrue(composition.shortcutController === composition.controller.shortcutController)
        XCTAssertTrue(composition.shortcutController.registrar === composition.hotKeyRegistrar)
        XCTAssertTrue(composition.shortcutController.store === composition.shortcutStore)
        XCTAssertTrue(composition.shortcutController.scheduler === composition.shortcutScheduler)
        if let display = composition.screenProvider.currentDisplays().first {
            let context = composition.guidePlacementProvider.context(
                for: display, paletteFrame: display.visibleFrame
            )
            XCTAssertEqual(context?.display, display)
        }
    }

    func testCompositionTestsDoNotImportExecutableTarget() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOfFile: packageRoot
            .appendingPathComponent("Tests/PointerCompositionTests/PointerCompositionRootTests.swift")
            .path)
        XCTAssertNil(source.range(of: "(?m)^import Pointer$", options: .regularExpression))
    }

- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PointerCompositionRootTests

Expected: Package.swift lacks PointerComposition and composition source/test target.

- [ ] **Step 3: Add the target graph and root.**

Add a library product/target PointerComposition depending on PointerCore and PointerAppKit; make Pointer depend directly on PointerComposition and PointerAppKit; add PointerCompositionTests depending directly on PointerComposition, PointerAppKit, and XCTest. Declare the BuildScripts XCTest target explicitly:

    .testTarget(
        name: "PointerBuildScriptsTests",
        dependencies: ["PointerAppKit"],
        path: "Tests/BuildScripts",
        exclude: ["IconResolutionProbe.swift", "test-build-contract.sh"],
        sources: [
            "LauncherContractTests.swift",
            "GuideAssetCatalogBuildTests.swift",
            "CleanCloneContractTests.swift"
        ]
    )

    Keep the existing PointerAppKitTests target path at Tests/PointerAppKitTests so its Support/** and Harness/** descendants compile automatically. PointerBuildScriptsTests has exactly the three Swift sources listed above and depends only on PointerAppKit; its tests invoke external shell helpers with Process rather than compiling them. IconResolutionProbe.swift and test-build-contract.sh remain excluded SwiftPM resources and are shell-invoked by the contract tests/scripts. Remove production global construction from controller/store and keep UserDefaults.standard only in PointerCompositionRoot.swift.

- [ ] **Step 4: Implement the sole factory and lifetime proof.**

Return all fields in the exact public shape. Keep a local let composition in main.swift through application.run(). Add weak probes for controller, guide, stores, and coordinator under withExtendedLifetime(composition), and a source-level test proving the diagnostic branches do not construct the container.

- [ ] **Step 5: Run GREEN and source-boundary checks.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PointerCompositionRootTests
    /usr/bin/grep -R 'UserDefaults.standard\|UserDefaults(suiteName:)\|PointerApplicationController()' Sources --exclude=PointerCompositionRoot.swift

Expected: composition identity passes and the source scan returns no production global construction.

## Task 2: Preserve diagnostic dispatch and interactive launcher behavior

**Files:**

- Modify: Sources/Pointer/main.swift
- Modify: Sources/Pointer/Pointer.swift
- Modify: Tests/PointerCompositionTests/PointerCompositionRootTests.swift
- Create: Tests/BuildScripts/LauncherContractTests.swift

- [ ] **Step 1: Write failing launcher contract tests.**

    func testSmokeBranchReturnsBeforeCompositionConstruction()
    func testBenchmarkBranchReturnsBeforeCompositionConstruction()
    func testQualityPerformanceAndComparisonBranchesReturnBeforeCompositionConstruction()
    func testNoFlagBranchConstructsOneStrongCompositionBeforeRun()

Use source inspection plus executable invocations. The smoke branch must accept --smoke --format json and optional built-in/external displays; the benchmark branch must accept --benchmark-gestures --format json; the quality branches must dispatch --quality-performance --format json --variant baseline|candidate --source-id <immutable-id> and --quality-compare --format json --baseline <path> --candidate <path> --output-dir <path>; invalid arguments exit nonzero with concise stderr.

- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter LauncherContractTests

Expected: current launcher imports only PointerAppKit, no composition target exists, and quality CLI branches are absent.

- [ ] **Step 3: Implement the two-path launcher.**

Import PointerComposition and PointerAppKit's @MainActor PerformanceCLI, retain all diagnostic parsers before MainActor composition, and dispatch smoke, gesture benchmark, quality-performance, and quality-compare branches before any composition is constructed. The quality branches invoke PerformanceCLI through MainActor.assumeIsolated { try PerformanceCLI.run(arguments:outputDirectory:) }; only the no-flag branch executes:

    let composition = PointerCompositionRoot.make()
    composition.application.commandRouter = composition.commandRouter
    composition.application.localKeyRouter = composition.commandRouter
    composition.application.firstUseGuide = composition.guide
    composition.application.delegate = composition.controller
    composition.application.run()

The local strong composition must remain alive for the blocking run and be releasable after it returns.

- [ ] **Step 4: Run GREEN and CLI checks.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PointerBuildScriptsTests|PointerCompositionRootTests'
    build/Pointer.app/Contents/MacOS/Pointer --smoke --format json
    build/Pointer.app/Contents/MacOS/Pointer --benchmark-gestures --format json

Expected: both diagnostics return without opening an interactive window or constructing composition; no-flag ownership is proven by source/lifetime tests.

## Task 3: Make Release bundle/resource/icon contract executable

**Files:**

- Modify: Bundle/Info.plist
- Modify: scripts/build-app.sh
- Modify: scripts/run-app.sh
- Modify: scripts/verify.sh
- Modify: Tests/BuildScripts/test-build-contract.sh
- Create: Tests/BuildScripts/IconResolutionProbe.swift
- Create: Tests/BuildScripts/GuideAssetCatalogBuildTests.swift

- [ ] **Step 1: Add failing build-contract assertions.**

    test_app_icon_compiled_to_assets_car()
    test_bundle_contains_first_use_guide_assets()
    test_launch_services_resolves_exact_bundle_and_marker_digest()
    test_second_release_build_has_identical_tracked_resource_manifest()

Expected: current build copies only Info.plist/executable and has no Assets.car, AppIcon identity, guide resources, or probe.

- [ ] **Step 2: Implement tracked resource compilation.**

Use actool for Bundle/Assets.xcassets into Contents/Resources/Assets.car, set CFBundleIconName exactly to AppIcon, copy tracked GuideAssetIdentity.json and guide resources, lint Info.plist, validate arm64 and ad-hoc signature, and keep staging cleanup recoverable. Reject untracked Info.plist/catalog resources.

- [ ] **Step 3: Implement IconResolutionProbe.swift.**

Compile IconResolutionProbe.swift with xcrun swiftc -framework AppKit -framework CoreServices only. It invokes LSRegisterURL, resolves the exact standardized Release bundle URL via NSWorkspace.shared.urlForApplication(withBundleIdentifier:), inspects AppIcon via assetutil --info, renders the resolved AppIcon NSImage at exactly 512 x 512 sRGB IEC 61966-2.1 RGBA8, normalizes alpha, hashes row-major bytes with SHA-256, and compares manifest digest/marker pixel. It does not import PointerAppKit or perform guide lookup. GuideAssetCatalogBuildTests is the module-linked test for that separate contract.

- [ ] **Step 4: Implement idempotence and clean-clone assertions.**

Generate build/Pointer.resource-manifest.sha256 from these exact sorted relative inputs: every regular file below Bundle/Assets.xcassets/AppIcon.appiconset, every regular file below Bundle/Assets.xcassets/FirstUseGuide, Bundle/AppIconIdentity.json, Bundle/GuideAssetIdentity.json, Bundle/Info.plist, build/Pointer.app/Contents/Resources/Assets.car, build/Pointer.app/Contents/Info.plist, and build/Pointer.app/Contents/MacOS/Pointer. Hash file bytes with shasum -a 256 and write one path-plus-digest row per input. Exclude Contents/_CodeSignature/**, build/.Pointer.app.*/** staging directories, SwiftPM .build/**, mtimes, absolute paths, and ad-hoc signature metadata. The manifest command is:

    LC_ALL=C find Bundle/Assets.xcassets/AppIcon.appiconset Bundle/Assets.xcassets/FirstUseGuide -type f -print | sort | while IFS= read -r path; do shasum -a 256 "$path"; done > build/Pointer.resource-manifest.sha256
    shasum -a 256 Bundle/AppIconIdentity.json Bundle/GuideAssetIdentity.json Bundle/Info.plist build/Pointer.app/Contents/Resources/Assets.car build/Pointer.app/Contents/Info.plist build/Pointer.app/Contents/MacOS/Pointer >> build/Pointer.resource-manifest.sha256

After the second Release build, generate build/Pointer.resource-manifest.candidate.sha256 with the same command and run cmp -s against the first manifest; on mismatch print diff -u and exit nonzero. Run the same manifest/probe comparison from F's scoped clean branch checkout with no inherited build products.

- [ ] **Step 5: Run GREEN.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer POINTER_RELEASE_BUNDLE="$PWD/build/Pointer.app" swift test --filter GuideAssetCatalogBuildTests
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Tests/BuildScripts/test-build-contract.sh
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/verify.sh

Expected: Release bundle has exact resources/icon identity, idempotent build, valid plist/signature/arm64, deterministic smoke, and no raw xcassets acceptance.

GuideAssetCatalogBuildTests is an @MainActor XCTestCase in the module-linked PointerBuildScriptsTests target. It imports PointerAppKit, resolves the Release bundle path from POINTER_RELEASE_BUNDLE, decodes GuideAssetCatalogEnvelope.entries from Bundle/GuideAssetIdentity.json, constructs the production GuideAssetCatalog(envelope:bundle:), and calls catalog.image(for:variant:) for every entry/variant. It derives source paths with GuideAssetSourceMapping, verifies each serialized sourceSHA256 and source dimensions against the tracked PNG, verifies every compiled image is nonnil and matches the variant dimensions, and fails on missing/extra/unresolved entries. This test owns no duplicate lookup implementation; it exercises the production catalog after actool.

## Task 4: Add CI, full gate, and final evidence schemas

**Files:**

- Modify: .github/workflows/verify.yml
- Modify: scripts/verify.sh
- Create: .codex/sdd/reports/quality-campaign/final/EvidenceLedger.md
- Create: .codex/sdd/reports/quality-campaign/final/ChromeFrictionReport.md
- Create: .codex/sdd/reports/quality-campaign/final/CompletionMatrix.md

- [ ] **Step 1: Write failing gate checks.**

    func testVerifyScriptCallsSmokeAndReleaseContracts()
    func testEvidenceLedgerRejectsMissingHostDateStepsResultOrPath()
    func testCompletionMatrixHasOneRowPerOriginalRequirement()

Expected: scripts/CI and final evidence files do not yet prove the complete scope.

- [ ] **Step 2: Implement integrated gate.**

Run Release build first, then the full Swift suite and exactly swift test --filter PointerBuildScriptsTests, followed by plist/signature/arm64/resource/icon/idempotence checks, deterministic smoke, benchmark, git diff --check, and clean-clone literal commands. Any test that invokes a built executable is scheduled only after the Release build succeeds. CI must use Xcode 15.4+ and macOS 14+ arm64 and must not claim physical coverage.

- [ ] **Step 3: Implement final reports.**

EvidenceLedger rows contain case, host/model, macOS/Xcode, connected displays, permissions, date/time, exact steps, result, evidence path, and evidence class. ChromeFrictionReport contains immutable baseline/candidate identities, persistent control/row/status/focus counts, common-path clicks/keys/steps, additions/removals, and disposition. CompletionMatrix links measurements/baseline.json and candidate.json, comparisons/paired-comparison.json, and resilience/resilience.json to the authoritative E evidence; it maps every original requirement to authoritative proof and marks missing/indirect/unsupported rows incomplete.

- [ ] **Step 4: Run GREEN.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PointerBuildScriptsTests
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/verify.sh
    git diff --check

Expected: all deterministic gates pass; physical rows remain explicit until manual evidence is recorded.

## Task 5: Execute the clean-clone gate from the local branch

**Files:**

- Create: scripts/test-clean-clone.sh
- Modify: Tests/BuildScripts/test-build-contract.sh
- Create: Tests/BuildScripts/CleanCloneContractTests.swift
- Create at runtime: .codex/sdd/reports/quality-campaign/final/CleanCloneIdentity.md

- [ ] **Step 1: Write failing clean-clone contract tests.**

    func testCleanCloneScriptUsesCommittedSourceIdentityAndScopedDetachedWorktree()
    func testCleanCloneRunsReleaseBuildBeforeSmokeWithoutRemoteAccess()

    The source-path test resolves the script root from #filePath, not the process current directory, and asserts the script contains mktemp, git worktree add --detach from a committed source identity, a trap cleanup, build-app.sh, `swift test --filter PointerBuildScriptsTests`, verify.sh, and smoke invocation before any application open. The ordering test asserts the Release build precedes the BuildScripts test and both precede verify/smoke.

- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CleanCloneContractTests

Expected: scripts/test-clean-clone.sh and the contract tests are absent.

- [ ] **Step 3: Implement the executable clean-clone protocol.**

scripts/test-clean-clone.sh must use this exact local-only sequence after the coordinator's committed-source gate:

    source_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
    source_identity="$(git -C "$source_root" rev-parse --verify HEAD^{commit})"
    [[ -n "$source_identity" ]]
    [[ -z "$(git -C "$source_root" status --porcelain --untracked-files=all)" ]]
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/pointer-clean-clone.XXXXXX")"
    clone_root="$fixture/repo"
    trap 'git -C "$source_root" worktree remove --force "$clone_root" >/dev/null 2>&1 || true; rm -rf -- "$fixture"' EXIT
    git -C "$source_root" worktree add --detach "$clone_root" "$source_identity"
    (cd "$clone_root" && DEVELOPER_DIR="${DEVELOPER_DIR:?}" ./scripts/build-app.sh)
    (cd "$clone_root" && DEVELOPER_DIR="${DEVELOPER_DIR:?}" swift test --filter PointerBuildScriptsTests)
    (cd "$clone_root" && DEVELOPER_DIR="${DEVELOPER_DIR:?}" ./scripts/verify.sh)

The script must fail if source_identity is unavailable, the source worktree is dirty, the scoped worktree is not created, or the Release bundle/smoke contract fails. It must not call git clone, archive a mutable working tree, fetch, pull, or a remote URL. It records source_identity in the final clean-clone evidence and removes only the scoped temporary worktree after the run. The coordinator's commit gate must make the six plan/design documents and reconciled implementation available at that identity before invoking this script.

- [ ] **Step 4: Run the clean-clone gate.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/test-clean-clone.sh

    Expected: the scoped temporary checkout builds Release, runs `swift test --filter PointerBuildScriptsTests`, validates resources/signature/arm64, and runs deterministic smoke before any live window is opened.

## Task 6: Execute the complete manual-use matrix

**Files:**

- Create: .codex/sdd/reports/quality-campaign/final/ManualUseReport.md
- Modify: .codex/sdd/reports/quality-campaign/final/EvidenceLedger.md

- [ ] **Step 1: Run host-capability preflight.**

Record host/model, macOS/Xcode, connected displays, full-screen/Space capability, VoiceOver, Reduce Transparency, Increase Contrast, permissions, and date/time. A missing capability is an exact gap, not a pass.

- [ ] **Step 2: Exercise the built app directly.**

Record launch standby; annotation toggle; arrow, rectangle, ellipse, pen, emoji, spotlight; select/move/resize/delete; undo, clear, swept erase; palette drag/re-show; Escape/menu bar; shortcut change/conflict/timeout/recovery/relaunch; narrow/wide palette; keyboard-only; VoiceOver; dark/light/contrast; display pointer placement; two displays; full-screen Spaces; disconnect/reconnect/no-display; denied permissions; long session; and fresh-defaults first-use guide launch/reopen/Close/Done/Escape/annotation dismissal/display loss/reconnect/stop-start. Explicitly verify guide placement receives the palette frame and avoidance rects, stays clamped beside the palette, and does not cover a presentation target. Explicitly verify standby keeps marks/undo but removes selection/handles/Delete and requires re-selection.

- [ ] **Step 3: Record every row.**

Each row records exact steps, observed result, evidence path, and whether proof is physical/manual or deterministic. Every capable-but-untested, failed, or missing-field row remains incomplete.

- [ ] **Step 4: Run final application-level review.**

Require no unresolved blocker/high-severity finding, reviewed issue ledger entries with reproduction/evidence/owner/fix/reviewer/adversarial result/verification, and a second fresh audit that finds no meaningful new issue. Lower-severity residuals require a reason and bounded follow-up.

## Task 7: Reconciliation gate

- [ ] **Step 1:** Run git status --short, git diff --check, and verify F-only paths plus accepted A-E reports.
- [ ] **Step 2:** Run full tests, Release/build contract, clean-clone, smoke, benchmark, performance disposition, and manual evidence ledger.
- [ ] **Step 3:** Hand all diffs/reports to the configured Luna reviewer; reviewer returns REVISE or APPROVED with architecture, security, accessibility, resource, and evidence findings.
- [ ] **Step 4:** After approval, adversarial Codex re-reads the objective/design and challenges composition lifetime, diagnostic branch isolation, icon identity, raw asset copies, clean-clone reproducibility, manual case coverage, evidence-class honesty, dirty-checkout boundaries, and every completion-matrix row.
- [ ] **Step 5:** Return findings to the owning worker, rerun the relevant gates, obtain reviewer approval, and repeat Codex review until all workstreams reconcile. Do not mark complete while any completion row is indirect, unsupported, untested, or missing.

## Plan self-check

Composition target/identity, exact import-line exclusion, declared BuildScripts target, Release-before-executable-test ordering, Release/icon/build contracts, CI/full validation, final evidence reports, complete manual matrix, clean-clone proof, and reviewer/adversarial reconciliation are covered. No commit step or out-of-scope product feature is included.
