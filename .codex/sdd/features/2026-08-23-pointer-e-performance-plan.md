# Pointer E — Performance and Resilience Measurement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking. The coordinating agent owns commits and publication; worker tasks end with evidence/status handoff instead of commit steps.

**Goal:** Measure the production model, renderer, compositor, launch, allocation, redraw, responsiveness, input-to-visible, memory, and resilience paths with immutable paired evidence, then return only measured regressions or fixes to the owning workstream.

**Architecture:** Preserve GestureBenchmark's real PointerSession API and its
fixed standard12 12-mark/240-sample/5-warmup/30-trial model run. The typed
fixture-profile harness parameterizes the same production model and renderer
oracle for the separate dense1000 1,000-mark profile. The
`--benchmark-gestures --format json` command remains the model-only
`GestureBenchmark.Result` output. `PerformanceHarness` produces one typed
fixture-profile report per variant and profile; the separate
`PerformanceComparisonHarness` consumes immutable baseline/candidate
measurement reports and produces the paired `PerformanceComparisonReport`.
E-foundation owns diagnostics, benchmark contracts, fixtures, and report
contracts; E-execution owns only runtime performance evidence. Measured
findings return to the named prior-phase owner:
A-foundation/A-harness, B-core/B-render-integration, C-product-surface, or
D-visual-language.

**Tech Stack:** Swift tools 5.10, macOS 14+, AppKit, PointerCore, PointerAppKit, XCTest, ContinuousClock, Codable, os_signpost/instrumentation available on host, fixed-seed bootstrap statistics.

**Spec:** .codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md (Workstream E — performance and resilience measurement).

## Global Constraints

- Do not claim a performance improvement without before/after measurements from the same production path and fixture.
- Structurally valid measurement reports may contain `measured`, `failed`, or
  `unmeasured` statuses; completion validation rejects failed or unmeasured
  required metrics, and `not_applicable` is never permitted. Any missing,
  failed, or unmeasured required metric leaves that measurement report's
  disposition `revise`, never `blocked` or `acceptedNoRegression`. Comparison preflight then rejects it
  before constructing or writing any comparison.
  Comparison
  inputs are stricter: `PerformanceComparisonHarness` rejects any failed or
  unmeasured required metric before it constructs or writes a comparison, so a
  persisted comparison contains measured comparisons only.
- Every per-profile comparison uses immutable commit SHA or SHA-256 content
  manifest identities, the same `PerformanceConfiguration.fixtureProfile`,
  host, and fixture,
  five warmups, `pairsPerOrder == 15`, and `totalPairs == pairsPerOrder * 2 ==
  30`: exactly 15 baseline-first and 15 candidate-first pairs. It uses a
  fixed-seed 10,000-resample bootstrap interval.
- Task 3c/E-execution runs both typed fixture profiles, `standard12` and
  `dense1000`, as separate configuration/provenance/
  `PerformanceMeasurementReport` artifacts. Each profile has its own
  `FixtureIdentity` profile/version/count, measurement reports, pair-execution
  artifact, comparison, and output root. Only Task 3c's typed campaign
  completion manifest requires one accepted comparison for each profile and
  rejects missing, duplicate, or concatenated populations; an individual
  foundation/report run remains bound to one profile.
- `benchmark-quality.sh` interleaves each baseline→candidate or candidate→baseline pair per trial, records partial indexed artifacts, and never runs a whole baseline batch before a whole candidate batch.
- A candidate/baseline median or p95 ratio greater than 1.10, frame/input budget breach, leak, invalid schema, or missing/failed/unmeasured required metric structurally requires disposition `revise` (never `blocked` or `acceptedNoRegression`) and blocks completion.
- At 60 Hz equivalent, p95 render plus compositor work is at most 16.7 ms for
  both the `standard12` 12-mark and `dense1000` 1,000-mark profiles; no
  repeatable active-gesture main-thread stall exceeds 100 ms; p95
  input-to-visible is at most 100 ms. The 16.7 ms gate is evaluated per
  profile, never over concatenated samples.
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
- E-foundation Task 3b defines the compositor, process, manual, and
  combined-frame protocols and their honest `.unmeasured`/`revise` fallbacks.
  The current renderer adapter measures the real offscreen CanvasView/CGContext
  path; the current WindowServer compositor, process, combined-frame, and
  manual adapters do not yet produce authoritative measurements. A
  `CACurrentMediaTime` duration is not WindowServer compositor measurement,
  and `combinedFrame` is not a renderer-plus-compositor sum. Task 3c's
  `benchmark-quality.sh` and E-execution supply external trace/process/manual
  evidence and sidecars through those typed protocols. `ManualMetricAdapter`
  is currently a Codable evidence schema only until that Task 3c writer exists.
  No adapter may synthesize input, install global monitors/event taps, capture
  the screen, or replace the production route. Deterministic and manual
  evidence remain separate; missing required measured evidence blocks
  completion.
- Work only in /Users/bruno/Dev/pointer/.worktrees/stable-app; E-foundation
  owns Diagnostics/GestureBenchmark.swift, PerformanceHarness.swift,
  PerformanceComparisonHarness.swift, PerformanceCLI.swift, their tests,
  `scripts/benchmark-quality.sh`, benchmark fixtures, and report schemas and
  validators. E-execution owns only the runtime evidence under
  `.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/{measurements,provenance,comparisons,resilience}/**`
  for both profiles; it consumes the
  already-implemented CLI/script and has no code or script ownership.
  E task 3c defines and implements the immutable protocol and CLI/script
  contracts before F-foundation; E-execution runs those commands only after
  the F-foundation checkpoint described below.

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

