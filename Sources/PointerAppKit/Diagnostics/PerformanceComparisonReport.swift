import Foundation

public enum PerformanceMetricUnit: String, Codable, Sendable, Equatable {
    case nanoseconds
    case milliseconds
    case bytes
}

extension PerformanceMetricID {
    var canonicalUnit: PerformanceMetricUnit {
        switch self {
        case .model: return .nanoseconds
        case .renderer, .compositor, .combinedFrame, .launchCold, .launchWarm, .responsiveness, .inputToVisible: return .milliseconds
        case .allocations, .memoryRSS: return .bytes
        case .redrawLayout: return .milliseconds
        }
    }

    var canonicalBudgetLimit: Double? {
        switch self {
        case .combinedFrame: return 16.7
        case .responsiveness, .inputToVisible: return 100
        case .model, .renderer, .compositor, .launchCold, .launchWarm, .allocations, .redrawLayout, .memoryRSS: return nil
        }
    }
}

public struct ManualMetricEvidence: Codable, Sendable, Equatable {
    public let metricID: PerformanceMetricID
    public let evidenceClass: MetricEvidenceClass
    public let host: String
    public let recordedAt: String
    public let permissions: [String]
    public let steps: String
    public let samples: [Double]
    public let result: String
    public let evidencePath: String

    public init(
        metricID: PerformanceMetricID,
        evidenceClass: MetricEvidenceClass,
        host: String,
        recordedAt: String,
        permissions: [String],
        steps: String,
        samples: [Double],
        result: String,
        evidencePath: String
    ) {
        self.metricID = metricID
        self.evidenceClass = evidenceClass
        self.host = host
        self.recordedAt = recordedAt
        self.permissions = permissions
        self.steps = steps
        self.samples = samples
        self.result = result
        self.evidencePath = evidencePath
    }
}

public struct ManualMetricAdapter: Codable, Sendable, Equatable {
    public let evidence: ManualMetricEvidence

    public init(evidence: ManualMetricEvidence) {
        self.evidence = evidence
    }
}

public struct MetricComparison: Codable, Sendable, Equatable {
    public let metricID: PerformanceMetricID
    public let evidenceClass: MetricEvidenceClass
    public let unit: PerformanceMetricUnit
    public let baselineID: String
    public let candidateID: String
    public let baselineSamples: [Double]
    public let candidateSamples: [Double]
    public let ratios: [Double]
    public let deltas: [Double]
    public let budgetLimit: Double?
    public let bootstrapInterval: BootstrapInterval
    public let manualEvidence: ManualMetricEvidence?
    public let disposition: Disposition

    public init(
        metricID: PerformanceMetricID,
        evidenceClass: MetricEvidenceClass,
        unit: PerformanceMetricUnit,
        baselineID: String,
        candidateID: String,
        baselineSamples: [Double],
        candidateSamples: [Double],
        ratios: [Double],
        deltas: [Double],
        budgetLimit: Double?,
        bootstrapInterval: BootstrapInterval,
        manualEvidence: ManualMetricEvidence?,
        disposition: Disposition
    ) {
        self.metricID = metricID
        self.evidenceClass = evidenceClass
        self.unit = unit
        self.baselineID = baselineID
        self.candidateID = candidateID
        self.baselineSamples = baselineSamples
        self.candidateSamples = candidateSamples
        self.ratios = ratios
        self.deltas = deltas
        self.budgetLimit = budgetLimit
        self.bootstrapInterval = bootstrapInterval
        self.manualEvidence = manualEvidence
        self.disposition = disposition
    }
}

public struct PerformanceComparisonDraft: Sendable, Equatable {
    public let harnessVersion: String
    public let foundationIdentity: FoundationIdentity
    public let buildContractVersion: String
    public let baselineBuildProvenance: BuildProvenance
    public let candidateBuildProvenance: BuildProvenance
    public let baselineRunProvenance: PerformanceRunProvenance
    public let candidateRunProvenance: PerformanceRunProvenance
    public let pairEligibility: PerformancePairEligibility
    public let baselineFixture: FixtureIdentity
    public let candidateFixture: FixtureIdentity
    public let baselineMeasurementIdentity: MeasurementIdentity
    public let candidateMeasurementIdentity: MeasurementIdentity
    public let baselineID: String
    public let candidateID: String
    public let metrics: [MetricComparison]
    public let resilience: ResilienceMeasurement
    public let seed: UInt64
    public let resampleCount: Int
    public let disposition: Disposition

