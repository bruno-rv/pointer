import Foundation
import CryptoKit

@MainActor
public enum PerformanceComparisonHarness {
    public static func preflight(
        baseline: PerformanceMeasurementReport,
        candidate: PerformanceMeasurementReport,
        configuration: PerformanceConfiguration,
        eligibility: PerformancePairEligibility
    ) throws {
        // Completion validation is deliberately before any comparison object or
        // output path is touched. A diagnostic report cannot be promoted into a
        // paired result by filling failed values with defaults.
        try baseline.validateCompletion()
        try candidate.validateCompletion()

        try require(configuration == .standard, "comparison requires the standard configuration")
        try require(baseline.reportKind == .measurement && candidate.reportKind == .measurement, "comparison inputs must be measurement reports")
        try require(baseline.runProvenance.variant == "baseline", "baseline run variant must be baseline")
        try require(candidate.runProvenance.variant == "candidate", "candidate run variant must be candidate")
        try require(baseline.fixture == candidate.fixture, "baseline/candidate fixture mismatch")
        try require(baseline.host == candidate.host, "baseline/candidate host mismatch")
        try require(baseline.harnessVersion == candidate.harnessVersion, "baseline/candidate harness mismatch")
        try require(baseline.foundationIdentity == candidate.foundationIdentity, "baseline/candidate foundation mismatch")
        try require(baseline.buildContractVersion == candidate.buildContractVersion, "baseline/candidate build contract mismatch")
        try require(baseline.identity.sourceCommitSHA == baseline.buildProvenance.sourceIdentity.value, "baseline measurement identity does not match build provenance")
        try require(candidate.identity.sourceCommitSHA == candidate.buildProvenance.sourceIdentity.value, "candidate measurement identity does not match build provenance")
        try require(baseline.identity.contentManifestSHA256 == nil && candidate.identity.contentManifestSHA256 == nil, "comparison requires commit measurement identities")
        try require(baseline.identity.buildConfiguration == "release" && candidate.identity.buildConfiguration == "release", "comparison requires Release measurement identities")
        try require(sameMeasurementEnvironment(baseline.identity, candidate.identity), "baseline/candidate measurement environment mismatch")
        try require(baseline.runProvenance.configuration == configuration, "baseline configuration mismatch")
        try require(candidate.runProvenance.configuration == configuration, "candidate configuration mismatch")
        try require(baseline.identity.sourceCommitSHA != nil && candidate.identity.sourceCommitSHA != nil, "comparison requires immutable commit identities")
        try require(baseline.identity.sourceCommitSHA != candidate.identity.sourceCommitSHA, "baseline and candidate commits must differ")

        try PerformanceComparisonReportValidator.validateEligibility(
            eligibility,
            baseline: baseline.runProvenance,
            candidate: candidate.runProvenance,
            foundation: baseline.foundationIdentity,
            harnessVersion: baseline.harnessVersion,
            buildContractVersion: baseline.buildContractVersion
        )
        try require(eligibility.baselineCommitSHA == baseline.identity.sourceCommitSHA, "baseline eligibility does not match measurement identity")
        try require(eligibility.candidateCommitSHA == candidate.identity.sourceCommitSHA, "candidate eligibility does not match measurement identity")
        try require(baseline.runProvenance.acceptedFoundationArtifactSHA256 == candidate.runProvenance.acceptedFoundationArtifactSHA256, "baseline/candidate foundation artifact mismatch")
    }

    static func compare(
        baseline: PerformanceMeasurementReport,
        candidate: PerformanceMeasurementReport,
        configuration: PerformanceConfiguration,
        eligibility: PerformancePairEligibility
    ) throws -> PerformanceComparisonDraft {
        try preflight(baseline: baseline, candidate: candidate, configuration: configuration, eligibility: eligibility)
        throw PerformanceValidationError.invalid("comparison calculations are deferred to Task 3")
    }

    public static func writeComparison(
        draft: PerformanceComparisonDraft,
        baselineURL: URL,
        candidateURL: URL,
        outputDirectory: URL,
        configuration: PerformanceConfiguration,
        eligibility: PerformancePairEligibility
    ) throws -> PerformanceComparisonReport {
        let baselineData = try Data(contentsOf: baselineURL)
        let candidateData = try Data(contentsOf: candidateURL)
        let baselineHash = sha256(baselineData)
        let candidateHash = sha256(candidateData)
        let baseline = try JSONDecoder().decode(PerformanceMeasurementReport.self, from: baselineData)
        let candidate = try JSONDecoder().decode(PerformanceMeasurementReport.self, from: candidateData)
        try preflight(baseline: baseline, candidate: candidate, configuration: configuration, eligibility: eligibility)
        try validateDraftBindings(draft, baseline: baseline, candidate: candidate, eligibility: eligibility)
        let report = PerformanceComparisonReport(draft: draft, baselineMeasurementReportSHA256: baselineHash, candidateMeasurementReportSHA256: candidateHash)
        try report.validateCompletion()

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appendingPathComponent("paired-comparison.json")
        let comparisonData = try JSONEncoder().encode(report)
        try comparisonData.write(to: outputURL, options: .atomic)
        return report
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw PerformanceValidationError.invalid(message)
        }
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

    private static func validateDraftBindings(
        _ draft: PerformanceComparisonDraft,
        baseline: PerformanceMeasurementReport,
        candidate: PerformanceMeasurementReport,
        eligibility: PerformancePairEligibility
    ) throws {
        try require(draft.baselineID == baseline.identity.sourceCommitSHA, "baseline comparison ID does not match decoded measurement")
        try require(draft.candidateID == candidate.identity.sourceCommitSHA, "candidate comparison ID does not match decoded measurement")
        try require(draft.baselineMeasurementIdentity == baseline.identity, "baseline measurement identity mismatch")
        try require(draft.candidateMeasurementIdentity == candidate.identity, "candidate measurement identity mismatch")
        try require(draft.baselineFixture == baseline.fixture, "baseline fixture mismatch")
        try require(draft.candidateFixture == candidate.fixture, "candidate fixture mismatch")
        try require(draft.baselineBuildProvenance == baseline.buildProvenance, "baseline build provenance mismatch")
        try require(draft.candidateBuildProvenance == candidate.buildProvenance, "candidate build provenance mismatch")
        try require(draft.baselineRunProvenance == baseline.runProvenance, "baseline run provenance mismatch")
        try require(draft.candidateRunProvenance == candidate.runProvenance, "candidate run provenance mismatch")
        try require(draft.baselineRunProvenance.host == baseline.host, "baseline host mismatch")
        try require(draft.candidateRunProvenance.host == candidate.host, "candidate host mismatch")
        try require(draft.baselineRunProvenance.configuration == baseline.runProvenance.configuration, "baseline configuration mismatch")
        try require(draft.candidateRunProvenance.configuration == candidate.runProvenance.configuration, "candidate configuration mismatch")
        try require(draft.harnessVersion == baseline.harnessVersion && draft.harnessVersion == candidate.harnessVersion, "comparison harness mismatch")
        try require(draft.foundationIdentity == baseline.foundationIdentity && draft.foundationIdentity == candidate.foundationIdentity, "comparison foundation mismatch")
        try require(draft.buildContractVersion == baseline.buildContractVersion && draft.buildContractVersion == candidate.buildContractVersion, "comparison build contract mismatch")
        try require(draft.pairEligibility == eligibility, "comparison pair eligibility mismatch")
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