1. **E-foundation (tasks 1–3, including Task 3c):** implement and structurally
   test `GestureBenchmark.Result`, typed measurement/comparison schemas,
   validators, adapters, `PerformanceCLI`, and `scripts/benchmark-quality.sh`
   plus their argument contracts. These tasks may not pin a baseline, run a
   paired comparison, or claim performance completion.
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
use the same E schema version, exact `PerformanceConfiguration.fixtureProfile`
and `fixtureVersion`, typed `harnessVersion`, `foundationIdentity`/version,
`buildContractVersion`, and fixture configuration; both use the F
launcher/build foundation; the baseline
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
        public let buildConfiguration: String
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
        public let host: HostIdentity
        public let recordedAtUTC: String
        public let configuration: PerformanceConfiguration
        public let acceptedFoundationArtifactSHA256: String?
        public let foundationProvenancePath: String
        public let foundation: FoundationIdentity
        public let harnessVersion: String
        public let buildContractVersion: String
    }

    public struct HostIdentity: Codable, Sendable, Equatable {
        public let machineIdentifier: String
        public let processArchitecture: String
        public let connectedDisplayUUIDs: [String]
    }

    public struct FixtureIdentity: Codable, Sendable, Equatable {
        public let identifier: String
        public let fixtureProfile: PerformanceFixtureProfile
        public let fixtureVersion: String
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
        public let frameMilliseconds: [Double]
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
        public let sampleMilliseconds: [Double]
        public let p95Milliseconds: Double
    }

    public struct ResponsivenessMeasurement: Codable, Sendable {
        public let status: MeasurementStatus
        public let stallCount: Int
        public let responseMilliseconds: [Double]
        public let maximumMainThreadStallMilliseconds: Double
        public let p95ResponseMilliseconds: Double
    }

    public struct InputToVisibleMeasurement: Codable, Sendable {
        public let status: MeasurementStatus
        public let sampleCount: Int
        public let sampleMilliseconds: [Double]
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
        public let postWarmupSlopeBytesPerSecond: Double
        public let peakLiveResourceCounts: ResourceCounts
        public let endLiveResourceCounts: ResourceCounts
    }

    public struct PerformanceConfiguration: Codable, Sendable {
        public let fixtureMarkCount: Int
        public let fixtureProfile: PerformanceFixtureProfile
        public let fixtureVersion: String
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

        public static let standard12 = PerformanceConfiguration(
            fixtureMarkCount: 12,
            fixtureProfile: .standard12,
            fixtureVersion: "pointer-fixture-standard12/v1",
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

        public static let standard = standard12

        public static let dense1000 = PerformanceConfiguration(
            fixtureMarkCount: 1_000,
            fixtureProfile: .dense1000,
            fixtureVersion: "pointer-fixture-dense1000/v1",
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

        public static let dense = dense1000

        public var totalPairs: Int { pairsPerOrder * 2 }
    }

    public enum PerformanceFixtureProfile: String, Codable, Sendable, Equatable, CaseIterable {
        case standard12
        case dense1000

        public var markCount: Int {
            switch self {
            case .standard12: return 12
            case .dense1000: return 1_000
            }
        }

        public var identifier: String {
            switch self {
            case .standard12: return "pointer-standard-12-marks"
            case .dense1000: return "pointer-dense-1000-marks"
            }
        }

        public var version: String {
            switch self {
            case .standard12: return "pointer-fixture-standard12/v1"
            case .dense1000: return "pointer-fixture-dense1000/v1"
            }
        }
    }

    public struct PerformanceCampaignCompletionManifest: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let standard12ComparisonPath: String
        public let dense1000ComparisonPath: String
    }

The only accepted fixture profiles are `PerformanceFixtureProfile.standard12`
(`pointer-fixture-standard12/v1`, identifier `pointer-standard-12-marks`,
12 marks) and `.dense1000` (`pointer-fixture-dense1000/v1`, identifier
`pointer-dense-1000-marks`, 1,000 marks). Each profile binds
`PerformanceConfiguration.fixtureProfile`/`fixtureVersion` and
`FixtureIdentity.fixtureProfile`/`fixtureVersion`/`markCount`; measurement and
run provenance carry that configuration, while comparison persists each
baseline/candidate configuration and fixture through their typed provenance and
fixture fields. Profile populations, samples, pair artifacts, and comparisons
remain separate and are never concatenated.

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

    public enum PerformanceMetricUnit: String, Codable, Sendable, Equatable {
        case milliseconds
        case nanoseconds
        case bytes
    }

    public enum PairOrder: String, Codable, Sendable, Equatable {
        case baselineFirst
        case candidateFirst
    }

    public struct PerformancePairExecutionRecord: Codable, Sendable, Equatable {
        public let pairIndex: Int
        public let order: PairOrder
        public let baselineSampleIndex: Int
        public let candidateSampleIndex: Int
        public let baselineStartedAtUTC: String
        public let candidateStartedAtUTC: String
        public let baselineEndedAtUTC: String
        public let candidateEndedAtUTC: String
    }

    public struct PerformancePairExecutionArtifact: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let baselineID: String
        public let candidateID: String
        public let baselineMeasurementReportSHA256: String
        public let candidateMeasurementReportSHA256: String
        public let records: [PerformancePairExecutionRecord]
    }

`PerformancePairExecutionArtifact` is a version-1 persisted code-worker
artifact with exactly 30 unique contiguous `pairIndex` records: the first 15
are `.baselineFirst` and the next 15 `.candidateFirst`. It carries
baseline/candidate IDs and lowercase 64-hex measurement-report hashes; every
record binds baseline/candidate sample indices and UTC start/end timestamps.
Within each pair, each variant's start ≤ its own end, the first variant's end <
the second variant's start, and each pair's second end < the next pair's first
start. Its artifact SHA is
the separate `pairExecutionArtifactSHA256` argument/field, not a JSON field in
the artifact. The producer uses the canonical sorted-key encoder; the SHA is
SHA-256 of those canonical artifact bytes and is recomputable from the embedded
artifact. Unknown fields, alternate whitespace, or alternate key order are
rejected before decoding/acceptance. Internal `compare` receives the decoded
artifact plus that SHA;
the public `writeComparison` reads the artifact URL, validates the SHA and
records, and pairs samples by recorded indices rather than arrival order.

    public struct MetricComparison: Codable, Sendable {
        public let metricID: PerformanceMetricID
        public let evidenceClass: MetricEvidenceClass
        public let baselineID: String
        public let candidateID: String
        public let baselineSamples: [Double]
        public let candidateSamples: [Double]
        public let ratios: [Double]
        public let deltas: [Double]
        public let unit: PerformanceMetricUnit
        public let budgetLimit: Double?
        public let bootstrapInterval: BootstrapInterval
        public let improvementClaimed: Bool
        public let manualEvidence: ManualMetricEvidencePair?
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
        public static func run(
            configuration: PerformanceConfiguration,
            buildProvenance: BuildProvenance,
            runProvenance: PerformanceRunProvenance
        ) throws -> PerformanceMeasurementReport
    }

    @MainActor
    public enum PerformanceComparisonHarness {
        static func compare(
            baseline: PerformanceMeasurementReport,
            candidate: PerformanceMeasurementReport,
            configuration: PerformanceConfiguration,
            eligibility: PerformancePairEligibility,
            pairExecutionArtifact: PerformancePairExecutionArtifact,
            manualEvidenceDirectory: URL,
            pairExecutionArtifactSHA256: String,
            baselineMeasurementReportSHA256: String? = nil,
            candidateMeasurementReportSHA256: String? = nil
        ) throws -> PerformanceComparisonDraft
        public static func writeComparison(
            draft: PerformanceComparisonDraft,
            baselineURL: URL,
            candidateURL: URL,
            pairExecutionURL: URL,
            manualEvidenceDirectory: URL,
            outputDirectory: URL,
            configuration: PerformanceConfiguration,
            eligibility: PerformancePairEligibility
        ) throws -> PerformanceComparisonReport
    }

    public struct PerformanceComparisonDraft: Sendable, Equatable {
        // Public opaque, non-persisted carrier produced only by internal
        // compare. It has no public initializer or public stored properties.
        // Its internal representation carries the remaining comparison
        // content, excluding reportKind, schemaVersion,
        // baselineMeasurementReportSHA256, and candidateMeasurementReportSHA256;
        // the public writer owns and injects those four persisted fields.
        let harnessVersion: String
        let foundationIdentity: FoundationIdentity
        let buildContractVersion: String
        let baselineBuildProvenance: BuildProvenance
        let candidateBuildProvenance: BuildProvenance
        let baselineRunProvenance: PerformanceRunProvenance
        let candidateRunProvenance: PerformanceRunProvenance
        let baselineMeasurementIdentity: MeasurementIdentity
        let candidateMeasurementIdentity: MeasurementIdentity
        let baselineFixture: FixtureIdentity
        let candidateFixture: FixtureIdentity
        let pairExecutionArtifact: PerformancePairExecutionArtifact
        let pairExecutionArtifactSHA256: String
        let pairEligibility: PerformancePairEligibility
        let baselineID: String
        let candidateID: String
        let metrics: [MetricComparison]
        let resilience: ResilienceMeasurement
        let seed: UInt64
        let resampleCount: Int
        let disposition: Disposition
    }