    internal init(
        harnessVersion: String,
        foundationIdentity: FoundationIdentity,
        buildContractVersion: String,
        baselineBuildProvenance: BuildProvenance,
        candidateBuildProvenance: BuildProvenance,
        baselineRunProvenance: PerformanceRunProvenance,
        candidateRunProvenance: PerformanceRunProvenance,
        pairEligibility: PerformancePairEligibility,
        baselineFixture: FixtureIdentity,
        candidateFixture: FixtureIdentity,
        baselineMeasurementIdentity: MeasurementIdentity,
        candidateMeasurementIdentity: MeasurementIdentity,
        baselineID: String,
        candidateID: String,
        metrics: [MetricComparison],
        resilience: ResilienceMeasurement,
        seed: UInt64,
        resampleCount: Int,
        disposition: Disposition
    ) {
        self.harnessVersion = harnessVersion
        self.foundationIdentity = foundationIdentity
        self.buildContractVersion = buildContractVersion
        self.baselineBuildProvenance = baselineBuildProvenance
        self.candidateBuildProvenance = candidateBuildProvenance
        self.baselineRunProvenance = baselineRunProvenance
        self.candidateRunProvenance = candidateRunProvenance
        self.pairEligibility = pairEligibility
        self.baselineFixture = baselineFixture
        self.candidateFixture = candidateFixture
        self.baselineMeasurementIdentity = baselineMeasurementIdentity
        self.candidateMeasurementIdentity = candidateMeasurementIdentity
        self.baselineID = baselineID
        self.candidateID = candidateID
        self.metrics = metrics
        self.resilience = resilience
        self.seed = seed
        self.resampleCount = resampleCount
        self.disposition = disposition
    }
}

