# Pointer F — Integration, Composition, Manual Use, and Completion Evidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking. The coordinating agent owns commits and publication; worker tasks end with evidence/status handoff instead of commit steps.

**Goal:** Prove the reconciled Pointer product through its real package graph, Release bundle, deterministic CLI, clean-clone gate, manual interaction matrix, and evidence-led completion report.

**Architecture:** Add importable PointerComposition with the sole
dependency-injected factory and keep Pointer as a minimal diagnostic
dispatcher/interactive launcher. Build tracked Info.plist/assets through
actool, validate exact icon resolution and idempotence, run the full
Swift/Release/smoke/benchmark gate, and write final evidence under the
F-owned report subtree. E's model-only `GestureBenchmark.Result` remains
separate from the full-quality `PerformanceMeasurementReport` and paired
`PerformanceComparisonReport`; E-foundation implements the typed
`standard12`/`dense1000` fixture-profile schema, `PerformanceCLI`, and
`scripts/benchmark-quality.sh` before F-foundation, while F only imports and
wires the existing CLI's launcher branches and consumes both separate E
evidence sets.

**Tech Stack:** Swift tools 5.10, macOS 14+, SwiftPM, AppKit, Carbon, XCTest, xcodebuild/swift/actool/assetutil/Launch Services, shell scripts, GitHub Actions, Markdown evidence ledgers.

**Spec:** .codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md (Workstream F and completion audit).

## Global Constraints

- PointerComposition depends on PointerCore and PointerAppKit and is usable by composition tests without importing the executable.
- Pointer parses `--smoke --format json`, the model-only
  `--benchmark-gestures --format json`, full-quality
`--quality-performance --format json` with explicit `--operation trial` or
`--operation finalize`, and `--quality-compare --format json`
  and `--quality-campaign-complete --format json` before composition. The
  full-quality branches carry exactly one
  `--fixture-profile standard12|dense1000`; only the no-flag path calls
  `PointerCompositionRoot.make()`.
- The accepted profiles are exact: `PerformanceFixtureProfile.standard12`
  uses `pointer-fixture-standard12/v1`, identifier
  `pointer-standard-12-marks`, and 12 marks; `.dense1000` uses
  `pointer-fixture-dense1000/v1`, identifier `pointer-dense-1000-marks`, and
  1,000 marks. F passes the selected `fixtureProfile` through unchanged and
  never combines their report populations.
- Runtime ships only the compiled `Contents/Resources/Assets.car`, the
  byte-identical tracked `GuideAssetIdentity.json`, `Info.plist`, and the
  executable. Raw PNGs, imagesets, or `.xcassets` directories never ship in
  the app bundle; copying raw assets is a failed build, not a fallback.
- The source manifest is identical to E's full immutable content-manifest
  scope: Git-tracked regular files from `Package.swift`, `Sources/**`,
  `Tests/**`, `scripts/**`, `Bundle/Assets.xcassets/**`,
  `Bundle/AppIconIdentity.json`, `Bundle/GuideAssetIdentity.json`,
  `Bundle/Info.plist`, and these required plan/design inputs: the master design
  plus all six phase plans A through F:
  `.codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md`,
  `.codex/sdd/features/2026-08-23-pointer-a-observability-plan.md`,
  `.codex/sdd/features/2026-08-23-pointer-b-lifecycle-correctness-plan.md`,
  `.codex/sdd/features/2026-08-23-pointer-c-product-surface-accessibility-plan.md`,
  `.codex/sdd/features/2026-08-23-pointer-d-visual-language-plan.md`,
  `.codex/sdd/features/2026-08-23-pointer-e-performance-plan.md`, and
  `.codex/sdd/features/2026-08-23-pointer-f-integration-validation-plan.md`.
  It sorts `LC_ALL=C`, writes one `<sha256>  <relative-path>` row per file, and
  defines the 64-hex aggregate as the SHA-256 of those exact row bytes. It
  excludes generated reports, `build/**`, SwiftPM `.build/**`, code-signature
  metadata, mtimes, absolute paths, and untracked files. E baseline/candidate
  and F clean-clone must use this exact scope, row format, aggregate, and
  exclusions.
- F's `scripts/build-app.sh` accepts an explicit `--output-root <root>` and
  emits exactly `<root>/Pointer.app`, `<root>/source-manifest.sha256`,
  `<root>/bundle-manifest.sha256`, and `<root>/provenance.json`. That