Only public persisted entry is the exact
`writeComparison(draft:baselineURL:candidateURL:pairExecutionURL:manualEvidenceDirectory:outputDirectory:configuration:eligibility:)`:
it reads the exact bytes at `baselineURL` and `candidateURL`, computes lowercase
64-hex SHA-256 values, decodes the measurement reports, runs internal preflight
for measurement/configuration/eligibility fields, and cross-checks the supplied
hash-free draft and existing `manualEvidenceDirectory`. It reads canonical
artifact bytes at `pairExecutionURL`; internal compare validates the decoded
`PerformancePairExecutionArtifact` and separate SHA and pairs samples by its
recorded indices. The writer owns and injects `reportKind == .comparison`,
`schemaVersion == 1`, and the two computed measurement-report hashes to
construct the final `PerformanceComparisonReport`, then atomically writes it.
There is no writer
overload without `manualEvidenceDirectory` or `pairExecutionURL`. Internal
`compare(baseline:candidate:configuration:eligibility:pairExecutionArtifact:manualEvidenceDirectory:pairExecutionArtifactSHA256:baselineMeasurementReportSHA256:candidateMeasurementReportSHA256:)`
returns only the hash-free `PerformanceComparisonDraft`; Task 3 loads and
validates `manualEvidenceDirectory` plus the decoded pair artifact and its
separate SHA before producing that draft. It is the Task 3 calculation seam,
deferred and non-writing in Task 2b, and recomputes/validates the canonical
pair-artifact SHA from the decoded artifact. Exact input measurement-byte/source-
URL hash verification remains public-writer-owned. The persisted report fields retain the exact
input-byte hashes.

    public struct PerformanceComparisonReport: Codable, Sendable {
        public let reportKind: PerformanceReportKind
        public let schemaVersion: Int
        public let harnessVersion: String
        public let foundationIdentity: FoundationIdentity
        public let buildContractVersion: String
        public let baselineBuildProvenance: BuildProvenance
        public let candidateBuildProvenance: BuildProvenance
        public let baselineRunProvenance: PerformanceRunProvenance
        public let candidateRunProvenance: PerformanceRunProvenance
        public let baselineMeasurementIdentity: MeasurementIdentity
        public let candidateMeasurementIdentity: MeasurementIdentity
        public let baselineFixture: FixtureIdentity
        public let candidateFixture: FixtureIdentity
        public let pairExecutionArtifact: PerformancePairExecutionArtifact
        public let pairExecutionArtifactSHA256: String
        public let baselineMeasurementReportSHA256: String
        public let candidateMeasurementReportSHA256: String
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

Each comparison persists the baseline and candidate
`PerformanceRunProvenance.configuration` values and their full
`baselineFixture`/`candidateFixture` values. Preflight requires each
configuration's `fixtureProfile`/`fixtureVersion` and each fixture's profile,
version, and mark count to match, while rejecting a comparison that mixes
fixture profiles.

    @MainActor
    public protocol RendererInstrumentationAdapter {
        func measureRenderer(configuration: PerformanceConfiguration) -> FrameMeasurement
    }

    @MainActor
    public protocol CompositorInstrumentationAdapter {
        func measureCompositor(configuration: PerformanceConfiguration) -> FrameMeasurement
    }

Both instrumentation protocols are value-type capable and impose no
`AnyObject` class constraint. `PerformanceHarness.run` receives the
configuration plus the validated `BuildProvenance` and
`PerformanceRunProvenance` that it embeds in the measurement report.

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
        public let evidence: ManualMetricEvidencePair
    }

    public struct ManualMetricEvidence: Codable, Sendable {
        public let metricID: PerformanceMetricID
        public let evidenceClass: MetricEvidenceClass
        public let variant: String
        public let sourceCommitSHA: String
        public let measurementReportSHA256: String
        public let pairExecutionArtifactSHA256: String
        public let host: String
        public let recordedAt: String
        public let permissions: [String]
        public let steps: String
        public let samples: [Double]
        public let result: String
        public let evidencePath: String
    }

    public struct ManualMetricEvidencePair: Codable, Sendable {
        public let procedureVersion: String
        public let pairOrders: [PairOrder]
        public let baseline: ManualMetricEvidence
        public let candidate: ManualMetricEvidence
    }

Manual evidence is pair-bound by `ManualMetricEvidencePair`: its baseline and
candidate entries each carry the variant, lowercase 40-hex commit, lowercase
64-hex measurement-report hash, lowercase 64-hex `pairExecutionArtifactSHA256`,
host, procedure steps, and samples. The pair carries `procedureVersion` and
typed `pairOrders`; both entries must use the same ordered steps, permissions,
evidencePath, and shared `procedureVersion`, with exactly the matching
compositor or input evidence files; extra or missing files are rejected.
Each manual evidence file is emitted by the same canonical encoder/adapter as
its schema and must be sorted-key JSON bytes; alternate whitespace or key order
or unknown fields are rejected before decoding/acceptance, even when the bytes
decode to an equivalent value.

    @MainActor
    public enum PerformanceCLI {
        public static func run(arguments: [String], outputDirectory: URL) throws
    }

The canonical metric map is a private validator table, not a public Codable
type: `model` uses nanoseconds with no absolute
budget; `renderer`, `compositor`, `combinedFrame`, `launchCold`, `launchWarm`,
`redrawLayout`,
`responsiveness`, and `inputToVisible` use milliseconds, with absolute budgets
only for `combinedFrame` (`16.7`) and `responsiveness`/`inputToVisible`
(`100`). `allocations` uses bytes with no absolute budget. `memoryRSS` uses
strictly positive absolute RSS bytes for `MetricComparison` samples; its
signed `finalWindowDeltaBytes` and `postWarmupSlopeBytesPerSecond` (B/s) remain
measurement-report fields validated during pair preflight, never comparison
sample units or an absolute-p95 budget. The unit and optional budget are
serialized in each `MetricComparison`; the validator rejects a wrong unit,
missing required budget, huge/wrong value, or unexpected budget on an
unbudgeted metric. These are canonical values, not report-supplied thresholds.

