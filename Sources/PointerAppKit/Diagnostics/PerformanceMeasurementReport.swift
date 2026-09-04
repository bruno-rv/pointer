import Foundation

public enum MeasurementStatus: String, Codable, Sendable, Equatable {
    case measured
    case failed
    case unmeasured
}

public enum Disposition: String, Codable, Sendable, Equatable {
    case acceptedNoRegression
    case revise
    case blocked
}

public enum PerformanceReportKind: String, Codable, Sendable, Equatable {
    case measurement
    case comparison
}

public enum MemoryPhase: String, Codable, Sendable, Equatable, CaseIterable {
    case running
    case stopping
    case stopped
    case restarted
}

public enum SourceIdentityKind: String, Codable, Sendable, Equatable {
    case sourceCommitSHA
    case contentManifestSHA256
}

public enum SourceTreeStatus: String, Codable, Sendable, Equatable {
    case clean
    case dirty
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

    fileprivate static func canonical(for markCount: Int) -> PerformanceFixtureProfile {
        markCount == dense1000.markCount ? .dense1000 : .standard12
    }
}

public enum MetricEvidenceClass: String, Codable, Sendable, Equatable {
    case deterministic
    case manual
}

public enum PerformanceMetricID: String, CaseIterable, Codable, Sendable, Equatable {
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

public enum PerformanceValidationError: Error, Equatable, CustomStringConvertible,
    Sendable {
    case invalid(String)

    public var description: String {
        switch self {
        case let .invalid(message): return message
        }
    }
}

public struct MeasurementIdentity: Codable, Sendable, Equatable {
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

extension FixtureIdentity {
    init(
        identifier: String,
        markCount: Int,
        continuationSamples: Int,
        warmupCount: Int,
        trialCount: Int,
        seed: UInt64
    ) {
        let profile = PerformanceFixtureProfile.canonical(for: markCount)
        self.init(
            identifier: profile.identifier,
            fixtureProfile: profile,
            fixtureVersion: profile.version,
            markCount: markCount,
            continuationSamples: continuationSamples,
            warmupCount: warmupCount,
            trialCount: trialCount,
            seed: seed
        )
    }
}

public struct PerformanceConfiguration: Codable, Sendable, Equatable {
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
        fixtureVersion: PerformanceFixtureProfile.standard12.version,
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
        fixtureVersion: PerformanceFixtureProfile.dense1000.version,
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

