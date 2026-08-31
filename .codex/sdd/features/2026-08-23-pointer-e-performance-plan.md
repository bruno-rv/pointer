# Pointer E — Performance and Resilience Measurement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking. The coordinating agent owns commits and publication; worker tasks end with evidence/status handoff instead of commit steps.

**Goal:** Measure the production model, renderer, compositor, launch, allocation, redraw, responsiveness, input-to-visible, memory, and resilience paths with immutable paired evidence, then return only measured regressions or fixes to the owning workstream.

**Architecture:** Preserve GestureBenchmark's real PointerSession API and fixed
12-mark/240-sample/5-warmup/30-trial model run. The
`--benchmark-gestures --format json` command remains the model-only
`GestureBenchmark.Result` output. `PerformanceHarness` produces one variant
`PerformanceMeasurementReport`; the separate
`PerformanceComparisonHarness` consumes immutable baseline/candidate
measurement reports and produces the paired `PerformanceComparisonReport`.
E owns diagnostics, benchmark contracts, fixtures, and performance reports;
measured findings return to the named prior-phase owner:
A-foundation/A-harness, B-core/B-render-integration, C-product-surface, or
D-visual-language.

**Tech Stack:** Swift tools 5.10, macOS 14+, AppKit, PointerCore, PointerAppKit, XCTest, ContinuousClock, Codable, os_signpost/instrumentation available on host, fixed-seed bootstrap statistics.

**Spec:** .codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md (Workstream E — performance and resilience measurement).

## Global Constraints

- Do not claim a performance improvement without before/after measurements from the same production path and fixture.
- Structurally valid measurement reports may contain `measured`, `failed`, or
  `unmeasured` statuses; completion validation rejects failed or unmeasured
  required metrics, and `not_applicable` is never permitted. Comparison
  inputs are stricter: `PerformanceComparisonHarness` rejects any failed or
  unmeasured required metric before it constructs or writes a comparison, so a
  persisted comparison contains measured comparisons only.
- Every comparison uses immutable commit SHA or SHA-256 content manifest identities, the same host/fixture, five warmups, `pairsPerOrder == 15`, and `totalPairs == pairsPerOrder * 2 == 30`: exactly 15 baseline-first and 15 candidate-first pairs. It uses a fixed-seed 10,000-resample bootstrap interval.
- A candidate/baseline median or p95 ratio greater than 1.10, frame/input budget breach, leak, invalid schema, or required unmeasured metric is REVISE and blocks completion.
- At 60 Hz equivalent, p95 render plus compositor work is at most 16.7 ms for 12-mark and dense 1,000-mark fixtures; no repeatable active-gesture main-thread stall exceeds 100 ms; p95 input-to-visible is at most 100 ms.
- Memory is a 600-second, 5-second sample-interval time series with running, stopping, stopped, and restarted phases; running plateau and stop/restart checkpoints are separate.
- Performance fixes address a measured bottleneck in an owning workstream; no speculative cache, concurrency, dependency, or abstraction is accepted.
- Full end-to-end interaction measurement depends on accepted A-foundation
  smoke/fixtures, B-core lifecycle contracts, B-render-integration CanvasView
  render path, C-product-surface active-shortcut/metadata contracts,
  D-visual-language renderer/guide assets, and the A-harness
  CanvasIntegrationHarnessTests phase. E tasks 1–3 define and validate the
  benchmark, schema, and harness contracts after A-harness. E's paired
  immutable execution is held until F tasks 1–3 provide the executable
  composition, launcher, and Release resource foundation. Model-only
  measurement may run after A-foundation and B-core, but it is never treated
  as end-to-end evidence.
- Allowed instrumentation adapters are real offscreen CanvasView/CGContext renderer timing, os_signpost/CACurrentMediaTime WindowServer/compositor timing where available, /usr/bin/time/task_info/process metrics for launch/memory, and a manual physical metric adapter. No adapter may synthesize input, install global monitors/event taps, capture the screen, or replace the production route. Deterministic and manual evidence remain separate; missing required measured evidence blocks completion.
- Work only in /Users/bruno/Dev/pointer/.worktrees/stable-app; E owns
  Diagnostics/GestureBenchmark.swift, PerformanceHarness.swift,
  PerformanceComparisonHarness.swift, PerformanceCLI.swift, their tests,
  benchmark scripts/fixtures, and
  `.codex/sdd/reports/quality-campaign/performance/measurements/**`,
  `provenance/**`, `comparisons/**`, and `resilience/**` only. E task 3 defines the immutable
  protocol and CLI contracts; E-execution runs those commands only after the
  F-foundation checkpoint described below.

E uses the canonical source-manifest scope from the master design for every
baseline and candidate. The script runs `git ls-files` with these exact
pathspecs: `Package.swift`, `Sources/**`, `Tests/**`, `scripts/**`,
`Bundle/Assets.xcassets/**`, `Bundle/AppIconIdentity.json`,
`Bundle/GuideAssetIdentity.json`, `Bundle/Info.plist`, and the required
plan/design inputs under `.codex/sdd/features/` (the master design plus all
six phase plans A through F). It sorts the Git-tracked relative paths with
`LC_ALL=C`, writes
one `<sha256>  <relative-path>` byte row per file to
`source-manifest.sha256`, and hashes those exact rows to obtain the 64-hex
`fullSourceManifestSHA256`. Generated reports, `build/**`, SwiftPM `.build/**`,
code-signature metadata, mtimes, absolute paths, and untracked files are
excluded. E baseline/candidate and F clean-clone must use this same scope,
row format, aggregate, and exclusions; a scope mismatch is invalid.