The v1 raw timing arrays are `FrameMeasurement.frameMilliseconds`,
`RedrawLayoutMeasurement.sampleMilliseconds`,
`ResponsivenessMeasurement.responseMilliseconds`, and
`InputToVisibleMeasurement.sampleMilliseconds`. A `measured` report must carry
exactly `configuration.trialCount` finite, strictly positive values in each
applicable array, and each stored p95 must be recomputed from that array;
`failed`/`unmeasured` diagnostic reports may carry empty arrays and make no p95
or completion claim. For every measured `FrameMeasurement`,
`missedFrameCount` is exactly the count of `frameMilliseconds` samples greater
than 16.7 ms; a mismatch is invalid.

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
SHA-256, authoritative `buildConfiguration` (`release`; bootstrap diagnostic
may use `debug`), UTC timestamp, foundation identity/version, harness version,
build-contract version, and optional accepted-foundation artifact SHA-256. It
contains no filesystem path, so it remains portable. `PerformanceRunProvenance`
embeds the complete BuildProvenance plus host, UTC timestamp, variant, output
root, source ref, measurement configuration, and optional artifact paths. An
authoritative post-foundation run requires a nonnil lowercase 64-hex
`acceptedFoundationArtifactSHA256` matching both the embedded build value and
the accepted foundation artifact; only a bootstrap diagnostic run may leave it
nil. The report's build/run provenance and configuration values must agree.
Structural measurement validation allows `measured`,
`failed`, and `unmeasured` so diagnostic failures round-trip honestly. If any
required metric is `failed` or `unmeasured`, structural validation requires
the measurement report disposition to be `revise`, never `blocked` or
`acceptedNoRegression`; `validateCompletion()` rejects required failed/unmeasured metrics, budget
breaches, leaks, invalid dispositions, or any non-measured required status.
Public `writeComparison(draft:baselineURL:candidateURL:pairExecutionURL:manualEvidenceDirectory:outputDirectory:configuration:eligibility:)`
reads and hashes both exact measurement files, decodes them, runs internal
preflight for measurement/configuration/eligibility fields, and cross-checks
all reports against the supplied hash-free draft. It reads canonical pair
artifact bytes at `pairExecutionURL`; internal compare validates the decoded
artifact and separate SHA, manual evidence, and recorded-index pairing before
the writer injects `reportKind == .comparison`, `schemaVersion == 1`, and the
measurement-report hashes to construct the final
`PerformanceComparisonReport` and writes only after all cross-checks pass. Internal
`compare(baseline:candidate:configuration:eligibility:pairExecutionArtifact:manualEvidenceDirectory:pairExecutionArtifactSHA256:baselineMeasurementReportSHA256:candidateMeasurementReportSHA256:)`
returns only the hash-free `PerformanceComparisonDraft`; Task 3 validates
`manualEvidenceDirectory` and the required decoded
`PerformancePairExecutionArtifact` plus its separate SHA before producing it,
pairing by recorded indices. It is deferred to Task 3 calculations and is
non-writing in Task 2b, and recomputes/validates the canonical pair-artifact SHA
from the decoded artifact. Exact input measurement-byte/source-URL hash
verification remains public-writer-owned. A hash,
identity, fixture, provenance, or eligibility mismatch therefore produces no
output. A persisted `PerformanceComparisonReport` therefore contains measured
comparisons only. Its structural validator requires
`reportKind == .comparison`, immutable baseline/candidate identities, matching
schema/harness/foundation/build-contract versions, matching host/fixture,
both typed `BuildProvenance` values, matching baseline/candidate
`PerformanceRunProvenance` values including their accepted-foundation SHA and
`buildConfiguration`, and full `baselineMeasurementIdentity` and
`candidateMeasurementIdentity` values. The two measurement identities must
match exactly for host model, macOS, Xcode, developerDirectory, power state,
display state, and buildConfiguration; their clean source commit identities
must be distinct, and each must match its run/build provenance. It requires
full `baselineFixture` and `candidateFixture` values, equal in every field,
and each matching its corresponding measurement report. It requires
`pairExecutionArtifactSHA256` to match the canonical bytes read by the public
writer and the decoded artifact passed to internal compare, with its exact
30-record contents and every metric's paired samples mapped by recorded
indices. It requires one `MetricComparison` for every
`PerformanceMetricID`, the canonical
`PerformanceMetricUnit`, and a canonical optional `budgetLimit` (finite and
positive only when that metric has an absolute budget). It requires nonempty
ratio/delta arrays with exactly
`configuration.totalPairs` (`pairsPerOrder * 2`) entries for every metric,
equal-length paired sample arrays, and finite strictly positive baseline and
candidate samples so each ratio is exact; for `memoryRSS`, comparison samples
are strictly positive absolute RSS bytes while signed
`finalWindowDeltaBytes` and `postWarmupSlopeBytesPerSecond` (B/s) stay in the
measurement report and are validated during pair preflight, not as comparison
sample units.
The `PerformancePairExecutionArtifact.records` are the sole observed
`PairOrder` source and must contain exactly 15 `.baselineFirst` entries followed
by exactly 15 `.candidateFirst` entries; metrics use their recorded sample
indices. The validator deterministically
recomputes `BootstrapInterval` from the paired `deltas`, `seed`, and
`resampleCount` and rejects any tampered interval summary or seed/count. The
`improvementClaimed` flag may be true only when that recomputed bootstrap
delta upper bound (`upperDelta`) is strictly below zero; it is false otherwise,
including for `acceptedNoRegression`, which is not an improvement claim.
`validateCompletion()` recomputes every ratio,
the ratio median, and the ratio p95; both ratio summaries must be at most
`1.10`. For metrics with a canonical absolute budget, it also recomputes
candidate p95 in that metric's unit and requires it to be at most the canonical
limit. `memoryRSS` is validated using absolute-RSS comparison samples plus its
report-level delta/slope, never an absolute-RSS p95 budget. Empty arrays,
nonfinite or nonpositive baseline or candidate
samples, stale supplied ratios/deltas, wrong units, missing/huge/unexpected
budgets, or budget/ratio breaches are rejected. It also requires valid
`BootstrapInterval` values and the conditional manual-evidence rule. A manual metric requires
complete `ManualMetricEvidencePair` with baseline/candidate
`ManualMetricEvidence` entries (variant, commit, measurement-report hash,
pair-artifact hash, host, timestamp, permissions, exact steps, samples, result,
and evidence path), pair `procedureVersion`, and typed `PairOrder` sequence.
The entries must use equivalent procedures and exactly the identity-bound
compositor or input evidence files; a deterministic metric must have nil manual
evidence. Deterministic comparisons require at least 30 samples. Its
`validateCompletion()` also requires the candidate renderer p95 plus candidate
compositor p95 to be at most the canonical `combinedFrame` limit of 16.7 ms,
and requires candidate combinedFrame p95 to be at most 16.7 ms. It validates
only this measured comparison shape and never
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
and phase per sample, plus `postWarmupSlopeBytesPerSecond`. The slope is the
ordinary least-squares slope of `(elapsedSeconds, rssBytes)` over all samples
whose phase is `running` and whose elapsed time is at or after the configured
warmup boundary (`warmupCount * sampleIntervalSeconds`); it requires at least
two distinct timestamps and is expressed in bytes per second. Structural
validation requires a finite slope; completion accepts no growth only when the
slope is at most the exact tolerance `1e-9` B/s and rejects positive growth
above that tolerance.

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
    func testMeasuredTimingArraysHaveExactTrialCountAndRecomputedP95()
    func testDiagnosticTimingArraysMayBeEmpty()
    func testBuildAndRunProvenanceAreDistinctAndPortable()
    func testPerformanceHarnessRunRequiresBuildAndRunProvenance()
    func testInstrumentationAdaptersPermitValueTypes()
    func testBuildProvenanceCarriesValidatedConfigurationAndFoundationSHA()
    func testAuthoritativeRunRequiresAcceptedFoundationArtifactSHA()
    func testPerformanceReportRoundTripsTypedProvenanceAndFoundationVersions()
    func testFixtureProfilesAreTypedAndIndependent()
    func testMemoryReportComputesPostWarmupLeastSquaresSlopeAndRejectsGrowth()
    func testStructurallyValidFailedAndUnmeasuredReportsRoundTrip()
    func testCompletionValidationRejectsFailedOrUnmeasuredRequiredMetric()
    func testMissingFailedOrUnmeasuredRequiredMetricUsesReviseNotBlocked()
    func testManualMetricComparisonRoundTripsCompleteEvidence()
    func testManualMetricComparisonWithoutEvidenceOrWithDeterministicEvidenceIsRejected()
    func testManualEvidenceRejectsNonCanonicalJSONBytes()
    func testComparisonRejectsFailedOrUnmeasuredInputBeforeWritingOutput()
    func testMemoryReportRequiresSeriesAggregatesPhasesAndCheckpoints()