    public var isCanonical: Bool {
        self == .standard12 || self == .dense1000
    }
}

public extension PerformanceConfiguration {
    init(
        fixtureMarkCount: Int,
        samplesPerGesture: Int,
        warmupCount: Int,
        trialCount: Int,
        pairsPerOrder: Int,
        bootstrapSeed: UInt64,
        bootstrapResamples: Int,
        memoryWindowSeconds: Int,
        memorySampleIntervalSeconds: Int,
        harnessVersion: String,
        foundationIdentity: FoundationIdentity,
        buildContractVersion: String
    ) {
        let profile = PerformanceFixtureProfile.canonical(for: fixtureMarkCount)
        self.init(
            fixtureMarkCount: fixtureMarkCount,
            fixtureProfile: profile,
            fixtureVersion: profile.version,
            samplesPerGesture: samplesPerGesture,
            warmupCount: warmupCount,
            trialCount: trialCount,
            pairsPerOrder: pairsPerOrder,
            bootstrapSeed: bootstrapSeed,
            bootstrapResamples: bootstrapResamples,
            memoryWindowSeconds: memoryWindowSeconds,
            memorySampleIntervalSeconds: memorySampleIntervalSeconds,
            harnessVersion: harnessVersion,
            foundationIdentity: foundationIdentity,
            buildContractVersion: buildContractVersion
        )
    }
}

public struct PerformanceRunProvenance: Codable, Sendable, Equatable {
    public let variant: String
    public let outputRoot: String
    public let sourceRef: String
    public let build: BuildProvenance
    public let host: HostIdentity
    public let recordedAtUTC: String
    public let configuration: PerformanceConfiguration
    public let foundationProvenancePath: String
    public let foundation: FoundationIdentity
    public let harnessVersion: String
    public let buildContractVersion: String
    public let acceptedFoundationArtifactSHA256: String?
}

internal extension PerformanceRunProvenance {
    func validateStructure() throws {
        try PerformanceReportValidator.validateRunProvenance(self)
    }
}

public struct ModelMeasurement: Codable, Sendable, Equatable {
    public let status: MeasurementStatus
    public let trialNanoseconds: [Double]
    public let medianNanoseconds: Double
    public let p95Nanoseconds: Double
    public let madNanoseconds: Double
    public let publicationCount: Int
    public let modelChecksum: String
    public let finalStateValid: Bool
}

public struct FrameMeasurement: Codable, Sendable, Equatable {
    public let status: MeasurementStatus
    public let sampleCount: Int
    public let p95Milliseconds: Double
    public let frameMilliseconds: [Double]
    public let frameCount: Int
    public let missedFrameCount: Int
    public let instrumentationStatus: String
}

public extension FrameMeasurement {
    init(
        status: MeasurementStatus,
        sampleCount: Int,
        p95Milliseconds: Double,
        frameCount: Int,
        missedFrameCount: Int,
        instrumentationStatus: String
    ) {
        self.init(
            status: status,
            sampleCount: sampleCount,
            p95Milliseconds: p95Milliseconds,
            frameMilliseconds: [],
            frameCount: frameCount,
            missedFrameCount: missedFrameCount,
            instrumentationStatus: instrumentationStatus
        )
    }
}

public struct LaunchMeasurement: Codable, Sendable, Equatable {
    public let status: MeasurementStatus
    public let coldMilliseconds: [Double]
    public let warmMilliseconds: [Double]
}

public struct AllocationMeasurement: Codable, Sendable, Equatable {
    public let status: MeasurementStatus
    public let bytesPerGesture: [Int64]
    public let peakAllocationBytes: Int64
}

public struct RedrawLayoutMeasurement: Codable, Sendable, Equatable {
    public let status: MeasurementStatus
    public let redrawsPerSample: [Int]
    public let layoutPasses: [Int]
    public let p95Milliseconds: Double
    public let sampleMilliseconds: [Double]
}

public extension RedrawLayoutMeasurement {
    init(
        status: MeasurementStatus,
        redrawsPerSample: [Int],
        layoutPasses: [Int],
        p95Milliseconds: Double
    ) {
        self.init(
            status: status,
            redrawsPerSample: redrawsPerSample,
            layoutPasses: layoutPasses,
            p95Milliseconds: p95Milliseconds,
            sampleMilliseconds: []
        )
    }
}

public struct ResponsivenessMeasurement: Codable, Sendable, Equatable {
    public let status: MeasurementStatus
    public let stallCount: Int
    public let maximumMainThreadStallMilliseconds: Double
    public let p95ResponseMilliseconds: Double
    public let responseMilliseconds: [Double]
}

public extension ResponsivenessMeasurement {
    init(
        status: MeasurementStatus,
        stallCount: Int,
        maximumMainThreadStallMilliseconds: Double,
        p95ResponseMilliseconds: Double
    ) {
        self.init(
            status: status,
            stallCount: stallCount,
            maximumMainThreadStallMilliseconds: maximumMainThreadStallMilliseconds,
            p95ResponseMilliseconds: p95ResponseMilliseconds,
            responseMilliseconds: []
        )
    }
}

public struct InputToVisibleMeasurement: Codable, Sendable, Equatable {
    public let status: MeasurementStatus
    public let sampleCount: Int
    public let p95Milliseconds: Double
    public let missedSampleCount: Int
    public let sampleMilliseconds: [Double]
}

public extension InputToVisibleMeasurement {
    init(
        status: MeasurementStatus,
        sampleCount: Int,
        p95Milliseconds: Double,
        missedSampleCount: Int
    ) {
        self.init(
            status: status,
            sampleCount: sampleCount,
            p95Milliseconds: p95Milliseconds,
            missedSampleCount: missedSampleCount,
            sampleMilliseconds: []
        )
    }
}

public struct ResourceCounts: Codable, Sendable, Equatable {
    public let overlays: Int
    public let timers: Int
    public let handlers: Int
    public let windows: Int
    public let observers: Int
}

public struct MemorySample: Codable, Sendable, Equatable {
    public let elapsedSeconds: Double
    public let rssBytes: Int64
    public let phase: MemoryPhase
    public let resources: ResourceCounts
}

public struct MemoryAggregate: Codable, Sendable, Equatable {
    public let intervalIndex: Int
    public let sampleCount: Int
    public let meanRSSBytes: Int64
    public let peakRSSBytes: Int64
}

public struct MemoryMeasurement: Codable, Sendable, Equatable {
    public let status: MeasurementStatus
    public let windowSeconds: Int
    public let sampleIntervalSeconds: Int
    public let samples: [MemorySample]
    public let aggregates: [MemoryAggregate]
    public let peakRSSBytes: Int64
    public let finalWindowDeltaBytes: Int64
    public let finalWindowDeltaPercent: Double
    public let postWarmupSlopeBytesPerSecond: Double
    public let matchedBaselineSeries: [Double]
    public let matchedBaselineValues: [Int64]
    public let peakLiveResourceCounts: ResourceCounts
    public let endLiveResourceCounts: ResourceCounts
}

public extension MemoryMeasurement {
    init(
        status: MeasurementStatus,
        windowSeconds: Int,
        sampleIntervalSeconds: Int,
        samples: [MemorySample],
        aggregates: [MemoryAggregate],
        peakRSSBytes: Int64,
        finalWindowDeltaBytes: Int64,
        finalWindowDeltaPercent: Double,
        matchedBaselineSeries: [Double],
        matchedBaselineValues: [Int64],
        peakLiveResourceCounts: ResourceCounts,
        endLiveResourceCounts: ResourceCounts
    ) {
        self.init(
            status: status,
            windowSeconds: windowSeconds,
            sampleIntervalSeconds: sampleIntervalSeconds,
            samples: samples,
            aggregates: aggregates,
            peakRSSBytes: peakRSSBytes,
            finalWindowDeltaBytes: finalWindowDeltaBytes,
            finalWindowDeltaPercent: finalWindowDeltaPercent,
            postWarmupSlopeBytesPerSecond: 0,
            matchedBaselineSeries: matchedBaselineSeries,
            matchedBaselineValues: matchedBaselineValues,
            peakLiveResourceCounts: peakLiveResourceCounts,
            endLiveResourceCounts: endLiveResourceCounts
        )
    }
}

public struct ResilienceCase: Codable, Sendable, Equatable {
    public let identifier: String
    public let status: MeasurementStatus
    public let iterationCount: Int
    public let peakResourceCounts: ResourceCounts
    public let endResourceCounts: ResourceCounts
    public let leakedResource: Bool
    public let unexpectedGrowth: Bool
}

public struct ResilienceMeasurement: Codable, Sendable, Equatable {
    public let status: MeasurementStatus
    public let cases: [ResilienceCase]
    public let disposition: Disposition
}

public struct BootstrapInterval: Codable, Sendable, Equatable {
    public let lowerDelta: Double
    public let upperDelta: Double
    public let seed: UInt64
    public let resampleCount: Int
}

public struct PerformanceMeasurementReport: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

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

    public func validateStructure() throws {
        try PerformanceReportValidator.validateStructure(self)
    }

    public func validateCompletion() throws {
        try PerformanceReportValidator.validateCompletion(self)
    }
}

internal enum PerformanceReportValidator {
    private static let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")
    private static let emptyResources = ResourceCounts(overlays: 0, timers: 0, handlers: 0, windows: 0, observers: 0)
    private static let memorySlopeNoiseToleranceBytesPerSecond = 1e-9