public struct PerformanceComparisonReport: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let reportKind: PerformanceReportKind
    public let schemaVersion: Int
    public let harnessVersion: String
    public let foundationIdentity: FoundationIdentity
    public let buildContractVersion: String
    public let baselineBuildProvenance: BuildProvenance
    public let candidateBuildProvenance: BuildProvenance
    public let baselineRunProvenance: PerformanceRunProvenance
    public let candidateRunProvenance: PerformanceRunProvenance
    public let pairEligibility: PerformancePairEligibility
    public let baselineFixture: FixtureIdentity
    public let candidateFixture: FixtureIdentity
    public let baselineMeasurementIdentity: MeasurementIdentity
    public let candidateMeasurementIdentity: MeasurementIdentity
    public let baselineMeasurementReportSHA256: String
    public let candidateMeasurementReportSHA256: String
    public let baselineID: String
    public let candidateID: String
    public let metrics: [MetricComparison]
    public let resilience: ResilienceMeasurement
    public let seed: UInt64
    public let resampleCount: Int
    public let disposition: Disposition

    internal init(
        reportKind: PerformanceReportKind,
        schemaVersion: Int,
        harnessVersion: String,
        foundationIdentity: FoundationIdentity,
        buildContractVersion: String,
        baselineBuildProvenance: BuildProvenance,
        candidateBuildProvenance: BuildProvenance,
        baselineRunProvenance: PerformanceRunProvenance,
        candidateRunProvenance: PerformanceRunProvenance,
        pairEligibility: PerformancePairEligibility,
        baselineFixture: FixtureIdentity,
        candidateFixture: FixtureIdentity,
        baselineMeasurementIdentity: MeasurementIdentity,
        candidateMeasurementIdentity: MeasurementIdentity,
        baselineMeasurementReportSHA256: String,
        candidateMeasurementReportSHA256: String,
        baselineID: String,
        candidateID: String,
        metrics: [MetricComparison],
        resilience: ResilienceMeasurement,
        seed: UInt64,
        resampleCount: Int,
        disposition: Disposition
    ) {
        self.reportKind = reportKind
        self.schemaVersion = schemaVersion
        self.harnessVersion = harnessVersion
        self.foundationIdentity = foundationIdentity
        self.buildContractVersion = buildContractVersion
        self.baselineBuildProvenance = baselineBuildProvenance
        self.candidateBuildProvenance = candidateBuildProvenance
        self.baselineRunProvenance = baselineRunProvenance
        self.candidateRunProvenance = candidateRunProvenance
        self.pairEligibility = pairEligibility
        self.baselineFixture = baselineFixture
        self.candidateFixture = candidateFixture
        self.baselineMeasurementIdentity = baselineMeasurementIdentity
        self.candidateMeasurementIdentity = candidateMeasurementIdentity
        self.baselineMeasurementReportSHA256 = baselineMeasurementReportSHA256
        self.candidateMeasurementReportSHA256 = candidateMeasurementReportSHA256
        self.baselineID = baselineID
        self.candidateID = candidateID
        self.metrics = metrics
        self.resilience = resilience
        self.seed = seed
        self.resampleCount = resampleCount
        self.disposition = disposition
    }

    internal init(
        draft: PerformanceComparisonDraft,
        baselineMeasurementReportSHA256: String,
        candidateMeasurementReportSHA256: String
    ) {
        self.init(
            reportKind: .comparison,
            schemaVersion: Self.currentSchemaVersion,
            harnessVersion: draft.harnessVersion,
            foundationIdentity: draft.foundationIdentity,
            buildContractVersion: draft.buildContractVersion,
            baselineBuildProvenance: draft.baselineBuildProvenance,
            candidateBuildProvenance: draft.candidateBuildProvenance,
            baselineRunProvenance: draft.baselineRunProvenance,
            candidateRunProvenance: draft.candidateRunProvenance,
            pairEligibility: draft.pairEligibility,
            baselineFixture: draft.baselineFixture,
            candidateFixture: draft.candidateFixture,
            baselineMeasurementIdentity: draft.baselineMeasurementIdentity,
            candidateMeasurementIdentity: draft.candidateMeasurementIdentity,
            baselineMeasurementReportSHA256: baselineMeasurementReportSHA256,
            candidateMeasurementReportSHA256: candidateMeasurementReportSHA256,
            baselineID: draft.baselineID,
            candidateID: draft.candidateID,
            metrics: draft.metrics,
            resilience: draft.resilience,
            seed: draft.seed,
            resampleCount: draft.resampleCount,
            disposition: draft.disposition
        )
    }

    public func validateStructure() throws {
        try PerformanceComparisonReportValidator.validateStructure(self)
    }

    public func validateCompletion() throws {
        try PerformanceComparisonReportValidator.validateCompletion(self)
    }
}

enum PerformanceComparisonReportValidator {
    private static let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")