## Phase sequencing and eligibility gates

E has two explicit gates so its report schema can be implemented before the
launcher and Release bundle exist, without allowing a paired result to depend
on a stale or incomplete executable. The sequence is:

1. **E-foundation (tasks 1–3):** implement and structurally test
   `GestureBenchmark.Result`, typed measurement/comparison schemas, validators,
   adapters, and the CLI/script argument contracts. These tasks may not pin a
   baseline, run a paired comparison, or claim performance completion.
2. **F-foundation (tasks 1–3):** implement and gate the importable composition,
   diagnostic launcher branches, compiled Release resources, and the
   `Assets.car`/guide identity contract. F must pass its worker/reviewer/
   adversarial gate before E-execution starts.
3. **E-execution:** resolve a baseline and candidate from the same E schema and
   harness, with the F launcher/build foundation present, then run the paired
   immutable measurements and E reconciliation gate. Pin the baseline only
   after that foundation checkpoint; the authoritative candidate is a
   subsequent measured commit. Content-manifest measurements remain
   diagnostic-only and are never promoted into the paired comparison.
4. **F-final (tasks 4–7):** consume the reconciled E reports and run CI,
   clean-clone, manual use, Chrome friction, and final aggregation.

Baseline eligibility requires all of the following: the baseline and candidate
use the same E schema version, typed `harnessVersion`,
`foundationIdentity`/version, `buildContractVersion`, and fixture
configuration; both use the F launcher/build foundation; the baseline
  identity is observed and pinned after the F-foundation checkpoint; and the
  candidate is a different subsequent measured identity. A clean source tree
uses `sourceCommitSHA`; a dirty tree uses `contentManifestSHA256` calculated
from the canonical full source manifest. The measured executable's SHA-256
must match the provenance artifact and its build/bundle manifest. The
clean-clone condition is observed at execution time by the gate script;
neither a previous report nor a documentation claim can satisfy it.

---