    static func validateStructure(_ report: PerformanceMeasurementReport) throws {
        try require(report.reportKind == .measurement, "reportKind must be measurement")
        try require(report.schemaVersion == PerformanceMeasurementReport.currentSchemaVersion, "unsupported schemaVersion")
        try require(!report.harnessVersion.isEmpty, "harnessVersion is required")
        try require(!report.buildContractVersion.isEmpty, "buildContractVersion is required")
        try validateIdentity(report.identity, against: report.buildProvenance)
        try validateHost(report.host)
        try validateFixture(report.fixture)
        try validateBuild(report.buildProvenance)
        try validateRun(report.runProvenance)

        try require(report.runProvenance.build == report.buildProvenance, "run/build provenance mismatch")
        try require(report.runProvenance.host == report.host, "run/host mismatch")
        try require(report.runProvenance.configuration.fixtureMarkCount == report.fixture.markCount, "fixture mark count mismatch")
        try require(report.runProvenance.configuration.samplesPerGesture == report.fixture.continuationSamples, "fixture sample count mismatch")
        try require(report.runProvenance.configuration.warmupCount == report.fixture.warmupCount, "fixture warmup count mismatch")
        try require(report.runProvenance.configuration.trialCount == report.fixture.trialCount, "fixture trial count mismatch")
        try validateConfiguration(report.runProvenance.configuration)
        try require(report.harnessVersion == report.runProvenance.harnessVersion, "report/run harness version mismatch")
        try require(report.harnessVersion == report.buildProvenance.harnessVersion, "report/build harness version mismatch")
        try require(report.harnessVersion == report.runProvenance.configuration.harnessVersion, "report/configuration harness version mismatch")
        try require(report.foundationIdentity == report.runProvenance.foundation, "report/run foundation mismatch")
        try require(report.foundationIdentity == report.buildProvenance.foundation, "report/build foundation mismatch")
        try require(report.foundationIdentity == report.runProvenance.configuration.foundationIdentity, "report/configuration foundation mismatch")
        try require(report.buildContractVersion == report.runProvenance.buildContractVersion, "report/run build contract mismatch")
        try require(report.buildContractVersion == report.buildProvenance.buildContractVersion, "report/build build contract mismatch")
        try require(report.buildContractVersion == report.runProvenance.configuration.buildContractVersion, "report/configuration build contract mismatch")
        try require(report.buildProvenance.buildConfiguration == report.identity.buildConfiguration, "report/build configuration mismatch")
        let statuses: [MeasurementStatus] = [
            report.model.status,
            report.renderer.status,
            report.compositor.status,
            report.combinedFrame.status,
            report.launch.status,
            report.allocations.status,
            report.redrawLayout.status,
            report.responsiveness.status,
            report.inputToVisible.status,
            report.memory.status,
            report.resilience.status,
        ]
        if statuses.contains(where: { $0 == .failed || $0 == .unmeasured }) {
            try require(report.disposition == .revise, "failed or unmeasured reports require revise disposition")
        }

        try validateModel(report.model)
        try validateFrame(report.renderer)
        try validateFrame(report.compositor)
        try validateFrame(report.combinedFrame)
        try validateLaunch(report.launch)
        try validateAllocations(report.allocations)
        try validateRedrawLayout(report.redrawLayout)
        try validateResponsiveness(report.responsiveness)
        try validateInputToVisible(report.inputToVisible)
        try validateMemory(report.memory, warmupCount: report.runProvenance.configuration.warmupCount, trialCount: report.runProvenance.configuration.trialCount)
        try validateResilience(report.resilience)
        try validateMeasuredCounts(report)
    }

    static func validateCompletion(_ report: PerformanceMeasurementReport) throws {
        try validateStructure(report)
        let statuses: [MeasurementStatus] = [
            report.model.status,
            report.renderer.status,
            report.compositor.status,
            report.combinedFrame.status,
            report.launch.status,
            report.allocations.status,
            report.redrawLayout.status,
            report.responsiveness.status,
            report.inputToVisible.status,
            report.memory.status,
            report.resilience.status,
        ]
        try require(statuses.allSatisfy { $0 == .measured }, "completion requires every metric to be measured")
        try require(report.model.finalStateValid, "model final state is invalid")
        try require(report.model.publicationCount == 2, "model publication count must be two")
        try require(report.renderer.missedFrameCount == 0, "renderer frame budget breached")
        try require(report.compositor.missedFrameCount == 0, "compositor frame budget breached")
        try require(report.combinedFrame.missedFrameCount == 0, "combined frame budget breached")
        try require(report.renderer.p95Milliseconds + report.compositor.p95Milliseconds <= 16.7, "render/compositor frame budget breached")
        try require(report.combinedFrame.p95Milliseconds <= 16.7, "combined frame budget breached")
        try require(report.responsiveness.stallCount == 0, "main-thread stall budget breached")
        try require(report.responsiveness.maximumMainThreadStallMilliseconds <= 100, "main-thread stall budget breached")
        try require(report.inputToVisible.missedSampleCount == 0, "input sample budget breached")
        try require(report.inputToVisible.p95Milliseconds <= 100, "input-to-visible budget breached")
        try require(abs(report.memory.finalWindowDeltaBytes) <= 50 * 1024 * 1024, "memory byte budget breached")
        try require(report.memory.finalWindowDeltaPercent <= 10, "memory percentage budget breached")
        try require(report.resilience.disposition == .acceptedNoRegression, "resilience disposition is not accepted")
        try require(report.resilience.cases.allSatisfy { $0.status == .measured && !$0.leakedResource && !$0.unexpectedGrowth }, "resilience evidence is incomplete")
        try require(report.disposition == .acceptedNoRegression, "report disposition is not accepted")
        try require(report.runProvenance.configuration.isCanonical, "completion requires a canonical fixture configuration")
        try require(report.identity.buildConfiguration == "release", "completion requires a Release build")
        try require(report.buildProvenance.buildConfiguration == "release", "completion requires Release build provenance")
        guard let acceptedFoundation = report.buildProvenance.acceptedFoundationArtifactSHA256 else {
            throw PerformanceValidationError.invalid("completion requires accepted foundation provenance")
        }
        try require(isHex(acceptedFoundation, count: 64), "accepted foundation artifact must be lowercase 64-hex")
        try require(report.runProvenance.acceptedFoundationArtifactSHA256 == acceptedFoundation, "run/foundation artifact mismatch")
        try require(memoryPostWarmupSlope(report.memory) <= memorySlopeNoiseToleranceBytesPerSecond, "post-warmup memory slope exceeds measurement noise")
    }

    static func validateRunProvenance(_ run: PerformanceRunProvenance) throws {
        try validateBuild(run.build)
        try validateRun(run)
        try validateConfiguration(run.configuration)
    }