    static func validateStructure(_ report: PerformanceComparisonReport) throws {
        try require(report.reportKind == .comparison, "reportKind must be comparison")
        try require(report.schemaVersion == PerformanceComparisonReport.currentSchemaVersion, "unsupported comparison schemaVersion")
        try require(!report.harnessVersion.isEmpty, "comparison harnessVersion is required")
        try require(!report.buildContractVersion.isEmpty, "comparison buildContractVersion is required")
        try validateFoundation(report.foundationIdentity)
        try validateBuild(report.baselineBuildProvenance)
        try validateBuild(report.candidateBuildProvenance)
        try validateRun(report.baselineRunProvenance, expectedVariant: "baseline")
        try validateRun(report.candidateRunProvenance, expectedVariant: "candidate")
        try require(report.baselineRunProvenance.build == report.baselineBuildProvenance, "baseline run/build provenance mismatch")
        try require(report.candidateRunProvenance.build == report.candidateBuildProvenance, "candidate run/build provenance mismatch")
        try require(report.baselineRunProvenance.host == report.candidateRunProvenance.host, "baseline/candidate host mismatch")
        try require(report.baselineRunProvenance.configuration == report.candidateRunProvenance.configuration, "baseline/candidate configuration mismatch")
        try require(report.baselineRunProvenance.configuration == PerformanceConfiguration.standard, "comparison requires the standard configuration")
        try validateFixtures(report.baselineFixture, report.candidateFixture, configuration: report.baselineRunProvenance.configuration)
        try require(report.harnessVersion == report.baselineRunProvenance.harnessVersion, "comparison/baseline harness mismatch")
        try require(report.harnessVersion == report.candidateRunProvenance.harnessVersion, "comparison/candidate harness mismatch")
        try require(report.harnessVersion == report.baselineBuildProvenance.harnessVersion, "comparison/baseline build harness mismatch")
        try require(report.harnessVersion == report.candidateBuildProvenance.harnessVersion, "comparison/candidate build harness mismatch")
        try require(report.buildContractVersion == report.baselineRunProvenance.buildContractVersion, "comparison/baseline build contract mismatch")
        try require(report.buildContractVersion == report.candidateRunProvenance.buildContractVersion, "comparison/candidate build contract mismatch")
        try require(report.buildContractVersion == report.baselineBuildProvenance.buildContractVersion, "comparison/baseline build contract mismatch")
        try require(report.buildContractVersion == report.candidateBuildProvenance.buildContractVersion, "comparison/candidate build contract mismatch")
        try require(report.foundationIdentity == report.baselineRunProvenance.foundation, "comparison/baseline foundation mismatch")
        try require(report.foundationIdentity == report.candidateRunProvenance.foundation, "comparison/candidate foundation mismatch")
        try require(report.foundationIdentity == report.baselineBuildProvenance.foundation, "comparison/baseline build foundation mismatch")
        try require(report.foundationIdentity == report.candidateBuildProvenance.foundation, "comparison/candidate build foundation mismatch")
        try require(report.baselineRunProvenance.acceptedFoundationArtifactSHA256 != nil, "baseline accepted foundation artifact is required")
        try require(report.baselineRunProvenance.acceptedFoundationArtifactSHA256 == report.candidateRunProvenance.acceptedFoundationArtifactSHA256, "baseline/candidate foundation artifact mismatch")

        try validateIdentity(report.baselineID, measurement: report.baselineMeasurementIdentity, build: report.baselineBuildProvenance, run: report.baselineRunProvenance)
        try validateIdentity(report.candidateID, measurement: report.candidateMeasurementIdentity, build: report.candidateBuildProvenance, run: report.candidateRunProvenance)
        try validateMeasurementReportHashes(report.baselineMeasurementReportSHA256, report.candidateMeasurementReportSHA256)
        try require(sameMeasurementEnvironment(report.baselineMeasurementIdentity, report.candidateMeasurementIdentity), "baseline/candidate measurement environment mismatch")
        try require(report.baselineID != report.candidateID, "baseline and candidate identities must differ")
        try validateEligibility(report.pairEligibility, baseline: report.baselineRunProvenance, candidate: report.candidateRunProvenance, foundation: report.foundationIdentity, harnessVersion: report.harnessVersion, buildContractVersion: report.buildContractVersion)
        try require(report.seed == report.baselineRunProvenance.configuration.bootstrapSeed, "comparison seed does not match configuration")
        try require(report.resampleCount == report.baselineRunProvenance.configuration.bootstrapResamples, "comparison resample count does not match configuration")
        try validateMetrics(report.metrics, baselineID: report.baselineID, candidateID: report.candidateID, host: report.baselineRunProvenance.host.machineIdentifier, expectedPairCount: report.baselineRunProvenance.configuration.totalPairs, seed: report.seed, resampleCount: report.resampleCount)
        try validateResilience(report.resilience)
    }