## Interfaces

    public enum MeasurementStatus: String, Codable, Sendable {
        case measured
        case failed
        case unmeasured
    }

    public enum Disposition: String, Codable, Sendable {
        case acceptedNoRegression
        case revise
        case blocked
    }

    public enum PerformanceReportKind: String, Codable, Sendable {
        case measurement
        case comparison
    }

    public enum MemoryPhase: String, Codable, Sendable {
        case running
        case stopping
        case stopped
        case restarted
    }

    public struct MeasurementIdentity: Codable, Sendable {
        public let sourceCommitSHA: String?
        public let contentManifestSHA256: String?
        public let hostModel: String
        public let macOSVersion: String
        public let xcodeVersion: String
        public let developerDirectory: String
        public let powerState: String
        public let displayState: String
        public let buildConfiguration: String
    }

    public enum SourceIdentityKind: String, Codable, Sendable {
        case sourceCommitSHA
        case contentManifestSHA256
    }

    public enum SourceTreeStatus: String, Codable, Sendable {
        case clean
        case dirty
    }

    public struct SourceIdentity: Codable, Sendable, Equatable {
        public let kind: SourceIdentityKind
        public let value: String
    }

    public struct FoundationIdentity: Codable, Sendable, Equatable {
        public let identity: String
        public let version: String
    }

    public struct ValidatedFoundationProvenance: Codable, Sendable, Equatable {
        public let path: String
        public let foundation: FoundationIdentity
        public let checkpointCommitSHA: String
        public let fullSourceManifestSHA256: String
        public let harnessVersion: String
        public let buildContractVersion: String
    }

    public struct PerformancePairEligibility: Codable, Sendable, Equatable {
        public let baselineRoot: String
        public let candidateRoot: String
        public let baselineCommitSHA: String
        public let candidateCommitSHA: String
        public let foundationProvenance: ValidatedFoundationProvenance
    }

    public struct BuildProvenance: Codable, Sendable, Equatable {
        public let sourceTreeStatus: SourceTreeStatus
        public let sourceIdentity: SourceIdentity
        public let sourceManifestSHA256: String
        public let executableSHA256: String
        public let bundleManifestSHA256: String
        public let recordedAtUTC: String
        public let foundation: FoundationIdentity
        public let harnessVersion: String
        public let buildContractVersion: String
        public let acceptedFoundationArtifactSHA256: String?
    }

    public struct PerformanceRunProvenance: Codable, Sendable, Equatable {
        public let variant: String
        public let outputRoot: String
        public let sourceRef: String
        public let build: BuildProvenance
        public let foundationProvenancePath: String
        public let foundation: FoundationIdentity
        public let harnessVersion: String
        public let buildContractVersion: String
    }

    public struct HostIdentity: Codable, Sendable {
        public let machineIdentifier: String
        public let processArchitecture: String
        public let connectedDisplayUUIDs: [String]
    }

    public struct FixtureIdentity: Codable, Sendable {
        public let identifier: String
        public let markCount: Int
        public let continuationSamples: Int
        public let warmupCount: Int
        public let trialCount: Int
        public let seed: UInt64
    }

    public struct ModelMeasurement: Codable, Sendable {
        public let status: MeasurementStatus
        public let trialNanoseconds: [Double]
        public let medianNanoseconds: Double
        public let p95Nanoseconds: Double
        public let madNanoseconds: Double
        public let publicationCount: Int
        public let modelChecksum: String
        public let finalStateValid: Bool
    }

    public struct FrameMeasurement: Codable, Sendable {
        public let status: MeasurementStatus
        public let sampleCount: Int
        public let p95Milliseconds: Double
        public let frameCount: Int
        public let missedFrameCount: Int
        public let instrumentationStatus: String
    }

    public struct LaunchMeasurement: Codable, Sendable {
        public let status: MeasurementStatus
        public let coldMilliseconds: [Double]
        public let warmMilliseconds: [Double]
    }

    public struct AllocationMeasurement: Codable, Sendable {
        public let status: MeasurementStatus
        public let bytesPerGesture: [Int64]
        public let peakAllocationBytes: Int64
    }

    public struct RedrawLayoutMeasurement: Codable, Sendable {
        public let status: MeasurementStatus
        public let redrawsPerSample: [Int]
        public let layoutPasses: [Int]
        public let p95Milliseconds: Double
    }

    public struct ResponsivenessMeasurement: Codable, Sendable {
        public let status: MeasurementStatus
        public let stallCount: Int
        public let maximumMainThreadStallMilliseconds: Double
        public let p95ResponseMilliseconds: Double
    }

    public struct InputToVisibleMeasurement: Codable, Sendable {
        public let status: MeasurementStatus
        public let sampleCount: Int
        public let p95Milliseconds: Double
        public let missedSampleCount: Int
    }

    public struct ResourceCounts: Codable, Sendable, Equatable {
        public let overlays: Int
        public let timers: Int
        public let handlers: Int
        public let windows: Int
        public let observers: Int
    }

    public struct MemorySample: Codable, Sendable {
        public let elapsedSeconds: Double
        public let rssBytes: Int64
        public let phase: MemoryPhase
        public let resources: ResourceCounts
    }

    public struct MemoryAggregate: Codable, Sendable {
        public let intervalIndex: Int
        public let sampleCount: Int
        public let meanRSSBytes: Int64
        public let peakRSSBytes: Int64
    }

    public struct MemoryMeasurement: Codable, Sendable {
        public let status: MeasurementStatus
        public let windowSeconds: Int
        public let sampleIntervalSeconds: Int
        public let samples: [MemorySample]
        public let aggregates: [MemoryAggregate]
        public let peakRSSBytes: Int64
        public let finalWindowDeltaBytes: Int64
        public let finalWindowDeltaPercent: Double
        public let matchedBaselineSeries: [Double]
        public let matchedBaselineValues: [Int64]
        public let peakLiveResourceCounts: ResourceCounts
        public let endLiveResourceCounts: ResourceCounts
    }

    public struct PerformanceConfiguration: Codable, Sendable {
        public let fixtureMarkCount: Int
        public let samplesPerGesture: Int
        public let warmupCount: Int
        public let trialCount: Int
        public let pairsPerOrder: Int
        public let bootstrapSeed: UInt64
        public let bootstrapResamples: Int
        public let memoryWindowSeconds: Int
        public let memorySampleIntervalSeconds: Int
        public let harnessVersion: String
        public let foundationIdentity: FoundationIdentity
        public let buildContractVersion: String

        public static let standard = PerformanceConfiguration(
            fixtureMarkCount: 12,
            samplesPerGesture: 240,
            warmupCount: 5,
            trialCount: 30,
            pairsPerOrder: 15,
            bootstrapSeed: 48271,
            bootstrapResamples: 10_000,
            memoryWindowSeconds: 600,
            memorySampleIntervalSeconds: 5,
            harnessVersion: "pointer-performance-harness/v1",
            foundationIdentity: FoundationIdentity(
                identity: "pointer-f-foundation",
                version: "v1"
            ),
            buildContractVersion: "pointer-build-contract/v1"
        )

        public var totalPairs: Int { pairsPerOrder * 2 }
    }

    public struct BootstrapInterval: Codable, Sendable, Equatable {
        public let lowerDelta: Double
        public let upperDelta: Double
        public let seed: UInt64
        public let resampleCount: Int
    }

    public enum MetricEvidenceClass: String, Codable, Sendable {
        case deterministic
        case manual
    }

    public enum PerformanceMetricID: String, CaseIterable, Codable, Sendable {
        case model
        case renderer
        case compositor
        case combinedFrame
        case launchCold
        case launchWarm
        case allocations
        case redrawLayout
        case responsiveness
        case inputToVisible
        case memoryRSS
    }

    public struct MetricComparison: Codable, Sendable {
        public let metricID: PerformanceMetricID
        public let evidenceClass: MetricEvidenceClass
        public let baselineID: String
        public let candidateID: String
        public let baselineSamples: [Double]
        public let candidateSamples: [Double]
        public let ratios: [Double]
        public let deltas: [Double]
        public let bootstrapInterval: BootstrapInterval
        public let manualEvidence: ManualMetricEvidence?
        public let disposition: Disposition
    }

    public struct ResilienceCase: Codable, Sendable {
        public let identifier: String
        public let status: MeasurementStatus
        public let iterationCount: Int
        public let peakResourceCounts: ResourceCounts
        public let endResourceCounts: ResourceCounts
        public let leakedResource: Bool
        public let unexpectedGrowth: Bool
    }

    public struct ResilienceMeasurement: Codable, Sendable {
        public let status: MeasurementStatus
        public let cases: [ResilienceCase]
        public let disposition: Disposition
    }

    public struct PerformanceMeasurementReport: Codable, Sendable {
        public let reportKind: PerformanceReportKind
        public let schemaVersion: Int
        public let harnessVersion: String
        public let foundationIdentity: FoundationIdentity
        public let buildContractVersion: String
        public let buildProvenance: BuildProvenance
        public let runProvenance: PerformanceRunProvenance
        public let identity: MeasurementIdentity
        public let host: HostIdentity
        public let fixture: FixtureIdentity
        public let model: ModelMeasurement
        public let renderer: FrameMeasurement
        public let compositor: FrameMeasurement
        public let combinedFrame: FrameMeasurement
        public let launch: LaunchMeasurement
        public let allocations: AllocationMeasurement
        public let redrawLayout: RedrawLayoutMeasurement
        public let responsiveness: ResponsivenessMeasurement
        public let inputToVisible: InputToVisibleMeasurement
        public let memory: MemoryMeasurement
        public let resilience: ResilienceMeasurement
        public let disposition: Disposition
        public func validateStructure() throws
        public func validateCompletion() throws
    }

    @MainActor
    public enum PerformanceHarness {
        public static func measureModel(configuration: PerformanceConfiguration) -> ModelMeasurement
        public static func measureRenderer(configuration: PerformanceConfiguration) -> FrameMeasurement
        public static func measureCompositor(configuration: PerformanceConfiguration) -> FrameMeasurement
        public static func measureCombinedFrame(configuration: PerformanceConfiguration) -> FrameMeasurement
        public static func measureLaunch(configuration: PerformanceConfiguration) -> LaunchMeasurement
        public static func measureAllocations(configuration: PerformanceConfiguration) -> AllocationMeasurement
        public static func measureRedrawLayout(configuration: PerformanceConfiguration) -> RedrawLayoutMeasurement
        public static func measureResponsiveness(configuration: PerformanceConfiguration) -> ResponsivenessMeasurement
        public static func measureInputToVisible(configuration: PerformanceConfiguration) -> InputToVisibleMeasurement
        public static func measureMemory(configuration: PerformanceConfiguration) -> MemoryMeasurement
        public static func measureResilience(configuration: PerformanceConfiguration) -> ResilienceMeasurement
        public static func run(configuration: PerformanceConfiguration) throws -> PerformanceMeasurementReport
    }

    @MainActor
    public enum PerformanceComparisonHarness {
        public static func compare(
            baseline: PerformanceMeasurementReport,
            candidate: PerformanceMeasurementReport,
            configuration: PerformanceConfiguration,
            eligibility: PerformancePairEligibility
        ) throws -> PerformanceComparisonReport
        public static func writeComparison(
            baselineURL: URL,
            candidateURL: URL,
            manualEvidenceDirectory: URL,
            outputDirectory: URL,
            configuration: PerformanceConfiguration,
            eligibility: PerformancePairEligibility
        ) throws -> PerformanceComparisonReport
    }

    public struct PerformanceComparisonReport: Codable, Sendable {
        public let reportKind: PerformanceReportKind
        public let schemaVersion: Int
        public let harnessVersion: String
        public let foundationIdentity: FoundationIdentity
        public let buildContractVersion: String
        public let baselineBuildProvenance: BuildProvenance
        public let candidateBuildProvenance: BuildProvenance
        public let runProvenance: PerformanceRunProvenance
        public let pairEligibility: PerformancePairEligibility
        public let baselineID: String
        public let candidateID: String
        public let metrics: [MetricComparison]
        public let resilience: ResilienceMeasurement
        public let seed: UInt64
        public let resampleCount: Int
        public let disposition: Disposition
        public func validateStructure() throws
        public func validateCompletion() throws
    }

    @MainActor
    public protocol RendererInstrumentationAdapter: AnyObject {
        func measureRenderer(configuration: PerformanceConfiguration) -> FrameMeasurement
    }

    @MainActor
    public protocol CompositorInstrumentationAdapter: AnyObject {
        func measureCompositor(configuration: PerformanceConfiguration) -> FrameMeasurement
    }

    @MainActor
    public final class OffscreenCanvasRendererAdapter: RendererInstrumentationAdapter {
        public init()
        public func measureRenderer(configuration: PerformanceConfiguration) -> FrameMeasurement
    }

    @MainActor
    public final class SignpostWindowServerAdapter: CompositorInstrumentationAdapter {
        public init()
        public func measureCompositor(configuration: PerformanceConfiguration) -> FrameMeasurement
    }

    public struct ProcessMetricsAdapter: Codable, Sendable {
        public let launchCommand: String
        public let memorySource: String
    }

    public struct ManualMetricAdapter: Codable, Sendable {
        public let evidence: ManualMetricEvidence
    }

    public struct ManualMetricEvidence: Codable, Sendable {
        public let metricID: PerformanceMetricID
        public let evidenceClass: MetricEvidenceClass
        public let host: String
        public let recordedAt: String
        public let permissions: [String]
        public let steps: String
        public let samples: [Double]
        public let result: String
        public let evidencePath: String
    }

    @MainActor
    public enum PerformanceCLI {
        public static func run(arguments: [String], outputDirectory: URL) throws
    }