    private static func validateIdentity(_ identity: MeasurementIdentity, against build: BuildProvenance) throws {
        let hasCommit = identity.sourceCommitSHA != nil
        let hasManifest = identity.contentManifestSHA256 != nil
        try require(hasCommit != hasManifest, "exactly one source identity is required")
        if let commit = identity.sourceCommitSHA {
            try require(isHex(commit, count: 40), "sourceCommitSHA must be lowercase 40-hex")
            try require(build.sourceTreeStatus == .clean, "clean source trees require sourceCommitSHA")
            try require(build.sourceIdentity == SourceIdentity(kind: .sourceCommitSHA, value: commit), "build/source identity mismatch")
        }
        if let manifest = identity.contentManifestSHA256 {
            try require(isHex(manifest, count: 64), "contentManifestSHA256 must be lowercase 64-hex")
            try require(build.sourceTreeStatus == .dirty, "dirty source trees require contentManifestSHA256")
            try require(build.sourceIdentity == SourceIdentity(kind: .contentManifestSHA256, value: manifest), "build/source identity mismatch")
            try require(build.sourceManifestSHA256 == manifest, "content manifest identity does not match build manifest")
        }
        try require(!identity.hostModel.isEmpty, "hostModel is required")
        try require(!identity.macOSVersion.isEmpty, "macOSVersion is required")
        try require(!identity.xcodeVersion.isEmpty, "xcodeVersion is required")
        try require(!identity.developerDirectory.isEmpty, "developerDirectory is required")
        try require(!identity.powerState.isEmpty, "powerState is required")
        try require(!identity.displayState.isEmpty, "displayState is required")
        try require(!identity.buildConfiguration.isEmpty, "buildConfiguration is required")
    }

    private static func validateBuild(_ build: BuildProvenance) throws {
        try require(isHex(build.sourceManifestSHA256, count: 64), "sourceManifestSHA256 must be lowercase 64-hex")
        try require(isHex(build.executableSHA256, count: 64), "executableSHA256 must be lowercase 64-hex")
        try require(isHex(build.bundleManifestSHA256, count: 64), "bundleManifestSHA256 must be lowercase 64-hex")
        try require(!build.buildConfiguration.isEmpty, "buildConfiguration is required")
        try validateFoundation(build.foundation)
        try require(!build.harnessVersion.isEmpty, "build harnessVersion is required")
        try require(!build.buildContractVersion.isEmpty, "buildContractVersion is required")
        try validateUTC(build.recordedAtUTC)
        if let accepted = build.acceptedFoundationArtifactSHA256 {
            try require(isHex(accepted, count: 64), "accepted foundation artifact must be lowercase 64-hex")
        }
    }

    private static func validateRun(_ run: PerformanceRunProvenance) throws {
        try require(!run.variant.isEmpty, "run variant is required")
        try require(!run.outputRoot.isEmpty, "run outputRoot is required")
        try require(!run.sourceRef.isEmpty, "run sourceRef is required")
        try require(!run.foundationProvenancePath.isEmpty, "run foundation provenance path is required")
        try validateUTC(run.recordedAtUTC)
        try validateHost(run.host)
        try validateFoundation(run.foundation)
        try require(!run.harnessVersion.isEmpty, "run harnessVersion is required")
        try require(!run.buildContractVersion.isEmpty, "run buildContractVersion is required")
        if run.build.sourceIdentity.kind == .contentManifestSHA256 {
            try require(
                run.sourceRef == run.build.sourceIdentity.value || isHex(run.sourceRef, count: 40),
                "content run sourceRef must be its manifest or canonical source commit"
            )
        } else {
            try require(run.sourceRef == run.build.sourceIdentity.value, "run/source identity mismatch")
        }
        if let accepted = run.acceptedFoundationArtifactSHA256 {
            try require(isHex(accepted, count: 64), "run accepted foundation artifact must be lowercase 64-hex")
        }
        try require(run.acceptedFoundationArtifactSHA256 == run.build.acceptedFoundationArtifactSHA256, "run/build foundation artifact mismatch")
    }

    private static func validateFoundation(_ foundation: FoundationIdentity) throws {
        try require(!foundation.identity.isEmpty, "foundation identity is required")
        try require(!foundation.version.isEmpty, "foundation version is required")
    }

    private static func validateHost(_ host: HostIdentity) throws {
        try require(!host.machineIdentifier.isEmpty, "machineIdentifier is required")
        try require(!host.processArchitecture.isEmpty, "processArchitecture is required")
        try require(!host.connectedDisplayUUIDs.isEmpty, "at least one connected display is required")
        try require(host.connectedDisplayUUIDs.allSatisfy { !$0.isEmpty }, "display UUID is required")
    }

    private static func validateFixture(_ fixture: FixtureIdentity) throws {
        try require(!fixture.identifier.isEmpty, "fixture identifier is required")
        try require(fixture.identifier == fixture.fixtureProfile.identifier, "fixture identifier does not match profile")
        try require(fixture.fixtureVersion == fixture.fixtureProfile.version, "fixture version does not match profile")
        try require(fixture.markCount == fixture.fixtureProfile.markCount, "fixture mark count does not match profile")
        try require(fixture.markCount > 0, "fixture markCount must be positive")
        try require(fixture.continuationSamples > 0, "fixture continuationSamples must be positive")
        try require(fixture.warmupCount >= 0, "fixture warmupCount must be nonnegative")
        try require(fixture.trialCount > 0, "fixture trialCount must be positive")
    }

    private static func validateConfiguration(_ configuration: PerformanceConfiguration) throws {
        try require(configuration.isCanonical, "configuration must be a canonical fixture profile")
        try require(configuration.fixtureMarkCount == configuration.fixtureProfile.markCount, "configuration mark count does not match profile")
        try require(configuration.fixtureVersion == configuration.fixtureProfile.version, "configuration version does not match profile")
        try require(configuration.fixtureMarkCount > 0, "configuration fixtureMarkCount must be positive")
        try require(configuration.samplesPerGesture > 0, "configuration samplesPerGesture must be positive")
        try require(configuration.warmupCount >= 0, "configuration warmupCount must be nonnegative")
        try require(configuration.trialCount > 0, "configuration trialCount must be positive")
        try require(configuration.pairsPerOrder > 0, "configuration pairsPerOrder must be positive")
        try require(configuration.bootstrapResamples > 0, "configuration bootstrapResamples must be positive")
        try require(configuration.memoryWindowSeconds == 600, "configuration memory window must be 600 seconds")
        try require(configuration.memorySampleIntervalSeconds == 5, "configuration memory sample interval must be 5 seconds")
        try require(!configuration.harnessVersion.isEmpty, "configuration harnessVersion is required")
        try validateFoundation(configuration.foundationIdentity)
        try require(!configuration.buildContractVersion.isEmpty, "configuration buildContractVersion is required")
    }