Decode a fixture containing every field listed in the Interfaces section; assert
`reportKind == .measurement`, schemaVersion, identity, host, fixture, all ten
measurement objects, disposition, statuses, sample arrays, and
running/stopping/stopped/restarted phase counts. Decode a comparison fixture
with `reportKind == .comparison`; assert Codable preserves the typed enum, and
assert validateStructure() rejects a missing or wrong report kind rather than
accepting a generic dictionary value. Decode structurally valid reports with
measured, failed, and unmeasured statuses and assert they round-trip; for a
failed or unmeasured required metric, assert structural validation requires
disposition `revise`, never `blocked` or `acceptedNoRegression`. Decode a
manual MetricComparison with complete `ManualMetricEvidencePair` and assert
each baseline/candidate `ManualMetricEvidence` entry's variant, commit,
measurement-report hash, pair-artifact hash, host, timestamp, permissions,
exact steps, samples, result, and evidencePath survive round-trip. Also assert
the pair's procedure version and typed pair orders bind exactly the compositor
or input evidence files and equivalent procedures. Assert manual evidence is
written by the canonical sorted-key encoder and rejects alternate whitespace or
key order. Decode a manual comparison
with nil/empty evidence
and a deterministic comparison with nonnil manual evidence; assert
validateStructure() throws for both. Separately call validateCompletion() and
assert it throws for failed/unmeasured required metrics rather than silently
converting them to zero/default values. Round-trip the typed provenance,
`harnessVersion`, foundation identity/version, and build-contract version, and
assert mismatches are rejected, and assert `BuildProvenance` contains no path
or pair ancestry, carries `buildConfiguration`, and has an optional accepted
foundation SHA only in bootstrap diagnostics. Assert an authoritative
`PerformanceRunProvenance` requires a matching lowercase 64-hex accepted
foundation SHA while bootstrap diagnostics may leave it nil. Give the
comparison harness a structurally
valid measurement with a failed or unmeasured required metric and assert it
throws before constructing a `PerformanceComparisonReport` or writing an
output file; comparison reports contain measured comparisons only.
For measured reports, assert `FrameMeasurement.frameMilliseconds`,
`RedrawLayoutMeasurement.sampleMilliseconds`,
`ResponsivenessMeasurement.responseMilliseconds`, and
`InputToVisibleMeasurement.sampleMilliseconds` each contain exactly
`configuration.trialCount` finite, strictly positive values and that their
corresponding p95 fields are recomputed from the raw arrays; diagnostic
`failed`/`unmeasured` reports may carry empty timing arrays.

- [ ] **Step 2: Run RED.**

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PerformanceHarnessTests|PerformanceComparisonHarnessTests'

Expected: missing PerformanceMeasurementReport, PerformanceComparisonReport, and metric types fail compilation.

- [ ] **Step 3: Implement schema and validators.**

Use explicit Codable structs, not an untyped dictionary. Every required object
has exactly one `MeasurementStatus`. `PerformanceFixtureProfile` is the typed
profile input to the parameterized real `PointerSession` model and CanvasView
renderer oracles; `PerformanceConfiguration.fixtureProfile` and
`FixtureIdentity.fixtureProfile` carry that exact profile identity into each
report and run provenance.
`validateStructure()` checks model
samples/median/p95/MAD/publications/checksum/final state; frame sample/frame/
missed counts; launch cold/warm; allocation bytes/peak; redraw/layout; response
stalls; input samples/latency/missed samples; memory series/aggregates/matched
baseline/resource counts/phases; typed provenance and foundation/build
versions; and the conditional manualEvidence rule. It rejects a fixture-profile
mismatch or any attempt to concatenate `standard12` and `dense1000` populations.
The comparison harness
requires each measured raw timing array to contain exactly `trialCount` finite,
strictly positive values and recomputes its p95; failed/unmeasured diagnostics
may use empty arrays. The artifact records require the exact 15 baseline-first
then 15 candidate-first sequence, and metrics pair values by recorded sample
indices. It recomputes
the bootstrap interval from deltas/seed/resample count and rejects tampering;
`improvementClaimed` is true only when the recomputed delta upper bound is
strictly below zero and is false otherwise, including `acceptedNoRegression`.
It then performs a measured-status preflight on every required input metric and throws
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

Task 3b is the E-foundation adapter seam: it defines the compositor, process,
manual, and combined-frame protocols plus honest `.unmeasured`/`revise`
fallbacks. Task 3c is the E-foundation orchestration seam: E implements
`PerformanceCLI` and `scripts/benchmark-quality.sh` here, parameterized over
both `standard12` and `dense1000`, before F-foundation. F-foundation imports
and wires the existing CLI into the launcher; E-execution only consumes these
unchanged commands to produce the two fixture-profile evidence sets. Task 3c
also writes the typed `PerformanceCampaignCompletionManifest` only after
validating exactly one accepted comparison for each profile; an individual
`PerformanceComparisonReport` covers one profile and never aggregates both.

**Files:**

- Modify: Sources/PointerAppKit/Diagnostics/PerformanceHarness.swift
- Modify: Sources/PointerAppKit/Diagnostics/PerformanceComparisonHarness.swift
- Create: Sources/PointerAppKit/Diagnostics/PerformanceCLI.swift
- Modify: Tests/PointerAppKitTests/PerformanceHarnessTests.swift
- Modify: Tests/PointerAppKitTests/PerformanceComparisonHarnessTests.swift
- Create: Tests/PointerAppKitTests/PerformanceCLITests.swift
- Create: scripts/benchmark-quality.sh
- Create: .codex/sdd/reports/quality-campaign/performance/README.md
For each variant and each fixture profile, the script writes a separate
configuration/provenance and report set under these exact paths:

