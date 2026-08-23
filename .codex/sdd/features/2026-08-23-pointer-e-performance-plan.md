# Pointer E — Performance and Resilience Measurement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking. The coordinating agent owns commits and publication; worker tasks end with evidence/status handoff instead of commit steps.

**Goal:** Measure the production model, renderer, compositor, launch, allocation, redraw, responsiveness, input-to-visible, memory, and resilience paths with immutable paired evidence, then return only measured regressions or fixes to the owning workstream.

**Architecture:** Preserve GestureBenchmark's real PointerSession API and fixed 12-mark/240-sample/5-warmup/30-trial model run. PerformanceHarness produces one variant measurement report; the separate PerformanceComparisonHarness consumes immutable baseline/candidate measurement reports and produces the paired comparison report. E owns diagnostics, benchmark scripts, fixtures, and reports; measured findings return to the named prior-phase owner: A-foundation/A-harness, B-core/B-render-integration, C-product-surface, or D-visual-language.

**Tech Stack:** Swift tools 5.10, macOS 14+, AppKit, PointerCore, PointerAppKit, XCTest, ContinuousClock, Codable, os_signpost/instrumentation available on host, fixed-seed bootstrap statistics.

**Spec:** .codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md (Workstream E — performance and resilience measurement).

## Global Constraints