`PerformanceMeasurementReport.validateStructure()` requires
`reportKind == .measurement`, all required keys/types, exactly one immutable
source identity, valid enum values, finite numeric values, coherent arrays,
the 600-second/5-second memory window, running/stopping/stopped/restarted
checkpoints, resilience fields, and matching typed build/run provenance. Its identity
validator accepts exactly one of `sourceCommitSHA` matching `[0-9a-f]{40}` or
`contentManifestSHA256` matching `[0-9a-f]{64}`; both, neither, malformed,
dirty source-commit identities, or symbolic values are rejected. A clean
source tree must use the commit identity; a dirty source tree must use the
content-manifest identity.
`BuildProvenance` must contain the observed source-tree status, source identity
kind/value, source-manifest SHA-256, executable SHA-256, bundle-manifest
SHA-256, UTC timestamp, foundation identity/version, harness version,
build-contract version, and optional accepted-foundation artifact SHA-256. It
contains no filesystem path, so it remains portable. `PerformanceRunProvenance`
may record the resolved build/foundation artifact paths as run evidence and
must link the build artifact to its variant, output root, source ref, and
configuration versions. The report's build/run provenance and configuration
values must agree. Structural measurement validation allows `measured`,
`failed`, and `unmeasured` so diagnostic failures round-trip honestly, but
`validateCompletion()` rejects required failed/unmeasured metrics, budget
breaches, leaks, invalid dispositions, or any non-measured required status.
`PerformanceComparisonHarness.compare()` validates both measurement reports,
then rejects any failed or unmeasured required input before constructing or
writing a comparison. A persisted `PerformanceComparisonReport` therefore
contains measured comparisons only. Its structural validator requires
`reportKind == .comparison`, immutable baseline/candidate identities, matching
schema/harness/foundation/build-contract versions, matching host/fixture,
both typed `BuildProvenance` values, matching run provenance, one
`MetricComparison` for every
`PerformanceMetricID`, equal-length paired arrays, valid `BootstrapInterval`
values, and the conditional manual-evidence rule. A manual metric requires
complete `ManualMetricEvidence` (including host, timestamp, permissions, exact
steps, result, and evidence path); a deterministic metric must have nil manual
evidence. Deterministic comparisons require at least 30 samples. Its
`validateCompletion()` validates only this measured comparison shape and never
turns a rejected input into a persisted failed/unmeasured status. The
`PerformancePairEligibility` argument is constructed only after the CLI/script
verifies both explicit output roots, clean checkout/head-to-commit
correspondence, baseline-to-candidate ancestry, foundation-checkpoint ancestry,
and the accepted foundation provenance artifact. It requires clean 40-hex
commit identities and rejects content-manifest identities for authoritative
comparison. The harness revalidates root/ref, provenance, schema, host,
fixture, harness, foundation, and build-contract equality, so a direct harness
call cannot bypass eligibility; tests pass fabricated/mismatched eligibility
and assert that no comparison is produced or written. The
`PerformanceHarnessTests` and `PerformanceComparisonHarnessTests` fixtures
round-trip and reject both report kinds, provenance mismatches, and rejected
comparison inputs. `ModelMeasurement`
contains status, trial samples, median, p95, MAD, publication count, checksum,
and final-state validity. `FrameMeasurement` contains status, sample count,
p95, frame count, missed-frame count, and instrumentation status.
`MemoryMeasurement` contains status, windowSeconds, sampleIntervalSeconds,
every RSS sample, periodic aggregates, peak RSS, final-window delta
bytes/percent, matched-baseline series/values, peak/end live resource counts,
and phase per sample.