    private static func validateModel(_ model: ModelMeasurement) throws {
        try require(model.publicationCount >= 0, "publicationCount must be nonnegative")
        if model.status == .measured {
            try require(!model.trialNanoseconds.isEmpty, "measured model requires trial samples")
        }
        try require(model.trialNanoseconds.allSatisfy { $0.isFinite && $0 > 0 }, "trial nanoseconds must be finite and positive")
        if !model.trialNanoseconds.isEmpty {
            try require(model.medianNanoseconds.isFinite && model.medianNanoseconds > 0, "median nanoseconds must be finite and positive")
            try require(model.p95Nanoseconds.isFinite && model.p95Nanoseconds > 0, "p95 nanoseconds must be finite and positive")
            try require(model.madNanoseconds.isFinite && model.madNanoseconds >= 0, "MAD nanoseconds must be finite and nonnegative")
            try require(model.medianNanoseconds == median(model.trialNanoseconds), "median nanoseconds do not match samples")
            try require(model.p95Nanoseconds == nearestRankP95(model.trialNanoseconds), "p95 nanoseconds do not match samples")
            try require(model.madNanoseconds == mad(model.trialNanoseconds), "MAD nanoseconds do not match samples")
        } else {
            try require(model.medianNanoseconds.isFinite && model.medianNanoseconds >= 0, "median nanoseconds must be finite")
            try require(model.p95Nanoseconds.isFinite && model.p95Nanoseconds >= 0, "p95 nanoseconds must be finite")
            try require(model.madNanoseconds.isFinite && model.madNanoseconds >= 0, "MAD nanoseconds must be finite")
        }
        try require(!model.modelChecksum.isEmpty, "model checksum is required")
    }

    private static func validateFrame(_ frame: FrameMeasurement) throws {
        if frame.status == .measured {
            try require(frame.sampleCount > 0, "measured frame requires samples")
            try require(frame.frameCount > 0, "measured frame requires frames")
            try require(frame.p95Milliseconds > 0, "measured frame p95 must be positive")
            try require(frame.frameMilliseconds.count == frame.sampleCount, "frame raw samples must match sampleCount")
            try require(frame.frameMilliseconds.allSatisfy { $0.isFinite && $0 > 0 }, "frame raw samples must be finite and positive")
            try require(frame.p95Milliseconds == nearestRankP95(frame.frameMilliseconds), "frame p95 does not match raw samples")
            let expectedMissedFrameCount = frame.frameMilliseconds.filter { $0 > 16.7 }.count
            try require(frame.missedFrameCount == expectedMissedFrameCount, "missedFrameCount does not match raw frame samples")
        } else {
            try require(frame.frameMilliseconds.isEmpty, "diagnostic frame raw samples must be empty")
        }
        try require(frame.sampleCount >= 0, "frame sampleCount must be nonnegative")
        try require(frame.frameCount >= 0, "frameCount must be nonnegative")
        try require(frame.missedFrameCount >= 0 && frame.missedFrameCount <= frame.frameCount, "missedFrameCount is incoherent")
        try require(frame.p95Milliseconds.isFinite && frame.p95Milliseconds >= 0, "frame p95 must be finite and nonnegative")
        try require(!frame.instrumentationStatus.isEmpty, "instrumentationStatus is required")
    }

    private static func validateLaunch(_ launch: LaunchMeasurement) throws {
        if launch.status == .measured {
            try require(!launch.coldMilliseconds.isEmpty, "measured launch requires cold samples")
            try require(!launch.warmMilliseconds.isEmpty, "measured launch requires warm samples")
        }
        try require(launch.coldMilliseconds.allSatisfy { $0.isFinite && $0 >= 0 }, "cold launch values must be finite and nonnegative")
        try require(launch.warmMilliseconds.allSatisfy { $0.isFinite && $0 >= 0 }, "warm launch values must be finite and nonnegative")
    }

    private static func validateAllocations(_ allocation: AllocationMeasurement) throws {
        if allocation.status == .measured {
            try require(!allocation.bytesPerGesture.isEmpty, "measured allocations require samples")
        }
        try require(allocation.bytesPerGesture.allSatisfy { $0 >= 0 }, "allocation values must be nonnegative")
        try require(allocation.peakAllocationBytes >= 0, "peak allocation must be nonnegative")
        if let maximum = allocation.bytesPerGesture.max() {
            try require(allocation.peakAllocationBytes >= maximum, "peak allocation is below a sample")
        }
    }

    private static func validateRedrawLayout(_ redraw: RedrawLayoutMeasurement) throws {
        if redraw.status == .measured {
            try require(!redraw.redrawsPerSample.isEmpty, "measured redraw/layout requires samples")
            try require(redraw.sampleMilliseconds.count == redraw.redrawsPerSample.count, "redraw raw samples must match redraw counts")
            try require(redraw.sampleMilliseconds.allSatisfy { $0.isFinite && $0 > 0 }, "redraw raw samples must be finite and positive")
            try require(redraw.p95Milliseconds == nearestRankP95(redraw.sampleMilliseconds), "redraw p95 does not match raw samples")
        } else {
            try require(redraw.sampleMilliseconds.isEmpty, "diagnostic redraw raw samples must be empty")
        }
        try require(redraw.redrawsPerSample.allSatisfy { $0 >= 0 }, "redraw counts must be nonnegative")
        try require(redraw.layoutPasses.allSatisfy { $0 >= 0 }, "layout counts must be nonnegative")
        try require(redraw.redrawsPerSample.count == redraw.layoutPasses.count, "redraw/layout arrays must align")
        try require(redraw.p95Milliseconds.isFinite && redraw.p95Milliseconds >= 0, "redraw p95 must be finite and nonnegative")
    }