```text
build/standard12/baseline/Pointer.app
build/standard12/candidate/Pointer.app
build/standard12/pair-execution/partial/<pairOrder>-<pairIndex>.json
build/dense1000/baseline/Pointer.app
build/dense1000/candidate/Pointer.app
build/dense1000/pair-execution/partial/<pairOrder>-<pairIndex>.json
.codex/sdd/reports/quality-campaign/performance/standard12/measurements/{baseline,candidate}.json
.codex/sdd/reports/quality-campaign/performance/standard12/provenance/{baseline,candidate}.json
.codex/sdd/reports/quality-campaign/performance/standard12/comparisons/pair-eligibility.json
.codex/sdd/reports/quality-campaign/performance/standard12/comparisons/pair-execution.json
.codex/sdd/reports/quality-campaign/performance/standard12/comparisons/paired-comparison.json
.codex/sdd/reports/quality-campaign/performance/standard12/comparisons/manual/<metricID>.json
.codex/sdd/reports/quality-campaign/performance/standard12/resilience/resilience.json
.codex/sdd/reports/quality-campaign/performance/dense1000/measurements/{baseline,candidate}.json
.codex/sdd/reports/quality-campaign/performance/dense1000/provenance/{baseline,candidate}.json
.codex/sdd/reports/quality-campaign/performance/dense1000/comparisons/pair-eligibility.json
.codex/sdd/reports/quality-campaign/performance/dense1000/comparisons/pair-execution.json
.codex/sdd/reports/quality-campaign/performance/dense1000/comparisons/paired-comparison.json
.codex/sdd/reports/quality-campaign/performance/dense1000/comparisons/manual/<metricID>.json
.codex/sdd/reports/quality-campaign/performance/dense1000/resilience/resilience.json
.codex/sdd/reports/quality-campaign/performance/campaign-completion/manifest.json
```

The two profiles retain separate resilience outputs alongside their comparison
directories. Task 3c writes the typed `PerformanceCampaignCompletionManifest`
at the final path only after it has loaded exactly one accepted comparison for
each profile; it rejects missing, duplicate, or concatenated profiles. No path
is reused across profiles, and no aggregate combines the two sample
populations.

- [ ] **Step 1: Write failing paired-protocol tests.**

    func testPerformanceComparisonReportRoundTripsIDsSamplesRatiosBootstrapAndDisposition()
    func testPairedProtocolUsesImmutableIdentitiesFixedSeedWarmupsAndThirtyTrials()
    func testMeasurementCLIRejectsBothOrNeitherSourceIdentity()
    func testDirectComparisonHarnessCannotBypassPairEligibility()
    func testComparisonCLIRequiresReportPathsAndPairEligibilityFile()
    func testComparisonCarriesFullMeasurementIdentitiesAndExactPairArrays()
    func testComparisonPersistsEqualMatchingFixtures()
    func testComparisonWriterRejectsMeasurementByteHashMismatchWithoutOutput()
    func testComparisonWriterRejectsIdentityMismatchWithoutOutput()
    func testComparisonWriterRejectsFixtureMismatchWithoutOutput()
    func testComparisonWriterRejectsProvenanceMismatchWithoutOutput()
    func testComparisonWriterRejectsEligibilityMismatchWithoutOutput()
    func testComparisonWriterInjectsExactInputHashesIntoPersistedReport()
    func testCampaignCompletionManifestRequiresBothFixtureProfilesAndSeparateArtifacts()
    func testComparisonDraftIsOpaqueAndWriterInjectsReportMetadata()
    func testCampaignCompletionManifestRejectsDuplicateOrConcatenatedProfiles()
    func testPairExecutionArtifactHasThirtyUniqueIndexedRecords()
    func testComparisonPairsByRecordedIndicesAndRejectsArtifactMismatch()
    func testBenchmarkQualityInterleavesBaselineAndCandidatePerTrial()
    func testManualEvidencePairBindsVariantsCommitsHashesArtifactAndProcedure()
    func testInternalComparisonCalculationIsDeferredAndNonWriting()
    func testInternalComparisonLoadsAndValidatesManualEvidenceBeforeDraft()
    func testPairExecutionArtifactCarriesTypedOrderSequence()
    func testImprovementClaimRequiresRecomputedBootstrapUpperBound()
    func testBootstrapIntervalRejectsTamperedSummary()
    func testMetricComparisonRejectsNonfiniteOrNonpositiveSamplesOrInvalidBudget()
    func testComparisonCompletionRecomputesRatioAndCandidateP95()
    func testMetricComparisonRejectsWrongUnitAndUnexpectedBudget()
    func testMemoryComparisonUsesDeltaAndSlopeNotAbsoluteP95()
    func testComparisonRejectsRendererPlusCompositorBudgetBreach()
    func testBootstrapIntervalOnlyClaimsImprovementWhenUpperBoundIsBelowZero()
    func testBudgetRegressionAndMissingMetricDispositionIsRevise()
    func testResilienceReportCoversModeToolsMarksClearUndoDisplayChurnAndShortcutTimeout()
    func testRunningStopAndRestartResourceCheckpointsAreIndependent()