## Task 1: Extend the fixed production model benchmark

**Files:**

- Modify: Sources/PointerAppKit/Diagnostics/GestureBenchmark.swift
- Modify: Tests/PointerAppKitTests/GestureBenchmarkTests.swift
- Modify: scripts/benchmark-gestures.sh

- [ ] **Step 1: Add failing schema assertions.**

    func testReleaseBenchmarkUsesFixedFixtureTrialsWarmupsPublicationsChecksumAndFinalState()
    func testBenchmarkDoesNotClaimRendererOrCompositorTiming()

Assert 12 fixture marks, 240 continuation samples, 5 warmups, 30 trials, two
boundary publications per gesture, stable checksum, valid final state, and
the explicit model-only scope. The JSON remains a serialized
`GestureBenchmark.Result`; it is not a `PerformanceMeasurementReport` and
does not carry renderer, compositor, launch, or memory claims.

- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter GestureBenchmarkTests

Expected: any missing fixed field, checksum, or publication invariant fails.

- [ ] **Step 3: Implement only required benchmark/report changes.**

Keep fixture creation and JSON encoding outside timed scopes; continuation
mutates gesture-local preview and requests redraw without palette rebuild,
shared inspector publication, or undo entries. Keep rendererTimed/compositorTimed
false in the model-only `GestureBenchmark.Result`; E must not present it as
end-to-end timing. Full quality measurement belongs to
`--quality-performance --format json`, not this command.

- [ ] **Step 4: Run GREEN and CLI verification.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter GestureBenchmarkTests
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/benchmark-gestures.sh

Expected: Release JSON has fixed fixture/trial/publication/checksum/final-state fields.

## Task 2: Implement complete versioned PerformanceHarness schema

**Files:**

- Create: Sources/PointerAppKit/Diagnostics/PerformanceMeasurementReport.swift
- Create: Sources/PointerAppKit/Diagnostics/PerformanceComparisonReport.swift
- Create: Sources/PointerAppKit/Diagnostics/PerformanceHarness.swift
- Create: Sources/PointerAppKit/Diagnostics/PerformanceComparisonHarness.swift
- Create: Tests/PointerAppKitTests/PerformanceHarnessTests.swift
- Create: Tests/PointerAppKitTests/PerformanceComparisonHarnessTests.swift
- Create: Tests/PointerAppKitTests/PerformanceFixtures.swift