    static func validateCompletion(_ report: PerformanceComparisonReport) throws {
        try validateStructure(report)
        try require(report.disposition == .acceptedNoRegression, "comparison disposition is not accepted")
        try require(report.metrics.allSatisfy { $0.disposition == .acceptedNoRegression }, "a metric disposition is not accepted")
        try require(report.resilience.disposition == .acceptedNoRegression, "resilience disposition is not accepted")
        try require(report.resilience.cases.allSatisfy { $0.status == .measured && !$0.leakedResource && !$0.unexpectedGrowth }, "resilience evidence is incomplete")
        guard let renderer = report.metrics.first(where: { $0.metricID == .renderer }),
              let compositor = report.metrics.first(where: { $0.metricID == .compositor })
        else {
            throw PerformanceValidationError.invalid("renderer and compositor comparisons are required")
        }
        try require(nearestRankP95(renderer.candidateSamples) + nearestRankP95(compositor.candidateSamples) <= 16.7, "renderer/compositor frame budget breached")
        for metric in report.metrics {
            try require(median(metric.ratios) <= 1.10, "metric ratio median exceeds the 1.10 budget")
            try require(nearestRankP95(metric.ratios) <= 1.10, "metric ratio p95 exceeds the 1.10 budget")
            if let budgetLimit = metric.budgetLimit {
                try require(nearestRankP95(metric.candidateSamples) <= budgetLimit, "metric candidate p95 exceeds its budget")
            }
        }
    }

    private static func validateIdentity(_ id: String, measurement: MeasurementIdentity, build: BuildProvenance, run: PerformanceRunProvenance) throws {
        try require(isHex(id, count: 40), "comparison identity must be lowercase 40-hex")
        try require(build.sourceTreeStatus == .clean, "authoritative comparisons require clean source trees")
        try require(build.sourceIdentity.kind == .sourceCommitSHA, "authoritative comparisons require commit identities")
        try require(build.sourceIdentity.value == id, "comparison/build identity mismatch")
        try require(run.sourceRef == id, "comparison/run identity mismatch")
        try require(measurement.sourceCommitSHA == id && measurement.contentManifestSHA256 == nil, "measurement identity does not match comparison commit")
        try require(measurement.buildConfiguration == build.buildConfiguration && measurement.buildConfiguration == "release", "measurement build configuration mismatch")
        try require(!measurement.hostModel.isEmpty, "measurement host model is required")
        try require(!measurement.macOSVersion.isEmpty, "measurement macOS version is required")
        try require(!measurement.xcodeVersion.isEmpty, "measurement Xcode version is required")
        try require(!measurement.developerDirectory.isEmpty, "measurement developer directory is required")
        try require(!measurement.powerState.isEmpty, "measurement power state is required")
        try require(!measurement.displayState.isEmpty, "measurement display state is required")
    }

    private static func validateBuild(_ build: BuildProvenance) throws {
        try require(build.sourceTreeStatus == .clean, "comparison builds must be clean")
        try require(build.sourceIdentity.kind == .sourceCommitSHA, "comparison builds require commit source identities")
        try require(isHex(build.sourceIdentity.value, count: 40), "build source identity must be lowercase 40-hex")
        try require(isHex(build.sourceManifestSHA256, count: 64), "comparison source manifest must be lowercase 64-hex")
        try require(isHex(build.executableSHA256, count: 64), "comparison executable hash must be lowercase 64-hex")
        try require(isHex(build.bundleManifestSHA256, count: 64), "comparison bundle manifest must be lowercase 64-hex")
        try require(build.buildConfiguration == "release", "comparison requires Release build provenance")
        try require(!build.harnessVersion.isEmpty, "comparison build harnessVersion is required")
        try require(!build.buildContractVersion.isEmpty, "comparison build contract is required")
        try validateFoundation(build.foundation)
        try validateUTC(build.recordedAtUTC)
        guard let accepted = build.acceptedFoundationArtifactSHA256 else {
            throw PerformanceValidationError.invalid("comparison build requires accepted foundation artifact")
        }
        try require(isHex(accepted, count: 64), "comparison foundation artifact must be lowercase 64-hex")
    }