    private static func validateResponsiveness(_ responsiveness: ResponsivenessMeasurement) throws {
        if responsiveness.status == .measured {
            try require(!responsiveness.responseMilliseconds.isEmpty, "measured responsiveness requires samples")
            try require(responsiveness.responseMilliseconds.allSatisfy { $0.isFinite && $0 > 0 }, "response raw samples must be finite and positive")
            try require(responsiveness.p95ResponseMilliseconds == nearestRankP95(responsiveness.responseMilliseconds), "response p95 does not match raw samples")
            try require(responsiveness.maximumMainThreadStallMilliseconds >= responsiveness.responseMilliseconds.max()!, "maximum stall is below a response sample")
            try require(responsiveness.stallCount <= responsiveness.responseMilliseconds.count, "stallCount exceeds response samples")
        } else {
            try require(responsiveness.responseMilliseconds.isEmpty, "diagnostic response raw samples must be empty")
        }
        try require(responsiveness.stallCount >= 0, "stallCount must be nonnegative")
        try require(responsiveness.maximumMainThreadStallMilliseconds.isFinite && responsiveness.maximumMainThreadStallMilliseconds >= 0, "maximum stall must be finite and nonnegative")
        try require(responsiveness.p95ResponseMilliseconds.isFinite && responsiveness.p95ResponseMilliseconds >= 0, "response p95 must be finite and nonnegative")
    }

    private static func validateInputToVisible(_ input: InputToVisibleMeasurement) throws {
        if input.status == .measured {
            try require(input.sampleCount > 0, "measured input requires samples")
            try require(input.p95Milliseconds > 0, "measured input p95 must be positive")
            try require(input.sampleMilliseconds.count == input.sampleCount, "input raw samples must match sampleCount")
            try require(input.sampleMilliseconds.allSatisfy { $0.isFinite && $0 > 0 }, "input raw samples must be finite and positive")
            try require(input.p95Milliseconds == nearestRankP95(input.sampleMilliseconds), "input p95 does not match raw samples")
        } else {
            try require(input.sampleMilliseconds.isEmpty, "diagnostic input raw samples must be empty")
        }
        try require(input.sampleCount >= 0, "input sampleCount must be nonnegative")
        try require(input.missedSampleCount >= 0 && input.missedSampleCount <= input.sampleCount, "missedSampleCount is incoherent")
        try require(input.p95Milliseconds.isFinite && input.p95Milliseconds >= 0, "input p95 must be finite and nonnegative")
    }