- [ ] **Step 1: Write failing Codable/status tests.**

    func testPerformanceMeasurementReportRoundTripsEveryRequiredMeasurementObject()
    func testPerformanceReportKindIsTypedAndWrongOrMissingKindsAreRejected()
    func testBuildAndRunProvenanceAreDistinctAndPortable()
    func testPerformanceReportRoundTripsTypedProvenanceAndFoundationVersions()
    func testStructurallyValidFailedAndUnmeasuredReportsRoundTrip()
    func testCompletionValidationRejectsFailedOrUnmeasuredRequiredMetric()
    func testManualMetricComparisonRoundTripsCompleteEvidence()
    func testManualMetricComparisonWithoutEvidenceOrWithDeterministicEvidenceIsRejected()
    func testComparisonRejectsFailedOrUnmeasuredInputBeforeWritingOutput()
    func testMemoryReportRequiresSeriesAggregatesPhasesAndCheckpoints()

Decode a fixture containing every field listed in the Interfaces section; assert
`reportKind == .measurement`, schemaVersion, identity, host, fixture, all ten
measurement objects, disposition, statuses, sample arrays, and
running/stopping/stopped/restarted phase counts. Decode a comparison fixture
with `reportKind == .comparison`; assert Codable preserves the typed enum, and
assert validateStructure() rejects a missing or wrong report kind rather than
accepting a generic dictionary value. Decode structurally valid reports with
measured, failed, and unmeasured statuses and assert they round-trip. Decode a
manual MetricComparison with complete ManualMetricEvidence and assert every
host, recordedAt timestamp, permission, exact-step, result, and evidencePath
field survives round-trip. Decode a manual comparison with nil/empty evidence
and a deterministic comparison with nonnil manual evidence; assert
validateStructure() throws for both. Separately call validateCompletion() and
assert it throws for failed/unmeasured required metrics rather than silently
converting them to zero/default values. Round-trip the typed provenance,
`harnessVersion`, foundation identity/version, and build-contract version, and
assert mismatches are rejected, and assert `BuildProvenance` contains no path
or pair ancestry while `PerformanceRunProvenance` carries only run-level
paths/variant context. Give the comparison harness a structurally
valid measurement with a failed or unmeasured required metric and assert it
throws before constructing a `PerformanceComparisonReport` or writing an
output file; comparison reports contain measured comparisons only.

- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PerformanceHarnessTests|PerformanceComparisonHarnessTests'

Expected: missing PerformanceMeasurementReport, PerformanceComparisonReport, and metric types fail compilation.

- [ ] **Step 3: Implement schema and validators.**

Use explicit Codable structs, not an untyped dictionary. Every required object
has exactly one `MeasurementStatus`. `validateStructure()` checks model
samples/median/p95/MAD/publications/checksum/final state; frame sample/frame/
missed counts; launch cold/warm; allocation bytes/peak; redraw/layout; response
stalls; input samples/latency/missed samples; memory series/aggregates/matched
baseline/resource counts/phases; typed provenance and foundation/build
versions; and the conditional manualEvidence rule. The comparison harness
performs a measured-status preflight on every required input metric and throws
before constructing or writing a comparison if any input is failed/unmeasured.
`PerformanceComparisonReport.validateStructure()` accepts measured
comparisons only. `validateCompletion()` rejects missing paired/resilience
evidence, mismatched baseline series/provenance/configuration, missing
checkpoint data, budget breach, or a disposition other than
`acceptedNoRegression`; it never persists or claims a rejected status.

- [ ] **Step 4: Run GREEN.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PerformanceHarnessTests|PerformanceComparisonHarnessTests'

Expected: complete schema round-trip and rejection tests pass.

## Task 3: Define paired measurement, identity, budget, and resilience protocol

**Files:**

- Modify: Sources/PointerAppKit/Diagnostics/PerformanceHarness.swift
- Modify: Sources/PointerAppKit/Diagnostics/PerformanceComparisonHarness.swift
- Create: Sources/PointerAppKit/Diagnostics/PerformanceCLI.swift
- Modify: Tests/PointerAppKitTests/PerformanceHarnessTests.swift
- Modify: Tests/PointerAppKitTests/PerformanceComparisonHarnessTests.swift
- Create: Tests/PointerAppKitTests/PerformanceCLITests.swift
- Create: scripts/benchmark-quality.sh
- Create: .codex/sdd/reports/quality-campaign/performance/README.md
- Create at runtime: .codex/sdd/reports/quality-campaign/performance/measurements/baseline.json
- Create at runtime: .codex/sdd/reports/quality-campaign/performance/measurements/candidate.json
- Create at runtime: .codex/sdd/reports/quality-campaign/performance/provenance/baseline.json
- Create at runtime: .codex/sdd/reports/quality-campaign/performance/provenance/candidate.json
- Create at runtime: .codex/sdd/reports/quality-campaign/performance/comparisons/paired-comparison.json
- Create at runtime: .codex/sdd/reports/quality-campaign/performance/comparisons/manual/<metricID>.json
- Create at runtime: .codex/sdd/reports/quality-campaign/performance/resilience/resilience.json