    private static func validateMeasurementReportHashes(_ baseline: String, _ candidate: String) throws {
        try require(isHex(baseline, count: 64), "baseline measurement report hash must be lowercase 64-hex")
        try require(isHex(candidate, count: 64), "candidate measurement report hash must be lowercase 64-hex")
        try require(baseline != candidate, "baseline and candidate measurement report hashes must differ")
    }

    private static func validateRun(_ run: PerformanceRunProvenance, expectedVariant: String) throws {
        try require(run.variant == expectedVariant, "comparison run variant must be \(expectedVariant)")
        try require(!run.outputRoot.isEmpty, "comparison run output root is required")
        try require(!run.foundationProvenancePath.isEmpty, "comparison foundation provenance path is required")
        try require(!run.harnessVersion.isEmpty, "comparison run harnessVersion is required")
        try require(!run.buildContractVersion.isEmpty, "comparison run build contract is required")
        try validateFoundation(run.foundation)
        try validateUTC(run.recordedAtUTC)
        try require(run.acceptedFoundationArtifactSHA256 == run.build.acceptedFoundationArtifactSHA256, "comparison run/build artifact mismatch")
        try validateHost(run.host)
    }

    static func validateEligibility(
        _ eligibility: PerformancePairEligibility,
        baseline: PerformanceRunProvenance,
        candidate: PerformanceRunProvenance,
        foundation: FoundationIdentity,
        harnessVersion: String,
        buildContractVersion: String
    ) throws {
        try require(!eligibility.baselineRoot.isEmpty && !eligibility.candidateRoot.isEmpty, "pair roots are required")
        try require(eligibility.baselineRoot == baseline.outputRoot, "baseline eligibility root mismatch")
        try require(eligibility.candidateRoot == candidate.outputRoot, "candidate eligibility root mismatch")
        try require(isHex(eligibility.baselineCommitSHA, count: 40), "baseline eligibility commit must be lowercase 40-hex")
        try require(isHex(eligibility.candidateCommitSHA, count: 40), "candidate eligibility commit must be lowercase 40-hex")
        try require(eligibility.baselineCommitSHA != eligibility.candidateCommitSHA, "eligibility commit identities must differ")
        try require(eligibility.baselineCommitSHA == baseline.build.sourceIdentity.value, "baseline eligibility commit mismatch")
        try require(eligibility.candidateCommitSHA == candidate.build.sourceIdentity.value, "candidate eligibility commit mismatch")
        try require(eligibility.foundationProvenance.foundation == foundation, "eligibility foundation mismatch")
        try require(!eligibility.foundationProvenance.path.isEmpty, "eligibility foundation path is required")
        try require(eligibility.foundationProvenance.path == baseline.foundationProvenancePath, "baseline eligibility foundation path mismatch")
        try require(eligibility.foundationProvenance.path == candidate.foundationProvenancePath, "candidate eligibility foundation path mismatch")
        try require(isHex(eligibility.foundationProvenance.checkpointCommitSHA, count: 40), "foundation checkpoint must be lowercase 40-hex")
        try require(isHex(eligibility.foundationProvenance.fullSourceManifestSHA256, count: 64), "foundation source manifest must be lowercase 64-hex")
        try require(eligibility.foundationProvenance.harnessVersion == harnessVersion, "eligibility harness mismatch")
        try require(eligibility.foundationProvenance.buildContractVersion == buildContractVersion, "eligibility build contract mismatch")
    }