    private static func validateMemory(_ memory: MemoryMeasurement, warmupCount: Int, trialCount: Int) throws {
        try require(memory.windowSeconds == PerformanceConfiguration.standard.memoryWindowSeconds, "memory window must be 600 seconds")
        try require(memory.sampleIntervalSeconds == PerformanceConfiguration.standard.memorySampleIntervalSeconds, "memory sample interval must be 5 seconds")
        try require(memory.postWarmupSlopeBytesPerSecond.isFinite, "memory slope must be finite")
        try require(memory.peakRSSBytes >= 0, "peak RSS must be nonnegative")
        try require(memory.finalWindowDeltaPercent.isFinite, "memory delta percent must be finite")
        try require(memory.matchedBaselineSeries.allSatisfy { $0.isFinite && $0 >= 0 }, "matched baseline series must be finite and nonnegative")
        try require(memory.matchedBaselineValues.allSatisfy { $0 >= 0 }, "matched baseline values must be nonnegative")
        try require(memory.matchedBaselineSeries.count == memory.matchedBaselineValues.count, "matched baseline arrays must align")
        try validateResources(memory.peakLiveResourceCounts)
        try validateResources(memory.endLiveResourceCounts)
        try require(memory.peakLiveResourceCounts.overlays >= memory.endLiveResourceCounts.overlays, "peak/end overlay counts are incoherent")
        try require(memory.peakLiveResourceCounts.timers >= memory.endLiveResourceCounts.timers, "peak/end timer counts are incoherent")
        try require(memory.peakLiveResourceCounts.handlers >= memory.endLiveResourceCounts.handlers, "peak/end handler counts are incoherent")
        try require(memory.peakLiveResourceCounts.windows >= memory.endLiveResourceCounts.windows, "peak/end window counts are incoherent")
        try require(memory.peakLiveResourceCounts.observers >= memory.endLiveResourceCounts.observers, "peak/end observer counts are incoherent")

        if memory.samples.isEmpty {
            try require(memory.status != .measured, "measured memory requires samples")
            return
        }

        var previousElapsed = -Double.infinity
        var previousRank = 0
        var runningSampleCount = 0
        var runningRSSValues: [Int64] = []
        var observedPhases = Set<MemoryPhase>()
        for sample in memory.samples {
            try require(sample.elapsedSeconds.isFinite && sample.elapsedSeconds >= 0, "memory elapsed time must be finite and nonnegative")
            try require(sample.elapsedSeconds >= previousElapsed, "memory elapsed times must be ordered")
            try require(sample.rssBytes >= 0, "RSS must be nonnegative")
            try validateResources(sample.resources)
            let rank = phaseRank(sample.phase)
            try require(rank >= previousRank, "memory phases must be ordered")
            if sample.phase == .running {
                try require(sample.elapsedSeconds <= Double(memory.windowSeconds), "running memory samples exceed the window")
                runningSampleCount += 1
                runningRSSValues.append(sample.rssBytes)
            }
            observedPhases.insert(sample.phase)
            previousElapsed = sample.elapsedSeconds
            previousRank = rank
        }
        let runningSamples = memory.samples.filter { $0.phase == .running }
        let isScalarSeries = memory.status == .measured
            && memory.samples.count == trialCount
            && runningSamples.count == trialCount
            && memory.aggregates.isEmpty
            && memory.matchedBaselineSeries.isEmpty
            && memory.matchedBaselineValues.isEmpty
            && memory.samples.allSatisfy { $0.phase == .running }
        if isScalarSeries {
            let maximumRSS = memory.samples.map(\.rssBytes).max()!
            try require(memory.peakRSSBytes == maximumRSS, "peak RSS does not match sampled maximum")
            try require(memory.peakLiveResourceCounts == maximumResources(in: memory.samples), "peak live resources do not match sampled maximum")
            try require(memory.endLiveResourceCounts == memory.samples.last!.resources, "end live resources do not match final sample")
            for (index, sample) in runningSamples.enumerated() {
                try require(sample.elapsedSeconds == Double(index * memory.sampleIntervalSeconds), "scalar memory cadence has a gap")
            }
            let expectedSlope = leastSquaresSlope(for: runningSamples, warmupCount: warmupCount)
            try require(abs(memory.postWarmupSlopeBytesPerSecond - expectedSlope) <= memorySlopeNoiseToleranceBytesPerSecond, "scalar memory slope does not match samples")
            return
        }
        if memory.status == .measured {
            let expectedRunningSampleCount = memory.windowSeconds / memory.sampleIntervalSeconds + 1
            try require(runningSampleCount == expectedRunningSampleCount, "memory running cadence is incomplete")
            try require(runningSamples.count == expectedRunningSampleCount, "memory requires the full running window")
            for (index, sample) in runningSamples.enumerated() {
                try require(sample.elapsedSeconds == Double(index * memory.sampleIntervalSeconds), "memory running cadence has a gap")
            }
            let checkpoints = Array(memory.samples.dropFirst(expectedRunningSampleCount))
            try require(checkpoints.map(\.phase) == [.stopping, .stopped, .restarted], "memory lifecycle checkpoints are incomplete")
            for (index, checkpoint) in checkpoints.enumerated() {
                try require(checkpoint.elapsedSeconds == Double(memory.windowSeconds + (index + 1) * memory.sampleIntervalSeconds), "memory checkpoint cadence has a gap")
            }
            try require(checkpoints[1].resources == emptyResources, "stopped checkpoint must release all resources")
            let runningMaximum = maximumResources(in: runningSamples)
            try require(checkpoints[0].resources == emptyResources, "stopping checkpoint must release all resources")
            try require(checkpoints[2].resources == runningSamples.first!.resources, "restarted resources did not return to the running baseline")
            try require(resourcesAreAtMost(checkpoints[2].resources, runningMaximum), "restarted resources exceed running bounds")
        }
        let maximumRSS = memory.samples.map(\.rssBytes).max()!
        try require(memory.peakRSSBytes == maximumRSS, "peak RSS does not match sampled maximum")
        try require(memory.peakLiveResourceCounts == maximumResources(in: memory.samples), "peak live resources do not match sampled maximum")
        try require(memory.endLiveResourceCounts == memory.samples.last!.resources, "end live resources do not match final sample")

        let hasCompleteBaseline = !runningSamples.isEmpty
            && memory.matchedBaselineSeries.count == runningSamples.count
            && memory.matchedBaselineValues.count == runningSamples.count
        if hasCompleteBaseline {
            try require(memory.matchedBaselineSeries == runningSamples.map(\.elapsedSeconds), "matched baseline series does not align with running samples")
            let matchedFinal = memory.matchedBaselineValues.last!
            try require(matchedFinal > 0, "matched baseline final RSS must be positive")
            let candidateFinal = runningSamples.last!.rssBytes
            let expectedDelta = candidateFinal - matchedFinal
            let expectedPercent = Double(expectedDelta) / Double(matchedFinal) * 100
            let percentTolerance = max(1e-12, abs(expectedPercent) * 1e-12)
            try require(memory.finalWindowDeltaBytes == expectedDelta, "memory final-window byte delta does not match samples")
            try require(abs(memory.finalWindowDeltaPercent - expectedPercent) <= percentTolerance, "memory final-window percentage does not match samples")
        }

        if memory.status == .measured {
            let expectedSlope = leastSquaresSlope(for: runningSamples, warmupCount: warmupCount)
            try require(abs(memory.postWarmupSlopeBytesPerSecond - expectedSlope) <= memorySlopeNoiseToleranceBytesPerSecond, "memory slope does not match running samples")
        }

        var expectedInterval = 0
        var aggregateSampleTotal = 0
        var aggregateOffset = 0
        for aggregate in memory.aggregates {
            try require(aggregate.intervalIndex == expectedInterval, "memory aggregate intervals must be contiguous")
            try require(aggregate.sampleCount > 0, "memory aggregate sampleCount must be positive")
            try require(aggregate.meanRSSBytes >= 0 && aggregate.peakRSSBytes >= 0, "memory aggregates must be nonnegative")
            try require(aggregate.meanRSSBytes <= aggregate.peakRSSBytes, "memory aggregate mean exceeds peak")
            if aggregateOffset + aggregate.sampleCount <= runningRSSValues.count {
                let values = runningRSSValues[aggregateOffset..<(aggregateOffset + aggregate.sampleCount)]
                let expectedMean = Int64((values.reduce(0.0) { $0 + Double($1) } / Double(aggregate.sampleCount)).rounded())
                let expectedPeak = values.max()!
                try require(aggregate.meanRSSBytes == expectedMean, "memory aggregate mean does not match samples")
                try require(aggregate.peakRSSBytes == expectedPeak, "memory aggregate peak does not match samples")
            }
            aggregateSampleTotal += aggregate.sampleCount
            aggregateOffset += aggregate.sampleCount
            expectedInterval += 1
        }
        if memory.status == .measured {
            try require(!memory.aggregates.isEmpty, "measured memory requires aggregates")
            try require(aggregateSampleTotal == runningSampleCount, "memory aggregates do not cover running samples")
            try require(!memory.matchedBaselineSeries.isEmpty, "measured memory requires matched baseline series")
            try require(memory.matchedBaselineSeries.count == runningSampleCount, "measured memory baseline series is incomplete")
            try require(memory.matchedBaselineValues.count == runningSampleCount, "measured memory baseline values are incomplete")
        }
    }

    private static func validateResilience(_ resilience: ResilienceMeasurement) throws {
        if resilience.status == .measured {
            try require(!resilience.cases.isEmpty, "measured resilience requires cases")
        }
        for testCase in resilience.cases {
            try require(!testCase.identifier.isEmpty, "resilience case identifier is required")
            try require(testCase.iterationCount > 0, "resilience iterationCount must be positive")
            try validateResources(testCase.peakResourceCounts)
            try validateResources(testCase.endResourceCounts)
            try require(testCase.peakResourceCounts.overlays >= testCase.endResourceCounts.overlays, "resilience overlay counts are incoherent")
            try require(testCase.peakResourceCounts.timers >= testCase.endResourceCounts.timers, "resilience timer counts are incoherent")
            try require(testCase.peakResourceCounts.handlers >= testCase.endResourceCounts.handlers, "resilience handler counts are incoherent")
            try require(testCase.peakResourceCounts.windows >= testCase.endResourceCounts.windows, "resilience window counts are incoherent")
            try require(testCase.peakResourceCounts.observers >= testCase.endResourceCounts.observers, "resilience observer counts are incoherent")
        }
    }