Assert `PerformanceComparisonReport` contains `reportKind == .comparison`,
immutable baselineID/candidateID, one `MetricComparison` for every
`PerformanceMetricID`, paired baseline/candidate samples, ratios/deltas,
`BootstrapInterval` seed 48271/10,000 resamples, and per-metric dispositions.
Also assert full `baselineMeasurementIdentity` and
`candidateMeasurementIdentity` fields, exact equality for host model, macOS,
Xcode, developerDirectory, power/display state, and buildConfiguration, with
distinct source commits matching each run/build provenance. Require nonempty
ratios/deltas of exactly `totalPairs == pairsPerOrder * 2 == 30` per metric.
Round-trip artifact `records` and require exactly 15 `PairOrder.baselineFirst`
entries followed by exactly 15 `PairOrder.candidateFirst` entries, with every
metric paired by recorded sample indices. Assert `improvementClaimed` is true only
when the recomputed bootstrap delta upper bound (`upperDelta`) is strictly
below zero; it is false otherwise, including for `acceptedNoRegression`, which
is not an improvement claim. Recompute each `BootstrapInterval` from the
paired deltas, seed, and resample count and reject tampered summaries or seed/
count values.
Round-trip `PerformancePairExecutionArtifact` and require exactly 30 unique
records, 15 of each order, with only pairIndex/order, baseline/candidate sample
indices, and `baselineStartedAtUTC`, `candidateStartedAtUTC`,
`baselineEndedAtUTC`, and `candidateEndedAtUTC`; assert the artifact-level baseline/candidate
IDs and lowercase 64-hex report hashes. Assert the artifact hash is verified,
samples are paired by recorded indices, and an artifact/hash/order mismatch
causes both internal comparison and public writing to produce no output.
Round-trip lowercase 64-hex `baselineMeasurementReportSHA256` and
`candidateMeasurementReportSHA256` fields, and assert the writer computes and
verifies them against the exact input report bytes, injects them into the final
persisted report, injects `reportKind == .comparison` and `schemaVersion == 1`,
and emits output atomically. Assert the public `Sendable, Equatable`
`PerformanceComparisonDraft` surface has no initializer or stored properties;
its internal compare-only
carrier excludes those metadata and hash fields.
Exercise both `PerformanceFixtureProfile` values and assert each variant has
exactly one configuration/provenance and measurement report for
`standard12` (`pointer-fixture-standard12/v1`, identifier
`pointer-standard-12-marks`, 12 marks) and `dense1000`
(`pointer-fixture-dense1000/v1`, identifier `pointer-dense-1000-marks`, 1,000
marks). Assert their measurement, provenance, pair-artifact, comparison,
resilience, and output-root paths remain distinct, their
`PerformanceConfiguration.fixtureProfile`/`fixtureVersion` and
`FixtureIdentity.fixtureProfile`/`fixtureVersion`/`markCount` values match
end-to-end, and the Task 3c completion manifest rejects either missing profile,
duplicate profile, or concatenated cross-profile population. Apply
the 16.7 ms renderer-plus-compositor and combined-frame p95 gates separately
to both profiles.
Call only the public
`writeComparison(draft:baselineURL:candidateURL:pairExecutionURL:manualEvidenceDirectory:outputDirectory:configuration:eligibility:)`
writer with a hash-free `PerformanceComparisonDraft`, persisted report paths,
the required existing manual-evidence directory (empty for deterministic runs),
and the required pair-execution artifact URL; assert there is no writer
overload without either required input;
assert that internal decoded
`compare(baseline:candidate:configuration:eligibility:pairExecutionArtifact:manualEvidenceDirectory:pairExecutionArtifactSHA256:baselineMeasurementReportSHA256:candidateMeasurementReportSHA256:)`
receives the decoded artifact plus separate SHA, validates manual evidence and
artifact records, recomputes/validates the canonical artifact SHA before
producing the draft, and remains calculation-deferred and non-writing in Task
2b. Exact input measurement-byte/source-URL hash verification remains public-
writer-owned. The public writer rejects byte-hash, identity, fixture,
provenance, or eligibility mismatches without creating an output file.
Round-trip persisted `baselineFixture` and `candidateFixture` values, assert
they are equal and match the corresponding measurement reports, reject
nonfinite or nonpositive baseline/candidate samples or
nonfinite/nonpositive `budgetLimit`, and prove
completion recomputes ratio median/p95 at most `1.10` and candidate p95 within
the canonical absolute budget. Round-trip `MetricComparison.unit`, reject
wrong-unit and unexpected/huge/missing budgets against the canonical metric
map, and verify `memoryRSS` comparison samples are strictly positive absolute
RSS bytes while signed `finalWindowDeltaBytes` and
`postWarmupSlopeBytesPerSecond` (B/s) remain measurement-report fields
validated during pair preflight, not comparison sample units.
Reject a candidate whose renderer p95 plus compositor p95 exceeds 16.7 ms,
or whose combinedFrame p95 exceeds 16.7 ms.
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
harness version, build-contract version, and exact `buildConfiguration`
(`release` for authoritative builds, `debug` only for bootstrap diagnostics).
E's `benchmark-quality.sh` is the
sole creator of `PerformanceRunProvenance` and `PerformancePairEligibility`:
it consumes two validated BuildProvenance files plus roots/refs/foundation and
creates each run envelope with the same accepted-foundation artifact SHA as
the embedded build, or nil only for bootstrap diagnostics,
proves Git cleanliness, ancestry, source checkout to built executable
correspondence, and executable hash equality before invoking the app. It
passes `--run-provenance-file <path>` to `PerformanceCLI`; the app validates
the envelope syntax and decodes/cross-checks its embedded BuildProvenance, then
embeds the build/run artifacts in the report, but does not claim Git state or
ancestry on the shell's behalf.

The current `OffscreenCanvasRendererAdapter` measures the real
CanvasView/CGContext renderer path. The current
`SignpostWindowServerAdapter`, `UnavailableCombinedFrameAdapter`, and
`DefaultProcessMetricsAdapter` return honest `.unmeasured` values; a
`CACurrentMediaTime` duration is not WindowServer compositor measurement, and
`combinedFrame` is not a renderer-plus-compositor sum. `ManualMetricAdapter`
currently provides only the Codable evidence schema; its Task 3c writer is not
yet present. Task 3b defines these compositor, process, manual, and
combined-frame protocols and their `.unmeasured`/`revise` fallbacks. The
the model/renderer fixture code is profile-aware for both standard12 and
dense1000, with parameterized fixture construction and semantic checks covered
by tests. Task 3c
and E-execution supply external trace/process/manual evidence and sidecars
through those protocols. None synthesizes input or captures the screen. Define
the separate model, renderer, compositor, combined frame, launch, allocation,
redraw/layout, responsiveness, input-to-visible, and 600-second memory runs
for each fixture profile, plus the repeated-toggle, rapid-tool, 1,000-mark,
clear/undo, palette, display-churn, and shortcut-timeout resource checks. If
the host cannot instrument an OS-level metric, record `unmeasured` with its
adapter status and keep `validateCompletion()`/disposition `revise`; never
fabricate a measured value. Keep manual metric evidence in
`ManualMetricEvidence` and the final ledger; deterministic tests cannot
substitute for missing measured physical evidence. This step defines the
protocol but does not pin or execute a paired baseline/candidate run; that is
E-execution after F tasks 1–3.

- [ ] **Step 4: Implement report disposition and foundation handoff.**

Ratios at most 1.10 with no breach, leak, or missing metric may be
`acceptedNoRegression`; any ratio above 1.10, breach, leak, invalid structure,
or measurement report with a failed or unmeasured required metric structurally
requires disposition `revise` (never `blocked` or `acceptedNoRegression`) and
blocks completion. Structural report generation still preserves
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
  --fixture-profile standard12|dense1000 \
  (--source-commit-sha <40hex> | --content-manifest-sha256 <64hex>) \
  --run-provenance-file <path> --output-dir <directory>
Pointer --quality-compare --format json \
  --fixture-profile standard12|dense1000 \
  --baseline-report <path> --candidate-report <path> \
  --pair-eligibility-file <path> \
  --pair-execution-artifact <path> \
  --manual-evidence-dir <comparisons/manual> \
  --output-dir <comparisons>