    private static func validateMetrics(_ metrics: [MetricComparison], baselineID: String, candidateID: String, host: String, expectedPairCount: Int, seed: UInt64, resampleCount: Int) throws {
        try require(metrics.count == PerformanceMetricID.allCases.count, "comparison must contain every metric exactly once")
        let ids = metrics.map(\.metricID)
        try require(Set(ids).count == PerformanceMetricID.allCases.count, "comparison metric IDs must be unique")
        try require(Set(ids) == Set(PerformanceMetricID.allCases), "comparison metric IDs are incomplete")
        for metric in metrics {
            try require(metric.baselineID == baselineID, "metric baseline ID mismatch")
            try require(metric.candidateID == candidateID, "metric candidate ID mismatch")
            try require(metric.unit == metric.metricID.canonicalUnit, "metric unit does not match its canonical unit")
            try require(metric.baselineSamples.count == expectedPairCount && metric.candidateSamples.count == expectedPairCount, "paired metric arrays must contain exactly totalPairs samples")
            try require(metric.baselineSamples.allSatisfy { $0.isFinite && $0 > 0 } && metric.candidateSamples.allSatisfy { $0.isFinite && $0 > 0 }, "metric samples must be finite and positive")
            if let canonicalBudget = metric.metricID.canonicalBudgetLimit {
                guard let budgetLimit = metric.budgetLimit else {
                    throw PerformanceValidationError.invalid("metric requires its canonical budget limit")
                }
                try require(budgetLimit.isFinite && budgetLimit > 0 && budgetLimit == canonicalBudget, "metric budget limit does not match its canonical budget")
            } else {
                try require(metric.budgetLimit == nil, "metric does not permit an absolute budget limit")
            }
            try require(metric.bootstrapInterval.lowerDelta.isFinite && metric.bootstrapInterval.upperDelta.isFinite, "bootstrap bounds must be finite")
            try require(metric.bootstrapInterval.lowerDelta <= metric.bootstrapInterval.upperDelta, "bootstrap bounds are incoherent")
            try require(metric.bootstrapInterval.seed == seed, "metric bootstrap seed mismatch")
            try require(metric.bootstrapInterval.resampleCount == resampleCount && resampleCount > 0, "metric bootstrap resample count mismatch")
            try validateDerivedArrays(metric)
            try validateEvidence(metric, host: host)
        }
    }

    private static func validateDerivedArrays(_ metric: MetricComparison) throws {
        try require(!metric.ratios.isEmpty && !metric.deltas.isEmpty, "ratios and deltas are required")
        try require(metric.ratios.count == metric.baselineSamples.count && metric.deltas.count == metric.baselineSamples.count, "derived metric arrays must align")
        for index in metric.baselineSamples.indices {
            let baseline = metric.baselineSamples[index]
            let candidate = metric.candidateSamples[index]
            let ratio = metric.ratios[index]
            let delta = metric.deltas[index]
            try require(ratio.isFinite && delta.isFinite, "derived metric values must be finite")
            try require(abs(delta - (candidate - baseline)) <= max(1e-12, abs(candidate - baseline) * 1e-12), "metric delta is not derived from samples")
            let expectedRatio = candidate / baseline
            try require(abs(ratio - expectedRatio) <= max(1e-12, abs(expectedRatio) * 1e-12), "metric ratio is not derived from samples")
        }
    }

    private static func validateEvidence(_ metric: MetricComparison, host: String) throws {
        switch metric.evidenceClass {
        case .deterministic:
            try require(metric.manualEvidence == nil, "deterministic metrics cannot carry manual evidence")
        case .manual:
            guard let evidence = metric.manualEvidence else {
                throw PerformanceValidationError.invalid("manual metrics require evidence")
            }
            try require(evidence.metricID == metric.metricID, "manual evidence metric ID mismatch")
            try require(evidence.evidenceClass == .manual, "manual evidence class mismatch")
            try require(evidence.host == host, "manual evidence host mismatch")
            try require(!evidence.recordedAt.isEmpty, "manual evidence timestamp is required")
            try validateUTC(evidence.recordedAt)
            try require(!evidence.permissions.isEmpty && evidence.permissions.allSatisfy { !$0.isEmpty }, "manual evidence permissions are required")
            try require(!evidence.steps.isEmpty, "manual evidence steps are required")
            try require(!evidence.samples.isEmpty && evidence.samples.allSatisfy { $0.isFinite }, "manual evidence samples are required and finite")
            try require(!evidence.result.isEmpty, "manual evidence result is required")
            try require(!evidence.evidencePath.isEmpty, "manual evidence path is required")
        }
    }