    private static func validateMeasuredCounts(_ report: PerformanceMeasurementReport) throws {
        let configuration = report.runProvenance.configuration
        if report.model.status == .measured {
            try require(report.model.trialNanoseconds.count == configuration.trialCount, "model trial count does not match configuration")
        }
        let frames = [report.renderer, report.compositor, report.combinedFrame]
        for frame in frames where frame.status == .measured {
            try require(frame.sampleCount == configuration.trialCount, "frame sample count does not match configuration")
            try require(frame.frameMilliseconds.count == configuration.trialCount, "frame raw sample count does not match configuration")
            try require(frame.frameCount == configuration.trialCount, "frame count does not match configuration")
        }
        let measuredFrames = frames.filter { $0.status == .measured }
        if measuredFrames.count > 1 {
            try require(measuredFrames.dropFirst().allSatisfy { $0.sampleCount == measuredFrames[0].sampleCount }, "frame sample counts are not aligned")
        }
        if report.launch.status == .measured {
            try require(report.launch.coldMilliseconds.count == configuration.trialCount, "cold launch count does not match configuration")
            try require(report.launch.warmMilliseconds.count == configuration.trialCount, "warm launch count does not match configuration")
        }
        if report.allocations.status == .measured {
            try require(report.allocations.bytesPerGesture.count == configuration.trialCount, "allocation sample count does not match configuration")
        }
        if report.redrawLayout.status == .measured {
            try require(report.redrawLayout.sampleMilliseconds.count == configuration.trialCount, "redraw raw sample count does not match configuration")
            try require(report.redrawLayout.redrawsPerSample.count == configuration.trialCount, "redraw sample count does not match configuration")
            try require(report.redrawLayout.layoutPasses.count == configuration.trialCount, "layout sample count does not match configuration")
        }
        if report.inputToVisible.status == .measured {
            try require(report.inputToVisible.sampleCount == configuration.trialCount, "input sample count does not match configuration")
            try require(report.inputToVisible.sampleMilliseconds.count == configuration.trialCount, "input raw sample count does not match configuration")
        }
        if report.responsiveness.status == .measured {
            try require(report.responsiveness.responseMilliseconds.count == configuration.trialCount, "response raw sample count does not match configuration")
        }
    }

    private static func validateResources(_ resources: ResourceCounts) throws {
        try require(resources.overlays >= 0, "overlay count must be nonnegative")
        try require(resources.timers >= 0, "timer count must be nonnegative")
        try require(resources.handlers >= 0, "handler count must be nonnegative")
        try require(resources.windows >= 0, "window count must be nonnegative")
        try require(resources.observers >= 0, "observer count must be nonnegative")
    }

    private static func maximumResources(in samples: [MemorySample]) -> ResourceCounts {
        samples.reduce(ResourceCounts(overlays: 0, timers: 0, handlers: 0, windows: 0, observers: 0)) { current, sample in
            ResourceCounts(
                overlays: max(current.overlays, sample.resources.overlays),
                timers: max(current.timers, sample.resources.timers),
                handlers: max(current.handlers, sample.resources.handlers),
                windows: max(current.windows, sample.resources.windows),
                observers: max(current.observers, sample.resources.observers)
            )
        }
    }

    private static func resourcesAreAtMost(_ resources: ResourceCounts, _ maximum: ResourceCounts) -> Bool {
        resources.overlays <= maximum.overlays
            && resources.timers <= maximum.timers
            && resources.handlers <= maximum.handlers
            && resources.windows <= maximum.windows
            && resources.observers <= maximum.observers
    }

    private static func memoryPostWarmupSlope(_ memory: MemoryMeasurement) -> Double {
        let running = memory.samples.filter { $0.phase == .running }
        guard running.count > PerformanceConfiguration.standard.warmupCount,
              let first = running.dropFirst(PerformanceConfiguration.standard.warmupCount).first,
              let last = running.last,
              last.elapsedSeconds > first.elapsedSeconds
        else {
            return .infinity
        }
        return leastSquaresSlope(for: running, warmupCount: PerformanceConfiguration.standard.warmupCount)
    }

    private static func leastSquaresSlope(for running: [MemorySample], warmupCount: Int) -> Double {
        let postWarmup = Array(running.dropFirst(warmupCount))
        guard postWarmup.count >= 2 else { return .infinity }
        let meanElapsed = postWarmup.map(\.elapsedSeconds).reduce(0, +) / Double(postWarmup.count)
        let meanRSS = postWarmup.map { Double($0.rssBytes) }.reduce(0, +) / Double(postWarmup.count)
        let numerator = postWarmup.reduce(0.0) { total, sample in
            total + (sample.elapsedSeconds - meanElapsed) * (Double(sample.rssBytes) - meanRSS)
        }
        let denominator = postWarmup.reduce(0.0) { total, sample in
            total + pow(sample.elapsedSeconds - meanElapsed, 2)
        }
        return numerator / denominator
    }

    private static func phaseRank(_ phase: MemoryPhase) -> Int {
        switch phase {
        case .running: return 0
        case .stopping: return 1
        case .stopped: return 2
        case .restarted: return 3
        }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func nearestRankP95(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(0.95 * Double(sorted.count))))
        return sorted[rank - 1]
    }

    private static func mad(_ values: [Double]) -> Double {
        let center = median(values)
        return median(values.map { abs($0 - center) })
    }

    private static func isHex(_ value: String, count: Int) -> Bool {
        value.count == count && value.unicodeScalars.allSatisfy { hexCharacters.contains($0) }
    }

    private static func validateUTC(_ value: String) throws {
        try require(!value.isEmpty, "UTC timestamp is required")
        try require(value.hasSuffix("Z"), "timestamp must be UTC")
        let formatter = ISO8601DateFormatter()
        try require(formatter.date(from: value) != nil, "timestamp must be ISO-8601")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw PerformanceValidationError.invalid(message)
        }
    }
}