`provenance.json` is only the typed `BuildProvenance` for this build: it has
source status/identity, source/executable/bundle hashes, UTC timestamp,
foundation identity/version, harness version, and build-contract version;
exact `buildConfiguration` (`release` authoritative; `debug` bootstrap
diagnostic), optional accepted-foundation artifact SHA, and no filesystem path.
It has no pair ancestry or baseline/candidate claim. F owns clean/ref/
ancestry/build-app/hash creation and supplies prevalidated build/provenance
inputs. E's `benchmark-quality.sh` consumes those inputs, enforces its
canonical path/JSON boundary, and passes them to the diagnostic executable;
`PerformanceCLI` revalidates the typed provenance, eligibility, profile
containment, and hashes before writing. The app only validates and embeds the
typed build/run artifacts; it does not replace F's Git/build proof.
- Evidence distinguishes deterministic proof, current-host physical proof, and unverified platform claims. A capable but untested supported case keeps the goal active; it cannot be marked not applicable.
- The manual matrix covers every supported tool, mode, edit action, palette flow, shortcut path, display/Space condition, guide path, VoiceOver path, appearance state, permission condition, and long session available on the host.
- Work only in /Users/bruno/Dev/pointer/.worktrees/stable-app; preserve the primary checkout's unrelated README/graphify-out and do not reset/clean it.
- F owns Package.swift, Sources/PointerComposition/PointerCompositionRoot.swift, Sources/Pointer/main.swift, Tests/PointerCompositionTests/**, .github/workflows/verify.yml, Bundle/Info.plist, scripts/build-app.sh, scripts/run-app.sh, scripts/verify.sh, scripts/test-clean-clone.sh, Tests/BuildScripts/**, clean-clone/manual harnesses, `.codex/sdd/reports/quality-campaign/foundation/**`, and `.codex/sdd/reports/quality-campaign/final/**`. A's Support/Harness test files remain inside the existing PointerAppKitTests target path; F does not add a support target or alter their ownership.
- F-foundation consumes A-D interfaces plus the reconciled E-foundation
  contracts, imports and wires the already-existing E-foundation
  `PerformanceCLI` into the launcher, and does not own or edit that CLI or
  `scripts/benchmark-quality.sh`; F-final consumes the reconciled E-execution
  reports. F does not
  edit another phase's product behavior, performance subtree, shared fixtures,
  or guide/palette implementation to make integration pass.
- F's final aggregation consumes E's variant reports only from
  `.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/measurements/**`
  for both `standard12` and `dense1000`, their typed provenance artifacts from
  each profile's `provenance/**`, paired reports from each profile's
  `comparisons/**`, the persisted
  `pair-execution/pair-execution.json` artifact, and each
  profile's resilience evidence from `resilience/**`; F retains the exact E
  input reports and pair-execution artifacts unchanged, writes links/summaries
  under `final/**`, and never creates direct-root performance JSON.
- F-final requires both fixture profiles through Task 3c's typed campaign
  completion manifest and evaluates the 16.7 ms
  renderer-plus-compositor and combined-frame gates independently for each;
  it never concatenates their measurements or treats one profile as a proxy for
  the other. Current E adapter fallbacks remain honest: WindowServer
  compositor, combined-frame, process, and manual writer evidence may remain
  `.unmeasured`/`revise` until the F-owned authoritative caller supplies
  accepted external sidecars through the unchanged E CLI/writer seams;
  `ManualMetricAdapter` is currently a Codable schema, not a physical-evidence
  writer. `CACurrentMediaTime` alone is not a WindowServer measurement, and
  combined-frame evidence must be independently measured. F-foundation does
  not silently accept missing profile fields; E-foundation's implemented
  parameterized model/renderer oracle and tests cover both profiles.
- The clean-clone gate observes its committed source identity and clean status
  at execution time. It is unavailable until the coordinator provides a
  committed campaign identity containing the reconciled implementation, tests,
  assets, scripts, and plan/design inputs required by the branch. The current
  uncommitted plan/design state is a precondition failure, not a clean-clone
  result; a stale report or earlier clean/dirty claim cannot satisfy the gate.
- F tasks 1–3 start only after E-foundation tasks 1–3 have reconciled the
  benchmark/schema/harness contracts, including the trial/finalize partial-pair
  schemas. E-execution then runs the paired
  immutable protocol against this F foundation. F tasks 4–7 start only after
  E-execution is reconciled and consume its immutable reports. F never promotes
  Task3c diagnostic `revise` reports, invokes compare, or accepts a campaign
  manifest before its own foundation and the typed external sidecars exist.
  Before F-foundation, E's diagnostic script requires explicit F-supplied
  build/provenance/eligibility inputs, accepts no foundation or manual-evidence
  arguments, copies provenance into staged profile evidence, and makes no
  checkout-to-binary hash-correspondence claim; it may perform exactly 60
  trials and one finalize for a selected profile, then stops without compare or manifest;
  an F-owned authoritative caller must validate F's foundation/sidecar gate
  before invoking the unchanged E trial/finalize CLI and reject before the first
  trial when it is absent. The diagnostic script has no authoritative mode.
  Before any trial, the E-owned script canonicalizes and validates the selected
  profile roots and destinations: baseline/candidate roots are distinct
  non-symlink directories at `build/<fixture-profile>/{baseline,candidate}`;
  the profile evidence destination is a non-symlink path outside both roots;
  pair eligibility is exactly
  `<profile-evidence>/comparisons/pair-eligibility.json`; and each provenance
  file is a regular non-symlink file within its matching build root. Default
  executable routing is
  `<variant-root>/Pointer.app/Contents/MacOS/Pointer`; explicit executable
  overrides remain executable, canonical, and contained by that variant root.
  All build and evidence paths must resolve within the same physical
  `<repo-root>`: `<repo-root>/build/<fixture-profile>/{baseline,candidate}` and
  `<repo-root>/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>`.
  Relative arguments resolve from that root, and absolute arguments must
  canonicalize to those exact paths.
  `$REPO` denotes that physical repository root. Production CLI accepts run
  provenance only at `$REPO/build/<fixture-profile>/<variant>/provenance.json`,
  and each `PerformanceRunProvenance.outputRoot` equals
  `$REPO/build/<fixture-profile>/<variant>`;
  `PerformancePairEligibility.baselineRoot` and `.candidateRoot` are exactly
  `$REPO/build/<fixture-profile>/baseline` and
  `$REPO/build/<fixture-profile>/candidate`, and the partial directory is
  `$REPO/build/<fixture-profile>/pair-execution/partial`. Final evidence is
  only `$REPO/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>`;
  direct legacy evidence roots are rejected.
  The script validates the logical output scope before creating any directory,
  then acquires a live-owner profile lock before recovery or staging; that lock
  remains held through trials, finalization, and publication. Before spawning a
  child, the starting gate durably records only a starting intent/token, the
  shell PID, and transaction identity in the profile lock. The child then enters
  a private readiness gate; after readiness, the lock records its child PID and
  child PGID/process-group identity before releasing
  that gate. A recorded running owner may be taken over only after its shell
  PID, child PID, and process group are dead and descendants are quiescent. If
  the lock remains in the unrecorded `starting` state, it is the sole liveness
  exception: the wrapper may still be alive only after recovery atomically
  revokes and quarantines that transaction's private capability namespace/token
  and guarantees that the wrapper fails closed before publication, readiness-gate
  release, executable invocation, or mutation. The recovery operation is
  restartable: a valid existing capability-revocation marker is accepted and
  reused, while a valid deterministic `.revoked.<token>` quarantine is reopened
  to resume cleanup. Each revocation marker, quarantine rename, and cleanup
  transition is durably synced. After the quarantine validates, recovery
  atomically renames it to the deterministic `.cleanup.<token>` tombstone and
  durably syncs that transition.
  The cleanup directory name is the authoritative resumable state: it permits
  only the token-scoped `gate`, `ready`, `owner`,
  `owner.tmp`, `capability`, and `capability.revoked` entries with their
  expected physical node types, and accepts any subset after partial deletion,
  including a missing revocation marker. Recovery deletes the remaining allowed
  entries and then the empty tombstone, durably syncing each file-removal
  transition and the final cleanup. A live namespace, `.revoked.<token>`
  quarantine, and `.cleanup.<token>` tombstone may not coexist; malformed names,
  node types, symlinks, or extra entries reject. The journal owns transaction
  state and paths. When an existing profile lock appears stale, contenders
  serialize through the durable guard
  `$REPO/.codex/sdd/reports/quality-campaign/performance/.benchmark-quality.recovery.<fixture-profile>`.
  The guard records its owner PID and transaction plus the exact observed lock
  SHA-256 and complete observed owner tuple (shell PID, transaction, child,
  state, token, and child PGID). While holding the guard, recovery re-reads and
  re-fingerprints the exact stale lock and requires the tuple to remain identical
  and every recorded owner/process group to remain dead before any mutation. A
  changed, replaced, or newly live lock aborts without mutation; a live guard
  blocks. A dead guard is reclaimed only by validating it and atomically renaming
  it to the unique quarantine
  `.benchmark-quality.recovery.<fixture-profile>.reclaimed.<oldTransaction>.<oldPID>.<newTransaction>`,
  then durably cleaning that quarantine. After stale recovery, the guard is
  released and contenders return to normal lock acquisition, so simultaneous
  contenders allow exactly one publisher to proceed. An optional runner
  receives the selected executable as its first argument and
  the exact CLI argv, without `eval` or shell-string execution. Wrong-profile,
  traversal, alias/symlink, overlap, and out-of-root paths reject before the
  first trial. The staged diagnostic profile allowlist is exactly
  `provenance/{baseline,candidate}.json`,
  `comparisons/pair-eligibility.json`,
  `measurements/{baseline,candidate}.json`, and
  `pair-execution/pair-execution.json`, under only those four root directories;
  manual/resilience/comparison/partial/lock files and every extra entry are
  excluded. The shell's staged check requires only regular, non-symlink,
  well-formed JSON files and does not re-encode or assert canonical bytes;
  `PerformanceCLI` finalization owns canonical sorted-key bytes for generated
  measurement reports and the pair artifact, and its real integration test
  verifies that guarantee. Publication is a crash-recoverable journaled
  transaction: after the scope check and live-owner lock, the script journals
  transaction state plus canonical staging/destination/backup paths and
  `had-existing` state before creating pending staging. It creates the pending
  profile only at
  `$REPO/.codex/sdd/reports/quality-campaign/performance/.benchmark-quality.pending.<fixture-profile>/<fixture-profile>`.
  It then atomically installs
  the fully validated profile through `prepared`, `backed-up`, and `installed`
  states, records commit, and removes backup/journal only after commit. Recovery
  and signal cleanup handle dead owners in journaled `prepared`, `backed-up`,
  and `installed` states: `prepared` removes abandoned staging, `backed-up`
  restores the prior destination, and `installed` resolves the destination from
  the recorded `had-existing` and backup state. A pending tree or backup with
  no journal is an orphan, not safely recoverable; only an empty pending tree
  may be removed, while nonempty orphan state is rejected as requiring recovery.
  Handled `INT`/`TERM` signals are forwarded to the child process group and
  awaited until descendants quiesce. Each mutation-capable publication hook is
  awaited and followed by complete path/allowlist/JSON revalidation before
  commit. The lock's shell/child/process-group identity prevents a live owner
  from being recovered by another invocation; an unrecorded starting wrapper is
  eligible only after its capability namespace is atomically revoked/quarantined
  and it is guaranteed to fail closed. No half-published tree is accepted.
  `BenchmarkQualityScriptTests` covers an orphaned active-child/process-group
  lock, handled-signal group forwarding and descendant waiting, successful hook
  mutations followed by revalidation, the three pre-prepared, post-backup, and
  post-install crash windows, two SIGKILL recovery-of-recovery cases that resume
  from a valid revocation marker and from a deterministic `.revoked.<token>`
  quarantine, and two mid-cleanup SIGKILL cases that resume after partial
  deletion, including a missing revocation marker, from the `.cleanup.<token>`
  tombstone; one resumes after a generic allowed-file removal and one after
  revocation-marker removal. It also covers simultaneous stale contenders,
  exactly one publisher proceeding, and a SIGKILL while the stale-recovery
  guard is held that is reclaimed before recovery resumes.
- F tasks 1–3 produce the tracked foundation checkpoint
  `.codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json`.
  It is accepted only after the F worker, independent reviewer, and
  adversarial gate agree, and it records the foundation identity/version,
  harness version, build-contract version, checkpoint commit SHA, full source
  manifest SHA, executable/bundle-manifest SHAs, UTC timestamp, and worker/
  reviewer/adversarial acceptance results in a fixed JSON shape. E-execution
  and clean-clone receive this explicit path; no hidden environment variable
  supplies foundation identity.
- The canonical 420-point narrow-display fixture and accepted A-harness
  real-guide lifecycle evidence are prerequisites for F-final. D's static or
  source-asset guide checkpoints are provenance only and cannot replace the
  real-guide A-harness evidence.

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
        public static func make(resourceBundle: Bundle = .main) -> PointerComposition
    }

The root obtains `PointerApplication.shared as PointerApplication`, constructs
the concrete screen provider, coordinator, router, menu,
`ControlMetadataInventory`, and `GuidePlacementProvider`, decodes the tracked
`GuideAssetIdentity.json` from the injected `resourceBundle`, and constructs
an explicit D-owned `GuideAssetCatalog(envelope:bundle:)` with that exact same
bundle. It then constructs `PalettePanel(router:guidePlacementProvider:)`
with that provider, Carbon registrar, scheduler, `NotificationCenter.default`,
`UserDefaultsShortcutStore` with `UserDefaults.standard`, shortcut controller,
D's guide, and guide store, then wires provider/store/metadata dependencies
into palette/controller and catalog/provider/store directly into D's guide;
the catalog is not passed to C's controller. `GuideAssetCatalog` itself never
uses `Bundle.main`, a default bundle, or global resource lookup: only this
composition-root default may select `.main`.

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

    func testCompositionRootPassesOneInjectedResourceBundleToGuideCatalog() throws {
        let composition = PointerCompositionRoot.make(resourceBundle: testResourceBundle)
        let guide = try XCTUnwrap(composition.guide as? FirstUseGuideController)
        XCTAssertTrue(guide.assetCatalog === composition.guideAssetCatalog)
        XCTAssertEqual(guide.assetCatalog.bundleIdentifier, testResourceBundle.bundleIdentifier)
    }

    func testCompositionPublicAPICompilesFromExternalModule() throws {
        // Compile a temporary external client against only the library modules,
        // resolve public symbols, and inspect the package graph for the test
        // target's dependencies. This is symbol-aware and does not inspect
        // source text for import substrings.
        try runSwiftBuild(target: "PointerComposition")
        let probe = """
        import Foundation
        import PointerComposition
        @MainActor @main
        enum ExternalCompositionProbe {
            static func main() {
                let _: PointerComposition = PointerCompositionRoot.make(resourceBundle: .main)
            }
        }
        """
        try compileExternalSwiftProbe(probe, imports: ["PointerComposition", "PointerAppKit"])
        let packageGraph = try dumpPackageGraph()
        XCTAssertFalse(packageGraph.testTarget(named: "PointerCompositionTests").dependencies.contains("Pointer"))
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

Return all fields in the exact public shape. Keep a local `let composition` in
main.swift through `application.run()`. Add weak probes for controller, guide,
stores, and coordinator under `withExtendedLifetime(composition)`, and an
executable branch test proving the diagnostic branches do not construct the
container. The construction test must pass a non-main injected bundle and
prove the guide catalog resolves through that bundle; the production default
is `resourceBundle: Bundle = .main` at the root only.

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
    func testQualityCompareRequiresManualEvidenceDirectory()
    func testMetricSamplesCarryExplicitStatusAndStableDiagnosticInCanonicalOrder()
    func testExactVersionedTrialWireTypesRoundTripAllCanonicalMetricSamples()
    func testExternalTrialSidecarUsesExactNullableScalarWireShape()
    func testExternalAggregateSidecarRequiresThirtyOrderedResultHashes()
    func testTrialBuildsRequestFromFlagsAndRejectsOutputDirectory()
    func testTrialRequiresValidatedProvenanceAndEligibilityBeforePartial()
    func testTrialResultCarriesHashesWarmupsSamplesAndEvidence()
    func testTrialEmitsEveryMetricWithUnmeasuredDiagnostics()
    func testFinalizeDerivesContainedProfileEvidenceAndWritesArtifactLast()
    func testPreFoundationDiagnosticStopsAfterSixtyTrialsAndFinalize()
    func testDiagnosticScriptRejectsAuthoritativeFlagsBeforeTrials()
    func testTrialCLIAcceptsDiagnosticContentManifestIdentityBoundToRunCommit()
    func testCampaignCompletionCLIUsesExactAcceptedComparisonBindingsAndIsIdempotent()
    func testNoFlagBranchConstructsOneStrongCompositionBeforeRun()

Use executable invocations plus the external-module/symbol-aware compile proof
above. The smoke branch must accept
`--smoke --format json` and optional built-in/external displays. The
`--benchmark-gestures --format json` branch must remain the model-only
`GestureBenchmark.Result` diagnostic. The quality branches must dispatch these
operation-specific forms with their mutually exclusive measurement identities:
Direct `PerformanceCLI` URL arguments below are canonical absolute paths and
assume the command runs from the physical repository root (`$PWD == $REPO`).
The shell wrapper's relative arguments are the exception: it resolves them from
its own repository root before invoking the CLI.

```text
--quality-performance --format json --operation trial \
  --fixture-profile <standard12|dense1000> --variant <baseline|candidate> \
  --pair-order <baselineFirst|candidateFirst> --pair-index <0...29> \
  (--source-commit-sha <40hex> | --content-manifest-sha256 <64hex>) \
  --run-provenance-file "$PWD/build/<fixture-profile>/<variant>/provenance.json" \
  --pair-eligibility-file "$PWD/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/comparisons/pair-eligibility.json" \
  [--external-trial-sidecar "$PWD/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/external/trials/<variant>/<pairIndex>.json"] \
  --partial-pair-directory "$PWD/build/<fixture-profile>/pair-execution/partial"
--quality-performance --format json --operation finalize \
  --fixture-profile <standard12|dense1000> \
  --partial-pair-directory "$PWD/build/<fixture-profile>/pair-execution/partial" \
  --baseline-run-provenance-file "$PWD/build/<fixture-profile>/baseline/provenance.json" \
  --candidate-run-provenance-file "$PWD/build/<fixture-profile>/candidate/provenance.json" \
  --pair-eligibility-file "$PWD/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/comparisons/pair-eligibility.json" \
  [--baseline-external-aggregate-sidecar "$PWD/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/external/aggregate/baseline.json"] \
  [--candidate-external-aggregate-sidecar "$PWD/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/external/aggregate/candidate.json"] \
  --output-dir "$PWD/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>"
--quality-compare --format json \
  --fixture-profile standard12|dense1000 \
  --baseline-report "$PWD/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/measurements/baseline.json" \
  --candidate-report "$PWD/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/measurements/candidate.json" \
  --pair-eligibility-file "$PWD/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/comparisons/pair-eligibility.json" \
  --pair-execution-artifact "$PWD/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/pair-execution/pair-execution.json" \
  --manual-evidence-dir "$PWD/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/comparisons/manual" \
  --output-dir "$PWD/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/comparisons"
--quality-campaign-complete --format json \
  --standard12-comparison "$PWD/.codex/sdd/reports/quality-campaign/performance/standard12/comparisons/paired-comparison.json" \
  --dense1000-comparison "$PWD/.codex/sdd/reports/quality-campaign/performance/dense1000/comparisons/paired-comparison.json" \
  --output-file "$PWD/.codex/sdd/reports/quality-campaign/performance/campaign-completion/manifest.json"
```

The F-owned `--quality-campaign-complete` operation calls
`PerformanceCampaignCompletion.writeManifest` to validate both canonical
comparison files, their exact hashes, shared baseline/candidate lineage, and
profile separation before atomically writing the sorted-key completion manifest.
It accepts no path-only or concatenated evidence.

The launcher dispatches `--operation trial` and `--operation finalize` without
constructing composition. A trial performs five local warmups on an isolated
fixture and emits one scalar sample per metric in strict canonical
`PerformanceTrialRequest`, `PerformanceTrialMetricSample`,
`PerformanceTrialResult`, and `PerformancePartialPair` schema-version-1 JSON;
`sampleIndex == pairIndex`. Their exact fields are minimal request
`schemaVersion`, `fixtureProfile`, typed `variant`, `order`, `pairIndex`, and
`sampleIndex`; metric sample `metricID`, `unit`, `status`, `value`, and
`diagnostic`; result `schemaVersion`, `request`, `sourceIdentity`,
`runProvenanceSHA256`, `pairEligibilitySHA256`, `startedAtUTC`,
`endedAtUTC`, `warmupCountExecuted`, `samples`, required
`modelEvidence`, and required `rendererEvidence`; and partial `schemaVersion`,
`fixtureProfile`, `pairIndex`,
`order`, `baseline`, and `candidate`. Requests are in-memory values
constructed from flags; only the derived partial is persisted. Every canonical
metric is emitted exactly once; unavailable metrics use `unmeasured` with nil
value and a nonempty diagnostic. Unknown fields, alternate whitespace/key order,
duplicate/missing metrics, nonfinite values, and request/result identity
mismatches reject before decoding or acceptance. Direct `Codable` decoding of
the public request, result, and partial types enforces their exact key sets;
unknown or missing keys do not silently default. `PerformanceModelTrialEvidence`
owns `modelChecksum`, publication count, and final-state validity;
`PerformanceRendererTrialEvidence` owns frame count, missed-frame count,
instrumentation status, and required `semanticPass`. The result's
provenance/eligibility hashes bind the canonical provenance and its embedded
artifact hashes.
The public `PerformanceExternalTrialSidecar` schema has `schemaVersion`,
`binding`, and `measurements`; its binding carries the exact request, source
identity, `runProvenanceSHA256`, `pairEligibilitySHA256`, and timestamps. Its
measurements are exactly the ordered external metrics `compositor`,
`combinedFrame`, `launchCold`, `launchWarm`, `allocations`, `redrawLayout`,
`responsiveness`, and `inputToVisible`, each with `metricID`, `unit`, `status`,
`value`, and `diagnostic`. When present, a sidecar's UTC binding interval must
contain the actual in-process result interval (`startedAtUTC` through
`endedAtUTC`); it supplies external metric values/status only and never
replaces the persisted result timestamps. A retry for an already persisted
variant must match its stored external metric values, statuses, and containing
interval; a mismatched sidecar rejects before measurement. The trial operation
accepts optional
`--external-trial-sidecar <path>`; an absent sidecar supplies explicit
unmeasured null-value diagnostics for those eight external metrics. The public
`PerformanceExternalAggregateSidecar` schema has `schemaVersion`, typed
variant/profile/source/hash `binding`, exactly 30 ordered `resultSHA256s`, and
full typed `MemoryMeasurement` and `ResilienceMeasurement`. Finalize accepts
optional `--baseline-external-aggregate-sidecar <path>` and
`--candidate-external-aggregate-sidecar <path>`; when either is absent, it
does not fabricate external evidence: memory falls back to the in-process
`memoryRSS` aggregation when available, while resilience remains
`unmeasured` with disposition `revise`. Nullable keys, including external
scalar `value`/`diagnostic` and partial `baseline`/`candidate`, are always
present as `null`, never omitted.
When supplied, a trial sidecar is exactly
`$REPO/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/external/trials/<variant>/<pairIndex>.json`;
an aggregate sidecar is exactly
`$REPO/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/external/aggregate/<variant>.json`.
No alternate evidence root or direct legacy path is accepted.
Before finalization accepts an existing external preseed, it audits every
regular, non-symlink entry and binds each trial filename index to its request's
`pairIndex`/`sampleIndex` plus the current variant source identity,
run-provenance hash, and pair-eligibility hash; aggregate filenames must bind
the current variant/profile and hashes as well. Stale, extra, or mismatched
preseed files reject.
The Swift `PerformanceCLI` finalizer uses the same physical performance root
but a distinct publish transaction namespace. Its pending profile is exactly
`$REPO/.codex/sdd/reports/quality-campaign/performance/.<fixture-profile>.pending-<transactionID>`,
where `<transactionID>` is a UUID copied into the schema-version-1 journal at
`$REPO/.codex/sdd/reports/quality-campaign/performance/.benchmark-quality.transaction.<fixture-profile>`.
The journal records transaction state and canonical staging, destination,
backup, and `hadExistingOutput` paths. Recovery validates the journal's
canonical absolute paths and transaction-matching pending suffix before
acting. Any surviving staged profile must be a physical, exact-topology
profile containing only the four allowed root directories/files, with typed
provenance, eligibility, measurements, pair artifact, and optional external
evidence decoded and binding-validated. The backup is exactly
`$REPO/.codex/sdd/reports/quality-campaign/performance/.benchmark-quality.backup.<fixture-profile>/<fixture-profile>`.
Before a new transaction, any existing backup container must be physical and
empty. Recovery preflights a journaled backup as a physical container holding
only its recorded output; when restore moves that output out, it validates the
container is empty before removing it. During recovery, installed-state
cleanup removes the journaled backup container only after that preflight shape
check, and any extra
or malformed entry rejects. The `prepared`, `backed-up`, and `installed` crash
windows respectively remove abandoned staging or restore the prior output,
install validated staging or restore the backup, and resolve the output from
recorded `hadExistingOutput` plus backup state before deleting journal and
backup remnants.
The finalizer requires exactly 30 complete partial-pair files, aggregates every
metric's scalar values in sorted global-index order, requires model and renderer
evidence on every result, and unconditionally requires model-checksum agreement
within each variant regardless of sidecar presence. It derives
`measurements/{baseline,candidate}.json` under the selected profile evidence
directory before writing `pair-execution/pair-execution.json` as the last commit
marker. Those 30 canonical partial-pair files are the only resumable state.
Finalization sets `acceptedNoRegression` only when every required metric and
the complete memory/resilience evidence are measured and valid; otherwise it
preserves a diagnostic report with disposition `revise`.
Before warmup or measurement, the store audits the whole partial directory,
rejects symlinks/nonregular entries and illegal names, and canonical-decodes
and validates every existing regular partial. It then acquires an exclusive
per-slot `<pairIndex>.json.lock` and rechecks the directory while holding that
lock. Around reservation and write, the store captures the partial directory's
`lstat` `(st_dev, st_ino)` identity and requires the same device/inode after
lock acquisition and immediately before the atomic partial write; a directory
replacement, symlink, non-directory, or identity change rejects. Identical
retries are no-ops and conflicting retries reject. Only slots
0...29 may exist in the partial directory; filenames have no order prefix and
any extra entry or active lock rejects. Final load repeats the
regular/non-symlink audit and canonical decode before aggregation.
Global indices 0...14 require `baselineFirst` and 15...29 require
`candidateFirst`; the second variant merges into the same derived slot. No full
measurement report is emitted during a trial. The CLI constructs and
strictly validates each request from flags, provenance, and pair eligibility
before writing a partial; there is no request file or trial output directory.
Trial requires its `--run-provenance-file` and `--pair-eligibility-file`;
finalize requires the explicit baseline and candidate run-provenance files,
pair eligibility, and one profile evidence output directory. `--quality-compare`
emits an authoritative
`PerformanceComparisonReport` from the two report paths and typed eligibility
file; its required existing `--manual-evidence-dir` value binds directly to
`manualEvidenceDirectory` on internal compare together with the decoded
pair artifact and separate `pairExecutionArtifactSHA256`; the public writer
alone reads and validates the pair-execution URL before persistence; deterministic runs require that
directory to be empty. It does not accept roots or refs because the eligibility
file carries the prevalidated lineage. Each `benchmark-quality.sh` invocation
handles exactly one `--fixture-profile`; the campaign caller invokes it once
for `standard12` and once for `dense1000`. Invalid arguments, both/neither measurement source
identity flags, malformed identities, or content-manifest identities on the
authoritative compare exit nonzero with concise stderr. A diagnostic
content-manifest identity binds the build source manifest; eligibility binds
the corresponding commit through the run's 40-hex `sourceRef`, and pair IDs
remain those 40-hex source-ref commits, never the selected 64-hex value.
Separately scoped dirty diagnostic pairs may share a content-manifest hash when
their source-ref commits are distinct; that shared hash is not a pair ID.
F-owned build/ref/ancestry/hash
orchestration supplies the prevalidated inputs; the Task3c diagnostic script
invokes only the trial/finalize report-path commands. After F tasks 1–3 and
its sidecar gate, the F-owned authoritative caller can supply sidecars to the
unchanged CLI, invoke compare, and write the completion manifest;
all derived partial, measurement, and pair-artifact paths must be physically
contained under the selected profile roots, and finalization publishes the
whole profile evidence atomically rather than leaving a partial profile.
The launcher never constructs interactive composition for any diagnostic
branch.

- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter LauncherContractTests

Expected: current launcher imports only PointerAppKit, no composition target exists, and quality CLI branches are absent.

- [ ] **Step 3: Implement the two-path launcher.**

Import PointerComposition and PointerAppKit's @MainActor PerformanceCLI from
the already-existing E-foundation implementation, retain
all diagnostic parsers before MainActor composition, and dispatch smoke, the
model-only gesture benchmark, full quality-performance, and quality-compare
branches before any composition is constructed. The quality-performance
branch requires `--run-provenance-file <path>`; `PerformanceCLI` parses the
typed `PerformanceRunProvenance` envelope, checks its embedded
`BuildProvenance`, source identity, and artifact hashes, and embeds both typed
artifacts in `PerformanceMeasurementReport`. F-owned orchestration supplies
the prevalidated run envelope and `PerformancePairEligibility`; E-foundation's
`benchmark-quality.sh` enforces its canonical path/JSON boundary, while
`PerformanceCLI` revalidates the typed provenance and eligibility during
orchestration. The app does not assert Git status, ancestry, or checkout
provenance; F-owned shell scripts own those proofs. The
quality branches invoke PerformanceCLI through
`MainActor.assumeIsolated { try PerformanceCLI.run(arguments:outputDirectory:) }`;
the compare branch requires an existing `--manual-evidence-dir` and the
pair-execution artifact URL. The public writer privately reads, hashes, and
decodes that URL, then supplies the decoded artifact and its separate SHA plus
the manual directory to internal
`compare(baseline:candidate:configuration:eligibility:pairExecutionArtifact:manualEvidenceDirectory:pairExecutionArtifactSHA256:baselineMeasurementReportSHA256:candidateMeasurementReportSHA256:)`,
which loads and validates manual evidence and the artifact in Task 3 and returns only the hash-free
`PerformanceComparisonDraft`. That public `Sendable, Equatable` opaque carrier has no public
initializer or public stored properties and excludes `reportKind`,
`schemaVersion`, and the two measurement-report hashes. The E-owned writer
owns and injects those fields. It then reaches E's public exact
`writeComparison(draft:baselineURL:candidateURL:pairExecutionURL:manualEvidenceDirectory:outputDirectory:configuration:eligibility:)`,
which receives the same directory and pair-execution URL, cross-checks the
draft/artifact, injects `reportKind == .comparison`, `schemaVersion == 1`, and
the report hashes into the final report, and invokes
internal measurement/configuration/eligibility preflight before writing. It
serializes the persisted comparison with the canonical sorted-key JSON encoder
and writes those bytes atomically. The internal seam is deferred and non-writing
and recomputes/validates the
canonical pair-artifact SHA from the decoded artifact. Exact input measurement-
byte/source-URL hash verification remains public-writer-owned. Hash, identity, fixture, provenance, or eligibility
mismatch must fail before any output file is created.
Only the no-flag branch executes:

    let composition = PointerCompositionRoot.make()
    composition.application.commandRouter = composition.commandRouter
    composition.application.localKeyRouter = composition.commandRouter
    composition.application.firstUseGuide = composition.guide
    composition.application.delegate = composition.controller
    composition.application.run()

The local strong composition must remain alive for the blocking run and be releasable after it returns.

- [ ] **Step 4: Run GREEN and CLI checks.**

This is the F-foundation bootstrap invocation: the four explicit contract
constants are supplied because the accepted foundation artifact does not yet
exist.

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh --output-root build \
      --foundation-identity pointer-f-foundation --foundation-version v1 \
      --harness-version pointer-performance-harness/v1 \
      --build-contract-version pointer-build-contract/v1 \
      --build-configuration release
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
- Create at completion: .codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json

- [ ] **Step 1: Add failing build-contract assertions.**

    test_app_icon_compiled_to_assets_car()
    test_runtime_bundle_contains_only_compiled_assets_and_identity()
    test_launch_services_resolves_exact_bundle_and_marker_digest()
    test_second_release_build_has_identical_tracked_resource_manifest()
    test_build_provenance_contains_release_configuration_and_foundation_sha()

Expected: current build copies only Info.plist/executable and has no compiled
Assets.car, AppIcon identity, guide catalog contract, or probe. The test must
also fail if any raw PNG, imageset, or `.xcassets` directory is present under
the Release bundle.

- [ ] **Step 2: Implement tracked resource compilation.**

Use `actool` for `Bundle/Assets.xcassets` into
`Contents/Resources/Assets.car`, set `CFBundleIconName` exactly to `AppIcon`,
copy only the tracked `GuideAssetIdentity.json` beside the compiled catalog,
lint `Info.plist`, validate arm64 and the ad-hoc signature, and keep staging
cleanup recoverable. Do not copy raw PNGs, imagesets, or `.xcassets` into the
bundle. Reject untracked Info.plist/catalog resources and fail closed on any
raw asset found under `Contents/Resources`.

The build helper accepts `--output-root <root>` and emits only the four
documented per-variant outputs: `<root>/Pointer.app`,
`<root>/source-manifest.sha256`, `<root>/bundle-manifest.sha256`, and
`<root>/provenance.json`. A missing, extra, or differently rooted output is a
contract failure. It has two deterministic modes. Before the foundation is
accepted, bootstrap mode receives the explicit
`--foundation-identity`, `--foundation-version`, `--harness-version`, and
`--build-contract-version`, and `--build-configuration release|debug` from the
E/F contracts and emits a candidate `BuildProvenance` with no
accepted-foundation SHA; `debug` is diagnostic-only. After acceptance,
post-acceptance mode requires `--foundation-provenance <path>` and
`--build-configuration release`, validates the accepted artifact, and embeds
its SHA-256 plus identity/version fields in `BuildProvenance` without
embedding the artifact path. At the end of F tasks 1–3, the coordinator writes
`foundation/accepted-foundation.json` at the tracked path above, and the F
reviewer plus adversarial gate must accept it before E-execution.

The accepted foundation JSON uses this fixed loader-facing shape:

```json
{
  "schemaVersion": 1,
  "foundationIdentity": { "identity": "pointer-f-foundation", "version": "v1" },
  "harnessVersion": "pointer-performance-harness/v1",
  "buildContractVersion": "pointer-build-contract/v1",
  "buildConfiguration": "release",
  "checkpointCommitSHA": "<40hex>",
  "fullSourceManifestSHA256": "<64hex>",
  "executableSHA256": "<64hex>",
  "bundleManifestSHA256": "<64hex>",
  "acceptedAtUTC": "<ISO-8601 UTC>",
  "workerResult": "APPROVED",
  "reviewerResult": "APPROVED",
  "adversarialResult": "RECONCILED"
}
```

The loader rejects missing fields, malformed hashes/timestamps, or any result
other than the accepted values before deriving the foundation identity,
version, harness version, and build-contract version.

- [ ] **Step 3: Implement IconResolutionProbe.swift.**

Compile IconResolutionProbe.swift with xcrun swiftc -framework AppKit -framework CoreServices only. It invokes LSRegisterURL, resolves the exact standardized Release bundle URL via NSWorkspace.shared.urlForApplication(withBundleIdentifier:), inspects AppIcon via assetutil --info, renders the resolved AppIcon NSImage at exactly 512 x 512 sRGB IEC 61966-2.1 RGBA8, normalizes alpha, hashes row-major bytes with SHA-256, and compares manifest digest/marker pixel. It does not import PointerAppKit or perform guide lookup. GuideAssetCatalogBuildTests is the module-linked test for that separate contract.

- [ ] **Step 4: Implement idempotence and clean-clone assertions.**

Generate two sorted, path-stable manifests with distinct scopes. The
`source-manifest.sha256` contains every Git-tracked regular file selected by
the canonical pathspecs: `Package.swift`, `Sources/**`, `Tests/**`,
`scripts/**`, `Bundle/Assets.xcassets/**`,
`Bundle/AppIconIdentity.json`, `Bundle/GuideAssetIdentity.json`,
`Bundle/Info.plist`, and the required plan/design inputs: the master design
plus all six phase plans A through F:
`.codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md`,
`.codex/sdd/features/2026-08-23-pointer-a-observability-plan.md`,
`.codex/sdd/features/2026-08-23-pointer-b-lifecycle-correctness-plan.md`,
`.codex/sdd/features/2026-08-23-pointer-c-product-surface-accessibility-plan.md`,
`.codex/sdd/features/2026-08-23-pointer-d-visual-language-plan.md`,
`.codex/sdd/features/2026-08-23-pointer-e-performance-plan.md`, and
`.codex/sdd/features/2026-08-23-pointer-f-integration-validation-plan.md`.
These are source inputs and may include raw PNGs/imagesets. The script uses
`git ls-files -z`, filters regular files, sorts relative paths with `LC_ALL=C`,
and writes one canonical `<sha256>  <relative-path>` row per file. The
`fullSourceManifestSHA256` is the SHA-256 of those exact row bytes.

The `bundle-manifest.sha256` contains only runtime outputs:
`Contents/Resources/Assets.car`, the byte-identical
`Contents/Resources/GuideAssetIdentity.json`, `Contents/Info.plist`, and
`Contents/MacOS/Pointer`. Hash file bytes with `shasum -a 256` and write one
stable relative path-plus-digest row per output. Exclude generated reports,
`Contents/_CodeSignature/**`, `build/.Pointer.app.*/**` staging directories,
SwiftPM `.build/**`, mtimes, absolute paths, and ad-hoc signature metadata.
The source and bundle manifests are both required evidence; neither silently
substitutes for the other.

    source_paths=(Package.swift Sources Tests scripts Bundle/Assets.xcassets Bundle/AppIconIdentity.json Bundle/GuideAssetIdentity.json Bundle/Info.plist .codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md .codex/sdd/features/2026-08-23-pointer-a-observability-plan.md .codex/sdd/features/2026-08-23-pointer-b-lifecycle-correctness-plan.md .codex/sdd/features/2026-08-23-pointer-c-product-surface-accessibility-plan.md .codex/sdd/features/2026-08-23-pointer-d-visual-language-plan.md .codex/sdd/features/2026-08-23-pointer-e-performance-plan.md .codex/sdd/features/2026-08-23-pointer-f-integration-validation-plan.md)
    output_root=build
    git ls-files -z -- "${source_paths[@]}" | LC_ALL=C sort -z | while IFS= read -r -d '' path; do test -f "$path" && shasum -a 256 "$path"; done > "$output_root/source-manifest.sha256"
    shasum -a 256 "$output_root/Pointer.app/Contents/Resources/Assets.car" "$output_root/Pointer.app/Contents/Resources/GuideAssetIdentity.json" "$output_root/Pointer.app/Contents/Info.plist" "$output_root/Pointer.app/Contents/MacOS/Pointer" > "$output_root/bundle-manifest.sha256"
    resource_root="$output_root/Pointer.app/Contents/Resources"
    test -z "$(find -P "$resource_root" \( -type f -name '*.png' -o -type d \( -name '*.imageset' -o -name '*.xcassets' \) \) -print -quit)"

The build-contract test also creates nested sentinel directories named
`nested/guide.imageset` and `nested/guide.xcassets`, plus a nested `guide.png`,
under a temporary Resources tree and asserts this grouped predicate reports
each forbidden case before accepting the Release bundle.

After the second Release build, generate candidate source and bundle manifests
with the same commands and run `cmp -s` against the first pair; on mismatch
print `diff -u` and exit nonzero. Verify raw-asset absence on both builds. Run
the same source/bundle manifest and icon/catalog probe comparison from F's
scoped clean-clone checkout with no inherited build products; an earlier clean
or dirty claim is not reusable evidence.

- [ ] **Step 5: Run GREEN.**

This is the F-foundation bootstrap invocation; it must use the same four
explicit constants and only produces the candidate BuildProvenance used for
the later accepted-foundation artifact.

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh --output-root build \
      --foundation-identity pointer-f-foundation --foundation-version v1 \
      --harness-version pointer-performance-harness/v1 \
      --build-contract-version pointer-build-contract/v1 \
      --build-configuration release
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer POINTER_RELEASE_BUNDLE="$PWD/build/Pointer.app" swift test --filter GuideAssetCatalogBuildTests
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Tests/BuildScripts/test-build-contract.sh
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/verify.sh

Expected: Release bundle has exact resources/icon identity, idempotent build, valid plist/signature/arm64, deterministic smoke, and no raw xcassets acceptance.

GuideAssetCatalogBuildTests is an @MainActor XCTestCase in the module-linked
PointerBuildScriptsTests target. It imports PointerAppKit, resolves the Release
bundle path from `POINTER_RELEASE_BUNDLE`, decodes the identity file from the
bundle's `GuideAssetIdentity.json`, constructs the production
`GuideAssetCatalog(envelope:bundle:)` with that Release bundle, and calls
`catalog.image(for:variant:)` for every entry/variant. It derives source paths
with `GuideAssetSourceMapping` only from the source checkout, verifies every
serialized sourceSHA256 and source dimension against the tracked source PNG,
verifies every compiled image is nonnil and matches the variant dimensions,
and fails on missing/extra/unresolved entries. It also asserts that the
runtime bundle contains no raw asset files. This test owns no duplicate
lookup implementation; it exercises the production catalog against the
compiled `Assets.car` using the injected bundle.

## Task 4: Add CI, full gate, and final evidence schemas after E-execution

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
    func testCompletionMatrixRejectsPairOrderBootstrapOrImprovementClaimTampering()
    func testCompletionMatrixRequiresIndexedPairArtifactAndIdentityBoundManualEvidence()
    func testCompletionMatrixUsesReviseForMissingFailedOrUnmeasuredMetric()
    func testCompletionMatrixRequiresBothFixtureProfilesAndSeparateArtifacts()
    func testTask3cFinalizerRequiresThirtyPartialPairsAndWritesArtifactLast()

Expected: scripts/CI and final evidence files do not yet prove the complete
scope. This task cannot start until E-execution has produced reconciled
measurement, comparison, and resilience reports.

- [ ] **Step 2: Implement integrated gate.**

Run Release build first, then the full Swift suite and exactly
`swift test --filter PointerBuildScriptsTests`, followed by
plist/signature/arm64/resource/icon/idempotence checks, deterministic smoke,
the model-only benchmark, the already-reconciled E quality reports,
`git diff --check`, and clean-clone literal commands. Any test that invokes a
built executable is scheduled only after the Release build succeeds. CI must
use Xcode 15.4+ and macOS 14+ arm64 and must not claim physical coverage. The
final gate also reruns the Chrome friction inventory against the final F
candidate and the full immutable baseline hash from E; it must not reuse or
silently relabel D's checkpoint.

- [ ] **Step 3: Implement final reports.**

EvidenceLedger rows contain case, host/model, macOS/Xcode, connected displays,
permissions, date/time, exact steps, result, evidence path, and evidence class.
The authoritative F `ChromeFrictionReport` reruns the inventory against the
final F candidate, records the full immutable E baseline hash and candidate
identity, persistent control/row/status/focus counts, common-path
clicks/keys/steps, additions/removals, and disposition. The D Task 4
checkpoint is provenance only; it is linked as historical evidence and is
never relabeled as the final report. CompletionMatrix links
`standard12/{measurements,provenance,comparisons,resilience}/**` and
`dense1000/{measurements,provenance,comparisons,resilience}/**` to the
authoritative E evidence; each fixture profile must link its own baseline/candidate
  reports, pair-execution artifact at
  `pair-execution/pair-execution.json`, and comparison, and it maps every original
requirement to authoritative proof and marks missing/indirect/unsupported rows
  incomplete. It validates the canonical roots within one physical
  `<repo-root>`: `<repo-root>/build/<fixture-profile>/baseline` and
  `<repo-root>/build/<fixture-profile>/candidate`, with profile reports under
  `<repo-root>/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/`;
  no report or pair artifact may be reused across fixture profiles.
Task 3c's `PerformanceCampaignCompletionManifest` at
`.codex/sdd/reports/quality-campaign/performance/campaign-completion/manifest.json`
is the only aggregate completion contract: its fixed entries carry each
  `standard12ComparisonPath`/`standard12ComparisonSHA256` and
  `dense1000ComparisonPath`/`dense1000ComparisonSHA256` values for the exact
  profile-specific `comparisons/paired-comparison.json` paths and lowercase
  64-hex report hashes. Those path fields contain exactly the repo-relative
  strings `.codex/sdd/reports/quality-campaign/performance/standard12/comparisons/paired-comparison.json`
  and `.codex/sdd/reports/quality-campaign/performance/dense1000/comparisons/paired-comparison.json`,
  never absolute paths or paths from another repository root. It must name
  exactly one accepted comparison for each
  profile and reject missing, duplicate, or concatenated profiles. The two
  comparison artifacts and the manifest must share one physical performance
  root under the same `<repo-root>`. When `PerformanceCLI.run` invokes campaign
  completion, its `outputDirectory` argument must resolve to that physical
  repository root, not the `.codex/sdd/reports/quality-campaign/performance`
  directory. Both entries must share the same complete baseline/candidate
build lineage: source status/identity, source-manifest, executable, and
bundle-manifest hashes, build configuration, foundation, harness,
build-contract, and accepted-foundation values. Their complete measurement
environment and run host identity must also match. Task3c's
trial/finalize artifacts remain diagnostic `revise` and
cannot promote or write the manifest until F tasks 1–3 and typed external
trace/process/manual sidecars are accepted. After that gate, the F-owned
authoritative caller invokes `PerformanceCLI`
validated trial/finalize orchestration first, then invokes `PerformanceCLI`
compare and writes the completion manifest; `benchmark-quality.sh` never
invokes compare or writes the manifest. Each individual comparison persists
the baseline/candidate `PerformanceRunProvenance.configuration` values and full
`baselineFixture`/`candidateFixture` values; it requires matching fixture
profile/version/count and rejects cross-profile mixing. Its full
`baselineMeasurementIdentity` and
`candidateMeasurementIdentity`, exact host/macOS/Xcode/developerDirectory/
power/display/buildConfiguration equality, distinct source commits matching
run/build provenance, persisted lowercase 64-hex
`baselineMeasurementReportSHA256`/`candidateMeasurementReportSHA256` hashes
bound to the exact input report bytes; `writeComparison` computes and verifies
those hashes, injects them into the final report, and writes only after
validation; F retains the exact input reports unchanged.
F's acceptance test also rechecks the exact `--operation finalize` contract:
exactly 30 complete partial-pair files, sorted aggregate arrays, baseline and
candidate reports first, and the pair artifact as the last commit marker. The
test invokes the real `PerformanceCLI.run` finalize operation with its exact
argument order, and each profile/variant uses an independently valid lineage
fixture before any cross-profile campaign assertion.
It also validates the v1 raw timing arrays (`frameMilliseconds`, redraw/layout
`sampleMilliseconds`, `responseMilliseconds`, and input-to-visible
`sampleMilliseconds`) as exactly `trialCount` finite, strictly positive values
for measured reports, with p95 recomputation; failed/unmeasured diagnostics may
carry empty arrays. For measured frames, `missedFrameCount` must equal the
count of raw `frameMilliseconds` samples greater than 16.7 ms.

The retained artifact `records` are the sole observed `PairOrder` source:
records 0–14 must be baseline-first and 15–29 candidate-first, with baseline/
candidate sample indices and UTC start/end timestamps. Validation requires each
variant's start ≤ its own end, the first variant's end < the second
variant's start, and each pair's second end < the next pair's first start;
every metric pairs by recorded sample indices. F checks
deterministic bootstrap recomputation from deltas/seed/resample count,
rejects tampering, and accepts `improvementClaimed` only when the recomputed
delta upper bound is below zero; `acceptedNoRegression` is not an improvement
claim.
Any measurement report with a missing, failed, or unmeasured required metric
structurally requires disposition `revise`, never `blocked` or
`acceptedNoRegression`; comparison preflight rejects it
before constructing or writing any comparison, even though it blocks F-final
completion.
It also requires nonempty ratio/delta arrays of
exactly `totalPairs == pairsPerOrder * 2`. It also validates equal persisted
`baselineFixture`/`candidateFixture` values against their measurement reports,
the retained `pair-execution/pair-execution.json` artifact's 30 unique indexed records and
artifact hash; all metric samples are paired by recorded indices.
`benchmark-quality.sh` remains the producer that emits these records as it
invokes each pair. Manual
compositor/input evidence must bind both variants, commit/report hashes,
pair-artifact hash, procedure version, typed pair orders, host, paired
samples, and exactly the matching evidence file. Both variants must use the
same ordered steps, permissions, evidencePath, and shared procedureVersion.
The artifact and manual-evidence producers use the canonical sorted-key encoder;
the artifact SHA is SHA-256 of its canonical bytes and is recomputable from the
embedded artifact. Unknown fields, alternate whitespace, or alternate key
order are rejected before decoding/acceptance. Procedures must be equivalent.
The final report also validates the canonical `PerformanceMetricUnit`, finite
strictly positive baseline and candidate samples, and recomputed ratio median/
p95 at most `1.10`. Absolute
`budgetLimit` is optional and must equal the canonical value only for
`combinedFrame` (16.7 ms), `responsiveness` (100 ms), and `inputToVisible`
(100 ms); other metrics must carry nil budgets. For `memoryRSS`, comparison
samples are strictly positive absolute RSS bytes; signed
`finalWindowDeltaBytes` and `postWarmupSlopeBytesPerSecond` (B/s) remain
measurement-report fields validated during pair preflight, not comparison
sample units or an absolute RSS p95. It rejects a candidate in either
`standard12` or `dense1000` whose renderer p95 plus compositor p95 exceeds
16.7 ms or whose combinedFrame p95 exceeds 16.7 ms; those gates are
per-profile and never computed over concatenated samples. The report also
links the canonical 420-point narrow-display evidence and accepted A-harness
real-guide evidence before marking F-final complete.
The final report tests also exercise hash, identity, fixture, provenance, and
eligibility mismatches and assert no comparison output is created. They also
reject a missing/nonexistent manual-evidence directory or a nonempty directory
for a deterministic run, and assert no writer overload omits that directory.

- [ ] **Step 4: Run GREEN.**

This is a post-acceptance invocation and therefore must use the explicit
accepted foundation provenance path.

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh --output-root build \
      --foundation-provenance "$PWD/.codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json" \
      --build-configuration release
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PointerBuildScriptsTests
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/verify.sh
    git diff --check

Expected: all deterministic gates pass; the final Chrome report is based on
the final F candidate and full E baseline hash; physical rows remain explicit
until manual evidence is recorded.

## Task 5: Execute the clean-clone gate from the local branch

**Files:**

- Create: scripts/test-clean-clone.sh
- Modify: Tests/BuildScripts/test-build-contract.sh
- Create: Tests/BuildScripts/CleanCloneContractTests.swift
- Create at runtime: .codex/sdd/reports/quality-campaign/final/CleanCloneIdentity.md

- [ ] **Step 1: Write failing clean-clone contract tests.**

    func testCleanCloneScriptUsesCommittedSourceIdentityAndScopedDetachedWorktree()
    func testCleanCloneRunsReleaseBuildBeforeSmokeWithoutRemoteAccess()
    func testCleanCloneRunsBuiltSmokeBeforeVerifyScript()
    func testCleanCloneObservesCleanStatusAtInvocation()
    func testCleanCloneWritesFinalIdentityArtifactInExecutionOrder()
    func testCleanCloneFirstRunAndImmediateRerunExcludeGeneratedEvidence()
    func testBuildInvocationsDeclareOutputRootAndFoundationMode()

    The source-path test resolves the script root from #filePath, not the
    process current directory, and asserts the script contains mktemp, `git
    worktree add --detach` from a committed source identity, a trap cleanup,
    build-app.sh, `swift test --filter PointerBuildScriptsTests`, verify.sh,
    and smoke invocation before any application open. The ordering test asserts
    the Release build precedes provenance validation, the BuildScripts test,
    the direct built-executable `--smoke --format json` invocation, and then
    `verify.sh`. The clean-status test proves the script observes identity and
    `git status --porcelain --untracked-files=all` at invocation time, scoped
    to the canonical source inputs, rather than trusting a stale evidence
    file. The identity-artifact test requires
    the script to write
    `.codex/sdd/reports/quality-campaign/final/CleanCloneIdentity.md` with a
    UTC timestamp, source identity kind/value, observed clean status, exact
    commands and results, scoped worktree path, and cleanup outcome in that
    order, including a failed/precondition result when the source is dirty.
    The repeatability test runs the first clean-clone invocation and an
    immediate second invocation; both exclude the generated final report and
    temporary evidence from source cleanliness while still failing on an
    unrelated change inside the canonical input scope.
    The build-invocation test scans every documented `build-app.sh` command
    and rejects a bare invocation or one without `--output-root` plus either
    all four bootstrap constants or the accepted `--foundation-provenance`
    path.

- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CleanCloneContractTests

Expected: scripts/test-clean-clone.sh and the contract tests are absent.

- [ ] **Step 3: Implement the executable clean-clone protocol.**

    scripts/test-clean-clone.sh must observe and use this exact local-only sequence
at execution time after the coordinator's committed-source gate. It writes a
temporary identity artifact first, then publishes the final
`CleanCloneIdentity.md` only after cleanup so the source-manifest scope is not
changed by the evidence file itself:

    set -euo pipefail
    source_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
    evidence_path="$source_root/.codex/sdd/reports/quality-campaign/final/CleanCloneIdentity.md"
    current_step=initialization
    cleanup_status=not-run
    source_paths=(Package.swift Sources Tests scripts Bundle/Assets.xcassets Bundle/AppIconIdentity.json Bundle/GuideAssetIdentity.json Bundle/Info.plist .codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md .codex/sdd/features/2026-08-23-pointer-a-observability-plan.md .codex/sdd/features/2026-08-23-pointer-b-lifecycle-correctness-plan.md .codex/sdd/features/2026-08-23-pointer-c-product-surface-accessibility-plan.md .codex/sdd/features/2026-08-23-pointer-d-visual-language-plan.md .codex/sdd/features/2026-08-23-pointer-e-performance-plan.md .codex/sdd/features/2026-08-23-pointer-f-integration-validation-plan.md)
    current_step=observe-current-source
    source_identity="$(git -C "$source_root" rev-parse --verify HEAD^{commit})"
    source_status="$(git -C "$source_root" status --porcelain --untracked-files=all -- "${source_paths[@]}")"
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/pointer-clean-clone.XXXXXX")"
    clone_root="$fixture/repo"
    foundation_root="$fixture/foundation"
    evidence_tmp="$fixture/CleanCloneIdentity.md"
    cleanup_worktree() {
      foundation_cleanup=already-absent
      clone_cleanup=already-absent
      if [[ -n "$foundation_root" ]] && git -C "$source_root" worktree remove --force "$foundation_root" >/dev/null 2>&1; then
        foundation_cleanup=removed
      fi
      if [[ -n "$clone_root" ]] && git -C "$source_root" worktree remove --force "$clone_root" >/dev/null 2>&1; then
        clone_cleanup=removed
      fi
      cleanup_status="foundation:$foundation_cleanup,clone:$clone_cleanup"
    }
    trap 'exit_code=$?; set +e; cleanup_worktree; printf "\\n- exitCode: %s\\n- failingStep: %s\\n- cleanupOutcome: %s\\n" "$exit_code" "$current_step" "$cleanup_status" >> "$evidence_tmp"; mkdir -p "$(dirname -- "$evidence_path")"; mv -- "$evidence_tmp" "$evidence_path"; rm -rf -- "$fixture"; trap - EXIT; exit "$exit_code"' EXIT
    printf '# Clean-clone identity\n\n- currentStep: %s\n\n## Commands and results\n' "$current_step" > "$evidence_tmp"
    foundation_provenance=""
    while (( $# > 0 )); do
      case "$1" in
        --foundation-provenance) foundation_provenance="${2:?}"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
      esac
    done
    test -f "$foundation_provenance"
    foundation_identity="$(plutil -extract foundationIdentity.identity raw -o - "$foundation_provenance")"
    foundation_version="$(plutil -extract foundationIdentity.version raw -o - "$foundation_provenance")"
    harness_version="$(plutil -extract harnessVersion raw -o - "$foundation_provenance")"
    build_contract_version="$(plutil -extract buildContractVersion raw -o - "$foundation_provenance")"
    foundation_checkpoint_commit="$(plutil -extract checkpointCommitSHA raw -o - "$foundation_provenance")"
    current_step=load-foundation-provenance
    recorded_at_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    current_step=observe-current-source
    current_source_head="$source_identity"
    test "$foundation_checkpoint_commit" = "${foundation_checkpoint_commit##*[!0-9a-fA-F]*}"
    test "${#foundation_checkpoint_commit}" -eq 40
    git -C "$source_root" merge-base --is-ancestor "$foundation_checkpoint_commit" "$current_source_head"
    current_step=hash-current-source
    source_manifest="$fixture/source-manifest.sha256"
    (cd "$source_root" && git ls-files -z -- \
      'Package.swift' 'Sources/**' 'Tests/**' 'scripts/**' \
      'Bundle/Assets.xcassets/**' 'Bundle/AppIconIdentity.json' \
      'Bundle/GuideAssetIdentity.json' 'Bundle/Info.plist' \
      '.codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md' \
      '.codex/sdd/features/2026-08-23-pointer-a-observability-plan.md' \
      '.codex/sdd/features/2026-08-23-pointer-b-lifecycle-correctness-plan.md' \
      '.codex/sdd/features/2026-08-23-pointer-c-product-surface-accessibility-plan.md' \
      '.codex/sdd/features/2026-08-23-pointer-d-visual-language-plan.md' \
      '.codex/sdd/features/2026-08-23-pointer-e-performance-plan.md' \
      '.codex/sdd/features/2026-08-23-pointer-f-integration-validation-plan.md' \
      | LC_ALL=C sort -z | while IFS= read -r -d '' path; do \
        test -f "$path" && shasum -a 256 "$path"; \
      done) > "$source_manifest"
    current_source_manifest_sha="$(shasum -a 256 "$source_manifest" | awk '{print $1}')"
    current_step=hash-foundation-source
    foundation_root="$fixture/foundation"
    git -C "$source_root" worktree add --detach "$foundation_root" "$foundation_checkpoint_commit"
    foundation_manifest="$fixture/foundation-source-manifest.sha256"
    (cd "$foundation_root" && git ls-files -z -- \
      'Package.swift' 'Sources/**' 'Tests/**' 'scripts/**' \
      'Bundle/Assets.xcassets/**' 'Bundle/AppIconIdentity.json' \
      'Bundle/GuideAssetIdentity.json' 'Bundle/Info.plist' \
      '.codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md' \
      '.codex/sdd/features/2026-08-23-pointer-a-observability-plan.md' \
      '.codex/sdd/features/2026-08-23-pointer-b-lifecycle-correctness-plan.md' \
      '.codex/sdd/features/2026-08-23-pointer-c-product-surface-accessibility-plan.md' \
      '.codex/sdd/features/2026-08-23-pointer-d-visual-language-plan.md' \
      '.codex/sdd/features/2026-08-23-pointer-e-performance-plan.md' \
      '.codex/sdd/features/2026-08-23-pointer-f-integration-validation-plan.md' \
      | LC_ALL=C sort -z | while IFS= read -r -d '' path; do \
        test -f "$path" && shasum -a 256 "$path"; \
      done) > "$foundation_manifest"
    foundation_manifest_sha="$(shasum -a 256 "$foundation_manifest" | awk '{print $1}')"
    accepted_foundation_manifest_sha="$(plutil -extract fullSourceManifestSHA256 raw -o - "$foundation_provenance")"
    test "$foundation_manifest_sha" = "$accepted_foundation_manifest_sha"
    current_step=write-identity-header
    printf '# Clean-clone identity\n\n- recordedAtUTC: %s\n- sourceIdentityKind: sourceCommitSHA\n- sourceIdentityValue: %s\n- sourceTreeStatus: %s\n- currentSourceManifestSHA256: %s\n- foundationSourceManifestSHA256: %s\n- checkpointCommitSHA: %s\n- foundationIdentity: %s\n- foundationVersion: %s\n- harnessVersion: %s\n- buildContractVersion: %s\n- worktreePath: %s\n\n## Commands and results\n' \
      "$recorded_at_utc" "$source_identity" \
      "$(test -n "$source_status" && echo dirty || echo clean)" \
      "$current_source_manifest_sha" "$foundation_manifest_sha" \
      "$foundation_checkpoint_commit" "$foundation_identity" "$foundation_version" \
      "$harness_version" "$build_contract_version" "$clone_root" > "$evidence_tmp"
    printf '%s\n' "command: git status --porcelain --untracked-files=all" "result: $(test -n "$source_status" && echo dirty || echo clean)" >> "$evidence_tmp"
    test -z "$source_status"
    test -n "$source_identity"
    printf '%s\n' "command: git merge-base --is-ancestor $foundation_checkpoint_commit $current_source_head" "result: 0" >> "$evidence_tmp"
    printf '%s\n' "command: compare foundation checkpoint source manifest to accepted foundation artifact" "result: 0" >> "$evidence_tmp"
    printf '%s\n' "currentSourceManifestSHA256: $current_source_manifest_sha" "foundationSourceManifestSHA256: $foundation_manifest_sha" >> "$evidence_tmp"
    current_step=create-clean-clone
    git -C "$source_root" worktree add --detach "$clone_root" "$source_identity"
    printf '%s\n' "command: git worktree add --detach $clone_root $source_identity" "result: 0" >> "$evidence_tmp"
    current_step=build-release
    output_root=build
    (cd "$clone_root" && DEVELOPER_DIR="${DEVELOPER_DIR:?}" ./scripts/build-app.sh --output-root "$output_root" --foundation-provenance "$foundation_provenance" --build-configuration release)
    printf '%s\n' 'command: DEVELOPER_DIR=$DEVELOPER_DIR ./scripts/build-app.sh --output-root $output_root --foundation-provenance $foundation_provenance --build-configuration release' 'result: 0' >> "$evidence_tmp"
    current_step=validate-build-provenance
    build_provenance="$clone_root/$output_root/provenance.json"
    test -f "$build_provenance"
    actual_executable_sha="$(shasum -a 256 "$clone_root/$output_root/Pointer.app/Contents/MacOS/Pointer" | awk '{print $1}')"
    actual_bundle_manifest_sha="$(shasum -a 256 "$clone_root/$output_root/bundle-manifest.sha256" | awk '{print $1}')"
    foundation_artifact_sha="$(shasum -a 256 "$foundation_provenance" | awk '{print $1}')"
    test "$(plutil -extract sourceManifestSHA256 raw -o - "$build_provenance")" = "$current_source_manifest_sha"
    test "$(plutil -extract executableSHA256 raw -o - "$build_provenance")" = "$actual_executable_sha"
    test "$(plutil -extract bundleManifestSHA256 raw -o - "$build_provenance")" = "$actual_bundle_manifest_sha"
    test "$(plutil -extract acceptedFoundationArtifactSHA256 raw -o - "$build_provenance")" = "$foundation_artifact_sha"
    test "$(plutil -extract buildConfiguration raw -o - "$build_provenance")" = release
    test "$(plutil -extract foundation.identity raw -o - "$build_provenance")" = "$foundation_identity"
    test "$(plutil -extract foundation.version raw -o - "$build_provenance")" = "$foundation_version"
    test "$(plutil -extract harnessVersion raw -o - "$build_provenance")" = "$harness_version"
    test "$(plutil -extract buildContractVersion raw -o - "$build_provenance")" = "$build_contract_version"
    printf '%s\n' 'command: validate $output_root/provenance.json against current source/executable/bundle hashes and foundation versions' 'result: 0' >> "$evidence_tmp"
    executable_sha="$(shasum -a 256 "$clone_root/$output_root/Pointer.app/Contents/MacOS/Pointer" | awk '{print $1}')"
    bundle_manifest_sha="$(shasum -a 256 "$clone_root/$output_root/bundle-manifest.sha256" | awk '{print $1}')"
    printf '%s\n' "executableSHA256: $executable_sha" "bundleManifestSHA256: $bundle_manifest_sha" >> "$evidence_tmp"
    current_step=run-buildscripts-tests
    (cd "$clone_root" && DEVELOPER_DIR="${DEVELOPER_DIR:?}" swift test --filter PointerBuildScriptsTests)
    printf '%s\n' 'command: DEVELOPER_DIR=$DEVELOPER_DIR swift test --filter PointerBuildScriptsTests' 'result: 0' >> "$evidence_tmp"
    current_step=run-smoke
    (cd "$clone_root" && "$output_root/Pointer.app/Contents/MacOS/Pointer" --smoke --format json >/dev/null)
    printf '%s\n' 'command: $output_root/Pointer.app/Contents/MacOS/Pointer --smoke --format json' 'result: 0' >> "$evidence_tmp"
    current_step=run-verify
    (cd "$clone_root" && DEVELOPER_DIR="${DEVELOPER_DIR:?}" ./scripts/verify.sh)
    printf '%s\n' 'command: DEVELOPER_DIR=$DEVELOPER_DIR ./scripts/verify.sh' 'result: 0' >> "$evidence_tmp"

The `--foundation-provenance` loader resolves foundation identity/version,
harness version, build-contract version, and checkpoint commit from the
accepted F-foundation artifact and rejects missing or malformed values; no
hidden environment variable supplies them. The script recomputes the
foundation-checkpoint source manifest in a temporary foundation worktree,
compares it to the accepted artifact, and separately records the current
source manifest. It records the executable SHA-256 and bundle manifest SHA-256
after the Release build and fails if either cannot be computed. The final
artifact therefore records UTC time, identity kind/value, observed clean
status, both source-manifest SHAs and the checkpoint commit, executable/bundle hashes,
foundation identity/version, harness/build-contract versions, exact commands
and results, scoped worktree path, and cleanup outcome in execution order.

The script must fail if `source_identity` is unavailable, the source worktree is
dirty when the script starts, the scoped worktree is not created, or the
Release bundle/smoke contract fails. It must not call git clone, archive a
mutable working tree, fetch, pull, or a remote URL. The exit trap records every
command/result, cleanup outcome, observed `source_identity`, source status,
both source-manifest SHAs, checkpoint commit, and UTC timestamp in the final
clean-clone evidence,
then removes only the scoped temporary worktree. A prior report claiming clean
or dirty status is not evidence for this invocation. The coordinator's commit
gate must make the six plan/design documents and reconciled implementation
available at that identity before invoking this script.

- [ ] **Step 4: Run the clean-clone gate.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/test-clean-clone.sh \
      --foundation-provenance "$PWD/.codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json"

    Expected: the scoped temporary checkout builds Release, validates its
    per-build provenance, runs `swift test --filter PointerBuildScriptsTests`,
    directly invokes the built executable with `--smoke --format json`, then
    runs `verify.sh`; all occur before any live window is opened.

## Task 6: Execute the complete manual-use matrix

**Files:**

- Create: .codex/sdd/reports/quality-campaign/final/ManualUseReport.md
- Modify: .codex/sdd/reports/quality-campaign/final/EvidenceLedger.md

- [ ] **Step 1: Run host-capability preflight.**

Record host/model, macOS/Xcode, connected displays, full-screen/Space
capability, VoiceOver, Reduce Transparency, Increase Contrast, permissions,
and date/time. Include the canonical 420-point narrow-display fixture result
and link the accepted A-harness real-guide lifecycle evidence before starting
the final matrix. A missing capability or prerequisite is an exact gap, not a
pass.

- [ ] **Step 2: Exercise the built app directly.**

Record launch standby; annotation toggle; arrow, rectangle, ellipse, pen, emoji, spotlight; select/move/resize/delete; undo, clear, swept erase; palette drag/re-show; Escape/menu bar; shortcut change/conflict/timeout/recovery/relaunch; narrow/wide palette; keyboard-only; VoiceOver; dark/light/contrast; display pointer placement; two displays; full-screen Spaces; disconnect/reconnect/no-display; denied permissions; long session; and fresh-defaults first-use guide launch/reopen/Close/Done/Escape/annotation dismissal/display loss/reconnect/stop-start. For the guide row, run Pointer under accessory activation policy while another app is frontmost and record the app-active state before and after showing it; verify guide key-window and Done focus, physical Return dismissal, return of focus to the prior app, Close/Escape/annotation dismissal, reopen and restart behavior, display-loss/reconnect behavior, and that no orphan panel or appearance observer remains while the seen-state and resource checkpoint stay exact. Explicitly verify guide placement receives the palette frame and avoidance rects, stays clamped beside the palette, and does not cover a presentation target. Explicitly verify standby keeps marks/undo but removes selection/handles/Delete and requires re-selection.

- [ ] **Step 3: Record every row.**

Each row records exact steps, observed result, evidence path, and whether proof is physical/manual or deterministic. Every capable-but-untested, failed, or missing-field row remains incomplete.

- [ ] **Step 4: Run final application-level review.**

Require no unresolved blocker/high-severity finding, reviewed issue ledger entries with reproduction/evidence/owner/fix/reviewer/adversarial result/verification, and a second fresh audit that finds no meaningful new issue. Lower-severity residuals require a reason and bounded follow-up.

## Task 7: Reconciliation gate

- [ ] **Step 1:** Run `git status --short`, `git diff --check`, and verify
  F-only paths plus accepted A–E reports. Confirm the final
  `ChromeFrictionReport` names the final F candidate and the full immutable E
  baseline hash; D's checkpoint remains provenance only.
- [ ] **Step 2:** Run full tests, Release/build contract, raw-asset absence and
  source/bundle manifest idempotence, clean-clone, smoke, model-only benchmark,
  E performance disposition, and manual evidence ledger. Confirm the
  canonical 420-point narrow-display and A-harness real-guide prerequisites
  are linked before accepting F-final.
- [ ] **Step 3:** Hand all diffs/reports to the configured Luna reviewer; reviewer returns REVISE or APPROVED with architecture, security, accessibility, resource, and evidence findings.
- [ ] **Step 4:** After approval, adversarial Codex re-reads the objective/design and challenges composition lifetime, diagnostic branch isolation, icon identity, raw asset copies, clean-clone reproducibility, manual case coverage, evidence-class honesty, dirty-checkout boundaries, and every completion-matrix row.
- [ ] **Step 5:** Return findings to the owning worker, rerun the relevant gates, obtain reviewer approval, and repeat Codex review until all workstreams reconcile. Do not mark complete while any completion row is indirect, unsupported, untested, or missing.

## Plan self-check

Composition target/identity with an injected resource bundle, exact
import-line exclusion, declared BuildScripts target,
Release-before-executable-test ordering, model-only versus full-quality CLI
report contracts, Release/icon/build contracts with compiled-only runtime
assets, the canonical full Git-tracked source-manifest scope/aggregate,
typed provenance and executable/bundle hash correspondence, distinct
source/bundle manifests and directory-aware raw-asset absence,
CI/full validation, final evidence reports, canonical narrow and real-guide
prerequisites, complete manual matrix, execution-time clean-clone proof with
ordered `CleanCloneIdentity.md`, final Chrome friction rerun, and
reviewer/adversarial reconciliation are covered.
No commit step or out-of-scope product feature is included.