    private static func validateResilience(_ resilience: ResilienceMeasurement) throws {
        try require(resilience.status == .measured, "comparison resilience must be measured")
        try require(!resilience.cases.isEmpty, "comparison resilience requires cases")
        let identifiers = resilience.cases.map(\.identifier)
        try require(Set(identifiers).count == identifiers.count, "resilience case IDs must be unique")
        for testCase in resilience.cases {
            try require(!testCase.identifier.isEmpty, "resilience case identifier is required")
            try require(testCase.status == .measured, "resilience cases must be measured")
            try require(testCase.iterationCount > 0, "resilience iteration count must be positive")
            try validateResources(testCase.peakResourceCounts)
            try validateResources(testCase.endResourceCounts)
            try require(testCase.peakResourceCounts.overlays >= testCase.endResourceCounts.overlays, "resilience overlay counts are incoherent")
            try require(testCase.peakResourceCounts.timers >= testCase.endResourceCounts.timers, "resilience timer counts are incoherent")
            try require(testCase.peakResourceCounts.handlers >= testCase.endResourceCounts.handlers, "resilience handler counts are incoherent")
            try require(testCase.peakResourceCounts.windows >= testCase.endResourceCounts.windows, "resilience window counts are incoherent")
            try require(testCase.peakResourceCounts.observers >= testCase.endResourceCounts.observers, "resilience observer counts are incoherent")
        }
    }

    private static func validateFixtures(_ baseline: FixtureIdentity, _ candidate: FixtureIdentity, configuration: PerformanceConfiguration) throws {
        try require(baseline == candidate, "baseline/candidate fixture mismatch")
        try require(!baseline.identifier.isEmpty, "comparison fixture identifier is required")
        try require(baseline.markCount > 0 && baseline.continuationSamples > 0 && baseline.warmupCount >= 0 && baseline.trialCount > 0, "comparison fixture values are invalid")
        try require(baseline.markCount == configuration.fixtureMarkCount, "comparison fixture mark count does not match configuration")
        try require(baseline.continuationSamples == configuration.samplesPerGesture, "comparison fixture sample count does not match configuration")
        try require(baseline.warmupCount == configuration.warmupCount, "comparison fixture warmup count does not match configuration")
        try require(baseline.trialCount == configuration.trialCount, "comparison fixture trial count does not match configuration")
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

    private static func sameMeasurementEnvironment(_ baseline: MeasurementIdentity, _ candidate: MeasurementIdentity) -> Bool {
        baseline.hostModel == candidate.hostModel
            && baseline.macOSVersion == candidate.macOSVersion
            && baseline.xcodeVersion == candidate.xcodeVersion
            && baseline.developerDirectory == candidate.developerDirectory
            && baseline.powerState == candidate.powerState
            && baseline.displayState == candidate.displayState
            && baseline.buildConfiguration == candidate.buildConfiguration
    }

    private static func validateFoundation(_ foundation: FoundationIdentity) throws {
        try require(!foundation.identity.isEmpty && !foundation.version.isEmpty, "foundation identity and version are required")
    }

    private static func validateHost(_ host: HostIdentity) throws {
        try require(!host.machineIdentifier.isEmpty && !host.processArchitecture.isEmpty, "host identity is incomplete")
        try require(!host.connectedDisplayUUIDs.isEmpty && host.connectedDisplayUUIDs.allSatisfy { !$0.isEmpty }, "host display identity is incomplete")
    }

    private static func validateResources(_ resources: ResourceCounts) throws {
        try require(resources.overlays >= 0 && resources.timers >= 0 && resources.handlers >= 0 && resources.windows >= 0 && resources.observers >= 0, "resource counts must be nonnegative")
    }

    private static func validateUTC(_ value: String) throws {
        try require(!value.isEmpty && value.hasSuffix("Z"), "timestamp must be UTC")
        try require(ISO8601DateFormatter().date(from: value) != nil, "timestamp must be ISO-8601")
    }

    private static func isHex(_ value: String, count: Int) -> Bool {
        value.count == count && value.unicodeScalars.allSatisfy { hexCharacters.contains($0) }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw PerformanceValidationError.invalid(message)
        }
    }
}