```

For paired execution, each `--quality-performance` invocation carries
`--fixture-profile standard12|dense1000` and additionally accepts
`--pair-order baselineFirst|candidateFirst`, `--pair-index <0...29>`, and
`--partial-pair-artifact <path>`; indices 0–14 are
`.baselineFirst` and 15–29 are `.candidateFirst`, and each invocation records
one variant trial into that partial artifact. `benchmark-quality.sh` invokes the
two variants per trial in the required order, writes aggregate reports and
their hashes, then assembles the 30 partials into the final
`PerformancePairExecutionArtifact` before compare.

The first command emits one `PerformanceMeasurementReport`; for the second,
`--manual-evidence-dir` must name an existing directory and binds directly to
`manualEvidenceDirectory` on internal `compare` and the public
`writeComparison`. Internal
`compare` loads and validates that evidence before
returning the hash-free draft; deterministic runs require the directory to be
empty. The second emits one authoritative
`PerformanceComparisonReport` only for clean 40-hex commit
identities whose typed eligibility file has already passed the lineage/
foundation checks. The typed `reportKind` field makes the distinction
structural. A measurement command may still accept a content-manifest identity
for diagnostic runs, but the authoritative compare rejects that identity and
does not write a promoted comparison. Scripts orchestrate roots/refs/builds
and then invoke these report-path commands, while F wires the launcher
branches after its Release foundation is accepted. No report is written at
the performance root.

## Task 4: Execute the paired immutable protocol after F-foundation

This task starts only after F tasks 1–3 pass their worker, reviewer, and
adversarial gates and produce the accepted foundation artifact. The execution
consumes the E-foundation `PerformanceCLI` and
`scripts/benchmark-quality.sh` implementations; it does not modify their
source or claim code/script ownership. The authoritative comparison lineage
uses clean 40-hex baseline and candidate
commits only; content-manifest measurements remain diagnostic-only and cannot
be promoted or compared authoritatively without a separately accepted lineage
artifact. At execution time, resolve both commits, verify clean checkout/head
correspondence and ancestry, and build each commit with F's explicit
fixture-profile-specific output-root contract. Pin the baseline only after the
foundation checkpoint; a stale report, dirty checkout, symbolic label, prior D
checkpoint, or missing fixture profile is not eligible.

- [ ] **Step 1:** Observe and record the accepted foundation artifact,
  baseline/candidate refs, both exact fixture profiles, host, fixture, E
  schema/harness version, and F foundation identity. Require each source
  worktree to be clean and
  `HEAD == <40hex ref>`, then require
  `git merge-base --is-ancestor <baseline-ref> <candidate-ref>`. Require the
  foundation checkpoint commit to be an ancestor of both refs. The candidate
  must be a subsequent measured commit with the same host/fixture and both
  exact fixture profiles, but a different clean 40-hex commit identity; a
  content-manifest identity is
  diagnostic-only and is rejected by the authoritative compare.
- [ ] **Step 2:** Run both variants for each fixture profile, then that profile's
  comparison and resilience output:

      for fixture_profile in standard12 dense1000; do
        DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/benchmark-quality.sh \
          --fixture-profile "$fixture_profile" \
          --baseline-commit-sha <40hex-baseline> --candidate-commit-sha <40hex-candidate> \
          --baseline-root "build/$fixture_profile/baseline" --candidate-root "build/$fixture_profile/candidate" \
          --foundation-provenance .codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json \
          --manual-evidence-dir ".codex/sdd/reports/quality-campaign/performance/$fixture_profile/comparisons/manual" \
          --output-dir ".codex/sdd/reports/quality-campaign/performance/$fixture_profile"
      done

  `benchmark-quality.sh` creates scoped source worktrees at the two refs for
  the selected fixture profile, and the Task 3c implementation loops over both
  `standard12` and `dense1000` without sharing a build or report path. It
  verifies clean status, exact `HEAD` values, ancestry, and foundation
  checkpoint ancestry, validates the explicit accepted foundation provenance,
  then invokes F's
  `scripts/build-app.sh --output-root build/<fixture-profile>/baseline --build-configuration
  release --foundation-provenance
  .codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json` and
  `scripts/build-app.sh --output-root build/<fixture-profile>/candidate --build-configuration
  release --foundation-provenance
  .codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json`.
  Each output root must
  contain exactly `Pointer.app`, `source-manifest.sha256`,
  `bundle-manifest.sha256`, and build-only `provenance.json`; the script
  hashes each executable and cross-checks it against that BuildProvenance
  before passing the per-variant `--run-provenance-file` to
  `--quality-performance`. It alone creates the per-variant
  `PerformanceRunProvenance` and `PerformancePairEligibility`, then
  interleaves per-trial measurement: for pair indices 0 through 14 it runs
  one baseline→candidate trial, then for pair indices 15 through 29 it runs
  one candidate→baseline trial. Each per-trial CLI invocation writes a partial
  record under `build/<fixture-profile>/pair-execution/partial/<pairOrder>-<pairIndex>.json`;
  the script assembles and writes the aggregate measurement reports at
  `build/<fixture-profile>/baseline/measurements/measurement.json` and
  `build/<fixture-profile>/candidate/measurements/measurement.json` plus each
  `<variantRoot>/run-provenance.json`, computes their exact report hashes,
  finalizes the typed records with those hashes, and persists
  `performance/<fixture-profile>/comparisons/pair-execution.json` before invoking compare. The
  per-trial form is

      Pointer --quality-performance --format json --variant baseline|candidate \
        --fixture-profile <standard12|dense1000> \
        (--source-commit-sha <40hex> | --content-manifest-sha256 <64hex>) \
        --run-provenance-file <path> --output-dir <variantRoot> \
        --pair-order baselineFirst|candidateFirst --pair-index <0...29> \
        --partial-pair-artifact build/<fixture-profile>/pair-execution/partial/<pairOrder>-<pairIndex>.json

  and the script invokes the two variants for each pair before advancing to the
  next index. It never runs a whole baseline batch
  before a whole candidate batch. It publishes byte-identical copies as
  `performance/<fixture-profile>/measurements/baseline.json` and `candidate.json`,
  writes the typed `performance/<fixture-profile>/comparisons/pair-eligibility.json`,
  then invokes the
  compare CLI with only report paths:

      Pointer --quality-compare --format json \
        --fixture-profile <standard12|dense1000> \
        --baseline-report build/<fixture-profile>/baseline/measurements/measurement.json \
        --candidate-report build/<fixture-profile>/candidate/measurements/measurement.json \
        --pair-eligibility-file .codex/sdd/reports/quality-campaign/performance/<fixture-profile>/comparisons/pair-eligibility.json \
        --pair-execution-artifact .codex/sdd/reports/quality-campaign/performance/<fixture-profile>/comparisons/pair-execution.json \
        --manual-evidence-dir .codex/sdd/reports/quality-campaign/performance/<fixture-profile>/comparisons/manual \
        --output-dir .codex/sdd/reports/quality-campaign/performance/<fixture-profile>/comparisons

  The compare rejects
  content-manifest identities, mismatched refs/provenance/foundation, and any
  failed or unmeasured input before writing
  `<fixture-profile>/comparisons/paired-comparison.json`; resilience remains at
  `<fixture-profile>/resilience/resilience.json`. It exits nonzero on missing IDs,
  missing profiles, cross-profile paths, nonzero CLI
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
and E/F sequencing, executable PerformanceCLI/benchmark-quality ordering,
typed `standard12`/`dense1000` fixture profiles with separate output paths and
per-profile 16.7 ms gates, honest current adapter fallbacks plus external
evidence sidecars, allowed instrumentation adapters, production-path metrics,
memory/resource phases, budgets, resilience runs, evidence reports, and
required review loop are covered. No commit
instruction or cross-workstream source edit is included.