- Do not claim a performance improvement without before/after measurements from the same production path and fixture.
- Structurally valid reports may contain measured, failed, or unmeasured statuses; completion validation separately rejects failed or unmeasured required metrics, and not_applicable is never a permitted status.
- Every comparison uses immutable commit SHA or SHA-256 content manifest identities, same host/fixture, five warmups, 30 paired trials, 15 baseline-to-candidate and 15 candidate-to-baseline pairs, and a fixed-seed 10,000-resample bootstrap interval.
- A candidate/baseline median or p95 ratio greater than 1.10, frame/input budget breach, leak, invalid schema, or required unmeasured metric is REVISE and blocks completion.
- At 60 Hz equivalent, p95 render plus compositor work is at most 16.7 ms for 12-mark and dense 1,000-mark fixtures; no repeatable active-gesture main-thread stall exceeds 100 ms; p95 input-to-visible is at most 100 ms.
- Memory is a 600-second, 5-second sample-interval time series with running, stopping, stopped, and restarted phases; running plateau and stop/restart checkpoints are separate.
- Performance fixes address a measured bottleneck in an owning workstream; no speculative cache, concurrency, dependency, or abstraction is accepted.
- Full end-to-end interaction measurement depends on accepted A-foundation smoke/fixtures, B-core lifecycle contracts, B-render-integration CanvasView render path, C-product-surface active-shortcut/metadata contracts, D-visual-language renderer/guide assets, and the later A-harness CanvasIntegrationHarnessTests phase. Model-only measurement may run after A-foundation and B-core.
- Allowed instrumentation adapters are real offscreen CanvasView/CGContext renderer timing, os_signpost/CACurrentMediaTime WindowServer/compositor timing where available, /usr/bin/time/task_info/process metrics for launch/memory, and a manual physical metric adapter. No adapter may synthesize input, install global monitors/event taps, capture the screen, or replace the production route. Deterministic and manual evidence remain separate; missing required measured evidence blocks completion.
- Work only in /Users/bruno/Dev/pointer/.worktrees/stable-app; E owns Diagnostics/GestureBenchmark.swift, PerformanceHarness.swift, PerformanceComparisonHarness.swift, their tests, benchmark scripts/fixtures, and .codex/sdd/reports/quality-campaign/performance/measurements/**, comparisons/**, and resilience/** only.

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
        public let pairCount: Int
        public let bootstrapSeed: UInt64
        public let bootstrapResamples: Int
        public let memoryWindowSeconds: Int
        public let memorySampleIntervalSeconds: Int

        public static let standard = PerformanceConfiguration(
            fixtureMarkCount: 12,
            samplesPerGesture: 240,
            warmupCount: 5,
            trialCount: 30,
            pairCount: 15,
            bootstrapSeed: 48271,
            bootstrapResamples: 10_000,
            memoryWindowSeconds: 600,
            memorySampleIntervalSeconds: 5
        )
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
        public let schemaVersion: Int
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
            configuration: PerformanceConfiguration
        ) throws -> PerformanceComparisonReport
        public static func writeComparison(
            baselineURL: URL,
            candidateURL: URL,
            manualEvidenceDirectory: URL,
            outputDirectory: URL,
            configuration: PerformanceConfiguration
        ) throws -> PerformanceComparisonReport
    }

    public struct PerformanceComparisonReport: Codable, Sendable {
        public let schemaVersion: Int
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

PerformanceMeasurementReport.validateStructure() throws unless required keys/types are present, exactly one of sourceCommitSHA/contentManifestSHA256 is present, enum values are valid, numeric values are finite, arrays have coherent lengths, and the memory window is 600 seconds with 5-second samples, running/stopping/stopped/restarted checkpoints, and resilience fields. It allows measured, failed, and unmeasured statuses so diagnostic failures round-trip honestly. PerformanceMeasurementReport.validateCompletion() first calls validateStructure(), then rejects any required failed/unmeasured metric, budget breach, leak, invalid disposition, or non-measured required status. PerformanceComparisonReport.validateStructure() requires immutable baselineID/candidateID, one MetricComparison for every PerformanceMetricID, equal-length paired arrays, valid BootstrapInterval values, and the conditional manualEvidence rule. If evidenceClass is manual, manualEvidence is required and its host, recordedAt timestamp, permissions, exact steps, result, and evidencePath must all be nonempty; if evidenceClass is deterministic, manualEvidence must be nil. Deterministic comparisons require at least 30 samples, while manual comparisons carry explicit ManualMetricEvidence. PerformanceComparisonReport.validateCompletion() first calls validateStructure(), then rejects any required failed/unmeasured metric, missing resilience evidence, budget breach, leak, or disposition other than acceptedNoRegression. ModelMeasurement contains status, trial samples, median, p95, MAD, publication count, checksum, and final-state validity. FrameMeasurement contains status, sample count, p95, frame count, missed-frame count, and instrumentation status. MemoryMeasurement contains status, windowSeconds, sampleIntervalSeconds, every RSS sample, periodic aggregates, peak RSS, final-window delta bytes/percent, matched-baseline series/values, peak/end live resource counts, and phase per sample.

## Task 1: Extend the fixed production model benchmark

**Files:**

- Modify: Sources/PointerAppKit/Diagnostics/GestureBenchmark.swift
- Modify: Tests/PointerAppKitTests/GestureBenchmarkTests.swift
- Modify: scripts/benchmark-gestures.sh

- [ ] **Step 1: Add failing schema assertions.**

    func testReleaseBenchmarkUsesFixedFixtureTrialsWarmupsPublicationsChecksumAndFinalState()
    func testBenchmarkDoesNotClaimRendererOrCompositorTiming()

Assert 12 fixture marks, 240 continuation samples, 5 warmups, 30 trials, two boundary publications per gesture, stable checksum, valid final state, and explicit model-only scope.

- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter GestureBenchmarkTests

Expected: any missing fixed field, checksum, or publication invariant fails.

- [ ] **Step 3: Implement only required benchmark/report changes.**

Keep fixture creation and JSON encoding outside timed scopes; continuation mutates gesture-local preview and requests redraw without palette rebuild, shared inspector publication, or undo entries. Keep rendererTimed/compositorTimed false in this model-only report; E must not present it as end-to-end timing.

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
    func testStructurallyValidFailedAndUnmeasuredReportsRoundTrip()
    func testCompletionValidationRejectsFailedOrUnmeasuredRequiredMetric()
    func testManualMetricComparisonRoundTripsCompleteEvidence()
    func testManualMetricComparisonWithoutEvidenceOrWithDeterministicEvidenceIsRejected()
    func testMemoryReportRequiresSeriesAggregatesPhasesAndCheckpoints()

Decode a fixture containing every field listed in the Interfaces section; assert schemaVersion, identity, host, fixture, all ten measurement objects, disposition, statuses, sample arrays, and running/stopping/stopped/restarted phase counts. Decode structurally valid reports with measured, failed, and unmeasured statuses and assert they round-trip. Decode a manual MetricComparison with complete ManualMetricEvidence and assert every host, recordedAt timestamp, permission, exact-step, result, and evidencePath field survives round-trip. Decode a manual comparison with nil/empty evidence and a deterministic comparison with nonnil manual evidence; assert validateStructure() throws for both. Separately call validateCompletion() and assert it throws for failed/unmeasured required metrics rather than silently converting them to zero/default values.

- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PerformanceHarnessTests|PerformanceComparisonHarnessTests'

Expected: missing PerformanceMeasurementReport, PerformanceComparisonReport, and metric types fail compilation.

- [ ] **Step 3: Implement schema and validators.**

Use explicit Codable structs, not an untyped dictionary. Every required object has exactly one MeasurementStatus. validateStructure() checks model samples/median/p95/MAD/publications/checksum/final state; frame sample/frame/missed counts; launch cold/warm; allocation bytes/peak; redraw/layout; response stalls; input samples/latency/missed samples; memory series/aggregates/matched baseline/resource counts/phases; and the conditional manualEvidence rule. validateCompletion() rejects required failed/unmeasured statuses, missing paired/resilience evidence, mismatched baseline series, missing checkpoint data, budget breach, or a disposition other than acceptedNoRegression.

- [ ] **Step 4: Run GREEN.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PerformanceHarnessTests|PerformanceComparisonHarnessTests'

Expected: complete schema round-trip and rejection tests pass.

## Task 3: Add paired measurement, identity, budget, and resilience protocol

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
- Create at runtime: .codex/sdd/reports/quality-campaign/performance/comparisons/paired-comparison.json
- Create at runtime: .codex/sdd/reports/quality-campaign/performance/comparisons/manual/<metricID>.json
- Create at runtime: .codex/sdd/reports/quality-campaign/performance/resilience/resilience.json

- [ ] **Step 1: Write failing paired-protocol tests.**

    func testPerformanceComparisonReportRoundTripsIDsSamplesRatiosBootstrapAndDisposition()
    func testPairedProtocolUsesImmutableIdentitiesFixedSeedWarmupsAndThirtyTrials()
    func testBootstrapIntervalOnlyClaimsImprovementWhenUpperBoundIsBelowZero()
    func testBudgetRegressionAndMissingMetricDispositionIsRevise()
    func testResilienceReportCoversModeToolsMarksClearUndoDisplayChurnAndShortcutTimeout()
    func testRunningStopAndRestartResourceCheckpointsAreIndependent()

Assert PerformanceComparisonReport contains immutable baselineID/candidateID, one MetricComparison for every PerformanceMetricID, paired baseline/candidate samples, ratios/deltas, BootstrapInterval seed 48271/10,000 resamples, and per-metric dispositions. Also assert source/content identities, host/build/fixture fields, 5 warmups, 15 baseline-to-candidate plus 15 candidate-to-baseline pairs, ratio threshold 1.10, 16.7 ms/100 ms budgets, and separate resource checkpoints. Resilience cases must name repeated mode toggles, rapid tools, 1,000-mark sessions, repeated clear/undo, palette show/hide, display churn, and shortcut candidate timeout with status and resource counts.

- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PerformanceHarnessTests

Expected: PerformanceComparisonHarness, paired identity/bootstrap/disposition/checkpoint APIs, and comparison output mapping are absent.

- [ ] **Step 3: Implement fixed-seed pairing and actual production runs.**

Use a clean commit SHA or SHA-256 manifest covering source, tests, assets, scripts, and resources; reject labels current or dirty. OffscreenCanvasRendererAdapter measures the real CanvasView/CGContext path; SignpostWindowServerAdapter uses os_signpost/CACurrentMediaTime and records unmeasured when WindowServer cannot be observed; ProcessMetricsAdapter uses /usr/bin/time and task_info/process metrics for launch/RSS; ManualMetricAdapter writes ManualMetricEvidence for physical input-to-visible/compositor cases. None synthesizes input or captures the screen. Run model, renderer, compositor, combined frame, launch, allocation, redraw/layout, responsiveness, input-to-visible, and 600-second memory separately. If the host cannot instrument an OS-level metric, record unmeasured with its adapter status and keep validateCompletion()/disposition REVISE; never fabricate a measured value. Add repeated toggles, rapid tools, 1,000 marks, clear/undo, palette show/hide, display churn, and shortcut timeout resource checks. Keep manual metric evidence in ManualMetricEvidence and the final ledger; deterministic tests cannot substitute for a missing measured physical metric.

- [ ] **Step 4: Implement report disposition.**

Ratios at most 1.10 with no breach, leak, or missing metric may be acceptedNoRegression; any ratio above 1.10, breach, leak, invalid structure, failed metric, or unmeasured required metric makes completion disposition revise and blocks completion. Structural report generation still preserves failed/unmeasured statuses for diagnosis. Return a measured bottleneck to the named A-foundation/A-harness, B-core/B-render-integration, C-product-surface, or D-visual-language owner with metric, reproduction, identity, comparison, and narrow requested fix; E does not edit their source.

- [ ] **Step 5: Run GREEN and produce machine-readable report.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PerformanceHarnessTests|PerformanceComparisonHarnessTests'
    baseline_id="$(shasum -a 256 build/baseline/Pointer.resource-manifest.sha256 | awk '{print $1}')"
    candidate_id="$(shasum -a 256 build/candidate/Pointer.resource-manifest.sha256 | awk '{print $1}')"
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/benchmark-quality.sh --baseline-executable build/baseline/Pointer.app/Contents/MacOS/Pointer --baseline-id "$baseline_id" --candidate-executable build/candidate/Pointer.app/Contents/MacOS/Pointer --candidate-id "$candidate_id" --output-dir .codex/sdd/reports/quality-campaign/performance

PerformanceCLI.run(arguments:outputDirectory:) accepts --quality-performance --format json --variant baseline|candidate --source-id <immutable-id> and --quality-compare --format json --baseline <measurements/baseline.json> --candidate <measurements/candidate.json> --manual-evidence-dir <comparisons/manual> --output-dir <comparisons>. F wires these branches in the launcher after Release build. benchmark-quality.sh validates both executable paths and immutable IDs, invokes baseline then candidate in that order, writes measurements/baseline.json and measurements/candidate.json, maps each PerformanceMetricID to its paired samples, and for manual metrics loads comparisons/manual/<metricID>.json into MetricComparison.manualEvidence. It invokes PerformanceComparisonHarness.writeComparison(...), which validates both measurement reports, rejects a missing/manual-ID-mismatch/incomplete evidence file and nonnil manualEvidence on deterministic metrics, writes comparisons/paired-comparison.json, invokes PerformanceHarness.measureResilience for the fixed resilience run, writes resilience/resilience.json, and exits nonzero on missing IDs, nonzero CLI status, invalid structure, or completion REVISE. No report is written at the performance root.

## Task 4: Reconciliation gate

- [ ] **Step 1:** Run git status --short, git diff --check, and verify only E-owned paths changed.
- [ ] **Step 2:** Run the fixed GestureBenchmark, PerformanceHarnessTests, PerformanceComparisonHarnessTests, quality script, and full DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test.
- [ ] **Step 3:** Hand the report, raw samples, identities, disposition, and any measured finding to the configured Luna reviewer; reviewer returns REVISE or APPROVED with evidence.
- [ ] **Step 4:** After reviewer approval, adversarial Codex challenges model-only claims, missing metrics, >10% regressions, budget math, bootstrap direction, memory phases, resource checkpoints, and speculative fixes.
- [ ] **Step 5:** Return findings to E or the named owning worker; rerun paired measurements and reviewer/Codex checks until status is RECONCILED. Do not relabel unmeasured as pass and do not widen E's write scope.

## Plan self-check

The fixed benchmark, structurally permissive variant report decoding, separate PerformanceComparisonHarness/per-metric MetricComparison collection, completion validation/disposition, paired identities/bootstrap, executable PerformanceCLI/benchmark-quality ordering and measurements/comparisons/resilience output paths, allowed instrumentation adapters, production-path metrics, memory/resource phases, budgets, resilience runs, evidence reports, and required review loop are covered. No commit instruction or cross-workstream source edit is included.