- [ ] **Step 1: Write failing paired-protocol tests.**

    func testPerformanceComparisonReportRoundTripsIDsSamplesRatiosBootstrapAndDisposition()
    func testPairedProtocolUsesImmutableIdentitiesFixedSeedWarmupsAndThirtyTrials()
    func testMeasurementCLIRejectsBothOrNeitherSourceIdentity()
    func testDirectComparisonHarnessCannotBypassPairEligibility()
    func testBootstrapIntervalOnlyClaimsImprovementWhenUpperBoundIsBelowZero()
    func testBudgetRegressionAndMissingMetricDispositionIsRevise()
    func testResilienceReportCoversModeToolsMarksClearUndoDisplayChurnAndShortcutTimeout()
    func testRunningStopAndRestartResourceCheckpointsAreIndependent()

Assert `PerformanceComparisonReport` contains `reportKind == .comparison`,
immutable baselineID/candidateID, one `MetricComparison` for every
`PerformanceMetricID`, paired baseline/candidate samples, ratios/deltas,
`BootstrapInterval` seed 48271/10,000 resamples, and per-metric dispositions.
Also assert source/content identities, host/build/fixture fields, five
warmups, `pairsPerOrder == 15`, derived `totalPairs == 30`, exactly 15
baseline-first plus 15 candidate-first pairs, ratio
threshold 1.10, 16.7 ms/100 ms budgets, and separate resource checkpoints.
Resilience cases must name repeated mode toggles, rapid tools, 1,000-mark
sessions, repeated clear/undo, palette show/hide, display churn, and shortcut
candidate timeout with status and resource counts. The measurement command
must accept exactly one of `--source-commit-sha <40hex>` or
`--content-manifest-sha256 <64hex>` and reject both, neither, malformed, dirty,
or symbolic identities.

- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PerformanceHarnessTests

Expected: PerformanceComparisonHarness, paired identity/bootstrap/disposition/checkpoint APIs, and comparison output mapping are absent.

- [ ] **Step 3: Implement fixed-seed pairing and execution contracts.**

Use a clean 40-hex commit SHA or 64-hex SHA-256 content manifest covering the
canonical source scope; reject labels such as `current`, both identity flags,
neither identity flag, and malformed values. A clean tree uses the commit
identity; a dirty tree uses the full content-manifest identity. F's
`build-app.sh` emits one typed `BuildProvenance` per output root containing
observed source status/identity, full source-manifest SHA-256, executable and
bundle-manifest SHA-256 values, UTC timestamp, foundation identity/version,
harness version, and build-contract version. E's `benchmark-quality.sh` is the
sole creator of `PerformanceRunProvenance` and `PerformancePairEligibility`:
it consumes two validated BuildProvenance files plus roots/refs/foundation,
proves Git cleanliness, ancestry, source checkout to built executable
correspondence, and executable hash equality before invoking the app. It
passes `--provenance-file <path>` to `PerformanceCLI`; the app validates the
flag syntax and decodes/cross-checks the BuildProvenance artifact, then embeds
the build/run artifacts in the report, but does not claim Git state or ancestry
on the shell's behalf.

OffscreenCanvasRendererAdapter measures the real CanvasView/CGContext path;
SignpostWindowServerAdapter uses os_signpost/CACurrentMediaTime and records
unmeasured when WindowServer cannot be observed; ProcessMetricsAdapter uses
`/usr/bin/time` and task_info/process metrics for launch/RSS;
ManualMetricAdapter writes ManualMetricEvidence for physical input-to-visible/
compositor cases. None synthesizes input or captures the screen. Define the
separate model, renderer, compositor, combined frame, launch, allocation,
redraw/layout, responsiveness, input-to-visible, and 600-second memory runs,
plus the repeated-toggle, rapid-tool, 1,000-mark, clear/undo, palette,
display-churn, and shortcut-timeout resource checks. If the host cannot
instrument an OS-level metric, record `unmeasured` with its adapter status and
keep `validateCompletion()`/disposition `revise`; never fabricate a measured
value. Keep manual metric evidence in `ManualMetricEvidence` and the final
ledger; deterministic tests cannot substitute for a missing measured physical
metric. This step defines the protocol but does not pin or execute a paired
baseline/candidate run; that is E-execution after F tasks 1–3.

- [ ] **Step 4: Implement report disposition and foundation handoff.**

Ratios at most 1.10 with no breach, leak, or missing metric may be
`acceptedNoRegression`; any ratio above 1.10, breach, leak, invalid structure,
failed metric, or unmeasured required metric makes completion disposition
`revise` and blocks completion. Structural report generation still preserves
failed/unmeasured statuses for diagnosis. Return a measured bottleneck to the
named A-foundation/A-harness, B-core/B-render-integration, C-product-surface,
or D-visual-language owner with metric, reproduction, identity, comparison,
and narrow requested fix; E does not edit their source. Record the E-foundation
checkpoint for F and explicitly hand off the exact schema/harness version,
fixture, and argument contract. Do not pin a baseline or claim completion at
this gate.

- [ ] **Step 5: Run GREEN for the E-foundation gate.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PerformanceHarnessTests|PerformanceComparisonHarnessTests'

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PerformanceCLITests

`PerformanceCLI.run(arguments:outputDirectory:)` defines, but does not execute
at this gate, these exact commands:

```text
Pointer --quality-performance --format json --variant baseline|candidate \
  (--source-commit-sha <40hex> | --content-manifest-sha256 <64hex>) \
  --provenance-file <path> --output-dir <directory>
Pointer --quality-compare --format json \
  --baseline-root <build/baseline> --baseline-commit-sha <40hex> \
  --candidate-root <build/candidate> --candidate-commit-sha <40hex> \
  --foundation-provenance <path> \
  --manual-evidence-dir <comparisons/manual> \
  --output-dir <comparisons>
```

The first command emits one `PerformanceMeasurementReport`; the second emits
one authoritative `PerformanceComparisonReport` only for clean 40-hex commit
identities whose roots and refs pass the lineage/foundation checks. The typed
`reportKind` field makes the distinction structural. A measurement command may
still accept a content-manifest identity for diagnostic runs, but the
authoritative compare rejects that identity and does not write a promoted
comparison. Scripts orchestrate these commands, while F wires the launcher
branches after its Release foundation is accepted. No report is written at
the performance root.

## Task 4: Execute the paired immutable protocol after F-foundation

This task starts only after F tasks 1–3 pass their worker, reviewer, and
adversarial gates and produce the accepted foundation artifact. The
authoritative comparison lineage uses clean 40-hex baseline and candidate
commits only; content-manifest measurements remain diagnostic-only and cannot
be promoted or compared authoritatively without a separately accepted lineage
artifact. At execution time, resolve both commits, verify clean checkout/head
correspondence and ancestry, and build each commit with F's explicit output
root contract. Pin the baseline only after the foundation checkpoint; a stale
report, dirty checkout, symbolic label, or prior D checkpoint is not eligible.

- [ ] **Step 1:** Observe and record the accepted foundation artifact,
  baseline/candidate refs, host, fixture, E schema/harness version, and F
  foundation identity. Require each source worktree to be clean and
  `HEAD == <40hex ref>`, then require
  `git merge-base --is-ancestor <baseline-ref> <candidate-ref>`. Require the
  foundation checkpoint commit to be an ancestor of both refs. The candidate
  must be a subsequent measured commit with the same host/fixture and a
  different clean 40-hex commit identity; a content-manifest identity is
  diagnostic-only and is rejected by the authoritative compare.
- [ ] **Step 2:** Run both variants, then the comparison and resilience output:

      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/benchmark-quality.sh \
        --baseline-commit-sha <40hex-baseline> --candidate-commit-sha <40hex-candidate> \
        --baseline-root build/baseline --candidate-root build/candidate \
        --foundation-provenance .codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json \
        --manual-evidence-dir .codex/sdd/reports/quality-campaign/performance/comparisons/manual \
        --output-dir .codex/sdd/reports/quality-campaign/performance

  `benchmark-quality.sh` creates scoped source worktrees at the two refs,
  verifies clean status, exact `HEAD` values, ancestry, and foundation
  checkpoint ancestry, validates the explicit accepted foundation provenance,
  then invokes F's
  `scripts/build-app.sh --output-root build/baseline --foundation-provenance
  .codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json` and
  `scripts/build-app.sh --output-root build/candidate
  --foundation-provenance
  .codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json`.
  Each output root must
  contain exactly `Pointer.app`, `source-manifest.sha256`,
  `bundle-manifest.sha256`, and build-only `provenance.json`; the script
  hashes each executable and cross-checks it against that BuildProvenance
  before passing the per-variant `--provenance-file` to
  `--quality-performance`. It alone creates the per-variant
  `PerformanceRunProvenance` and `PerformancePairEligibility`, then invokes
  the full measurement branch for baseline then candidate, writes
  `measurements/baseline.json` and `measurements/candidate.json`, and invokes
  the authoritative compare with `--baseline-root`, `--candidate-root`, the
  two commit SHAs, and `--foundation-provenance`. The compare rejects
  content-manifest identities, mismatched refs/provenance/foundation, and any
  failed or unmeasured input before writing
  `comparisons/paired-comparison.json`; resilience remains at
  `resilience/resilience.json`. It exits nonzero on missing IDs, nonzero CLI
  status, provenance/hash mismatch, invalid structure, non-ancestor refs, or
  completion `revise`.
- [ ] **Step 3:** Hand raw samples, identities, disposition, and any measured
  finding to the configured Luna reviewer; after approval, adversarial Codex
  challenges model-only claims, source identity eligibility, missing metrics,
  >10% regressions, budget math, bootstrap direction, memory phases, resource
  checkpoints, and speculative fixes. Return findings to E or the named owner
  and rerun the paired execution until reconciled.

## Task 5: E-execution reconciliation gate

- [ ] **Step 1:** Run `git status --short`, `git diff --check`, and verify only
  E-owned paths changed; the clean-clone condition is observed by F at its own
  execution time and cannot be inherited from this report.
- [ ] **Step 2:** Run the fixed `GestureBenchmark`, schema tests, paired
  comparison tests, quality script, and the full Swift suite relevant to E.
- [ ] **Step 3:** Preserve failed/unmeasured statuses for diagnosis, but never
  relabel them as pass. Keep the E-execution report and identity artifacts
  immutable once reconciled; hand only measured findings to the named owner.

## Plan self-check

The fixed model-only `GestureBenchmark.Result`, typed measurement/comparison
report kinds and validators, typed harness/foundation/build-contract versions,
script-side provenance artifact and executable/bundle hash correspondence,
canonical full source-manifest scope, separate
PerformanceComparisonHarness/per-metric collection with measured-only
preflight, mutually exclusive immutable source identities, baseline eligibility
and E/F sequencing, executable PerformanceCLI/benchmark-quality ordering and
measurements/comparisons/resilience output paths, allowed instrumentation
adapters, production-path metrics, memory/resource phases, budgets, resilience
runs, evidence reports, and required review loop are covered. No commit
instruction or cross-workstream source edit is included.
